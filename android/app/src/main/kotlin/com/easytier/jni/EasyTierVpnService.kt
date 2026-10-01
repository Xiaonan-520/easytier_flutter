package com.easytier.jni

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * VPN service adapted from the official EasyTier tauri-plugin-vpnservice
 * (TauriVpnService.kt) and easytier-android-jni's reference EasyTierVpnService.
 * It establishes the TUN interface and hands the fd to the EasyTier core
 * instance via EasyTierJNI.setTunFd().
 */
class EasyTierVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null

    private fun dbg(msg: String) {
        try {
            java.io.File(getExternalFilesDir(null), "vpn_dbg.log")
                .appendText("${System.currentTimeMillis()} $msg\n")
        } catch (_: Throwable) {}
    }

    override fun onCreate() {
        super.onCreate()
        dbg("onCreate")
        instance = this
    }

    override fun onDestroy() {
        dbg("onDestroy")
        Log.i(TAG, "onDestroy")
        disconnect()
        stopForeground(STOP_FOREGROUND_REMOVE)
        instance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        dbg("onRevoke")
        Log.i(TAG, "onRevoke")
        disconnect()
        stopForeground(STOP_FOREGROUND_REMOVE)
        instance = null
        super.onRevoke()
    }

    /**
     * Synchronous teardown called from MainActivity before stopService().
     * stopService() alone was observed (Huawei EMUI 10) never to invoke
     * onDestroy, leaking the TUN fd and the foreground notification — the
     * official VpnServicePlugin does the same self?.onRevoke() dance.
     */
    fun stopNow() {
        Log.i(TAG, "stopNow")
        disconnect()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        dbg("onStartCommand action=${intent?.action} instance=${intent?.getStringExtra(INSTANCE_NAME)} ip=${intent?.getStringExtra(IPV4_ADDR)}")
        // Notification "Disconnect" action with the engine gone: reuse this
        // service's own synchronous teardown path (same as stopVpn does).
        if (intent?.action == ACTION_NOTIFICATION_DISCONNECT) {
            Log.i(TAG, "disconnect requested from notification")
            stopNow()
            return START_NOT_STICKY
        }

        val instanceName = intent?.getStringExtra(INSTANCE_NAME)
        val ipv4Addr = intent?.getStringExtra(IPV4_ADDR) ?: "10.144.144.1/24"
        val routes = intent?.getStringArrayExtra(ROUTES) ?: emptyArray()

        if (instanceName == null) {
            dbg("missing instance_name")
            Log.e(TAG, "missing instance_name, stopping")
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundWithNotification()

        val fd: Int
        try {
            fd = createVpnInterface(ipv4Addr, routes)
        } catch (t: Throwable) {
            Log.e(TAG, "establish vpn interface failed", t)
            stopSelf()
            return START_NOT_STICKY
        }

        val code = EasyTierJNI.setTunFd(instanceName, fd)
        if (code != 0) {
            Log.e(TAG, "setTunFd failed: ${EasyTierJNI.getLastError()}")
            stopSelf()
            return START_NOT_STICKY
        }
        isRunning = true
        dbg("tun fd $fd attached to $instanceName")
        Log.i(TAG, "tun fd $fd attached to instance $instanceName")
        return START_STICKY
    }

    private fun createVpnInterface(ipv4Addr: String, routes: Array<String>): Int {
        val ipParts = ipv4Addr.split("/")
        require(ipParts.size == 2) { "invalid ipv4 addr: $ipv4Addr" }

        val builder = Builder()
            .setSession("EasyTier")
            .setMtu(DEFAULT_MTU)
            .addAddress(ipParts[0], ipParts[1].toInt())
            .addAddress("fd00::1", 128)
        // Route for the local virtual subnet, derived from the assigned address
        // (the old hardcoded 10.144.144.0/24 broke any other addressing plan).
        subnetOf(ipParts[0], ipParts[1].toInt())?.let { (net, prefix) ->
            builder.addRoute(net, prefix)
        }
        for (route in routes) {
            val parts = route.split("/")
            if (parts.size == 2) builder.addRoute(parts[0], parts[1].toInt())
        }
        builder.addDisallowedApplication(PACKAGE_SELF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val descriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
        // Keep ownership of the PFD. The Rust core opens the fd with
        // close_fd_on_drop(false), so the Java side must close it on stop —
        // otherwise tun0 and the system VPN network leak after disconnect.
        vpnInterface = descriptor
        return descriptor.fd
    }

    private fun startForegroundWithNotification() {
        val channel = NotificationChannel(CHANNEL_ID, "EasyTier VPN", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)

        // Content is owned by NotificationHelper (driven from the Dart state
        // machine); here we only promote the service to foreground.
        val notification = io.github.xiaonan520.easytier_flutter.NotificationHelper
            .buildForeground(this)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun disconnect() {
        vpnInterface?.let {
            try { it.close() } catch (_: Exception) {}
        }
        vpnInterface = null
        isRunning = false
    }

    /** "a.b.c.d" + prefix -> network base address and prefix, e.g. ("10.144.144.0", 24). */
    private fun subnetOf(ip: String, prefix: Int): Pair<String, Int>? {
        val o = ip.split(".").map { it.toIntOrNull() ?: return null }
        if (o.size != 4 || o.any { it < 0 || it > 255 } || prefix !in 0..32) return null
        val addr = ((o[0] shl 24) or (o[1] shl 16) or (o[2] shl 8) or o[3])
        val mask = if (prefix == 0) 0 else -(1 shl (32 - prefix))
        val net = addr and mask
        return Pair(
            "${(net ushr 24) and 255}.${(net ushr 16) and 255}.${(net ushr 8) and 255}.${net and 255}",
            prefix,
        )
    }

    companion object {
        private const val TAG = "EasyTierVpnService"
        // Shared with NotificationHelper, which renders the notification
        // content for both the service and app-level state updates.
        const val CHANNEL_ID = "easytier_vpn_channel"
        const val NOTIFICATION_ID = 1356
        private const val DEFAULT_MTU = 1300
        private const val PACKAGE_SELF = "io.github.xiaonan520.easytier_flutter"

        const val ACTION_NOTIFICATION_DISCONNECT = "io.github.xiaonan520.easytier_flutter.NOTIFICATION_DISCONNECT"

        const val INSTANCE_NAME = "instance_name"
        const val IPV4_ADDR = "ipv4_addr"
        const val ROUTES = "routes"

        @JvmStatic var isRunning: Boolean = false
            private set

        @JvmStatic var instance: EasyTierVpnService? = null
            private set
    }
}
