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
import androidx.core.app.NotificationCompat

/**
 * VPN service adapted from the official EasyTier tauri-plugin-vpnservice
 * (TauriVpnService.kt) and easytier-android-jni's reference EasyTierVpnService.
 * It establishes the TUN interface and hands the fd to the EasyTier core
 * instance via EasyTierJNI.setTunFd().
 */
class EasyTierVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        disconnect()
        instance = null
        super.onDestroy()
    }

    override fun onRevoke() {
        disconnect()
        instance = null
        super.onRevoke()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val instanceName = intent?.getStringExtra(INSTANCE_NAME)
        val ipv4Addr = intent?.getStringExtra(IPV4_ADDR) ?: "10.144.144.1/24"
        val routes = intent?.getStringArrayExtra(ROUTES) ?: emptyArray()

        if (instanceName == null) {
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
            .addRoute("10.144.144.0", 24) // EasyTier default virtual network range
        for (route in routes) {
            val parts = route.split("/")
            if (parts.size == 2) builder.addRoute(parts[0], parts[1].toInt())
        }
        builder.addDisallowedApplication(PACKAGE_SELF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val descriptor = builder.establish()
            ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
        // EasyTier core now owns the raw fd (setTunFd). We remember a
        // ParcelFileDescriptor wrapper of the same fd purely so disconnect()
        // can close it when the VPN stops.
        val fd = descriptor.detachFd()
        vpnInterface = ParcelFileDescriptor.adoptFd(fd)
        return fd
    }

    private fun startForegroundWithNotification() {
        val channel = NotificationChannel(CHANNEL_ID, "EasyTier VPN", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_error) // placeholder until proper icon
            .setContentTitle("EasyTier VPN running")
            .setContentText("Virtual network is active")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .apply { contentIntent?.let(::setContentIntent) }
            .build()

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

    companion object {
        private const val TAG = "EasyTierVpnService"
        private const val CHANNEL_ID = "easytier_vpn_channel"
        private const val NOTIFICATION_ID = 1356
        private const val DEFAULT_MTU = 1300
        private const val PACKAGE_SELF = "io.github.xiaonan520.easytier_flutter"

        const val INSTANCE_NAME = "instance_name"
        const val IPV4_ADDR = "ipv4_addr"
        const val ROUTES = "routes"

        @JvmStatic var isRunning: Boolean = false
            private set

        @JvmStatic var instance: EasyTierVpnService? = null
            private set
    }
}
