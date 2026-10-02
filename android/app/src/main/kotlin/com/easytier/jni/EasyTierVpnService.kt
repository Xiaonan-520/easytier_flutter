package com.easytier.jni

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import io.github.xiaonan520.easytier_flutter.TileBootstrapper
import io.github.xiaonan520.easytier_flutter.TileRuntime

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
        // Abort an in-flight tile-start orchestration; the thread frees the
        // core itself if it had already got that far.
        tileStartAborted = true
        disconnect()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** CMFA-style lifecycle broadcast: the tile listens while visible.
     *  [vpnStartBroadcastSent] pairs every STARTED with exactly one STOPPED,
     *  even when the stop lands before the TUN was ever up. */
    private fun sendVpnStateBroadcast(started: Boolean) {
        vpnStartBroadcastSent = started
        val intent = Intent(
            if (started) ACTION_VPN_STARTED else ACTION_VPN_STOPPED,
        ).setPackage(packageName)
        sendBroadcast(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        dbg("onStartCommand action=${intent?.action} instance=${intent?.getStringExtra(INSTANCE_NAME)} ip=${intent?.getStringExtra(IPV4_ADDR)}")
        // Notification "Disconnect" action with the engine gone: reuse this
        // service's own synchronous teardown path (same as stopVpn does).
        if (intent?.action == ACTION_NOTIFICATION_DISCONNECT) {
            Log.i(TAG, "disconnect requested from notification")
            TileRuntime.onVpnStopped()
            stopNow()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_TILE_START) {
            return handleTileStart()
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

        // Duplicate attach (double-tap burst): never re-establish the TUN.
        if (isRunning) {
            sendVpnStateBroadcast(started = true)
            return START_STICKY
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
        TileRuntime.onVpnRunning()
        sendVpnStateBroadcast(started = true)
        // Tile-started session: no Flutter engine exists to push notification
        // updates, so refresh the shade natively (idempotent with later
        // Dart-driven updates — same id, same channel).
        io.github.xiaonan520.easytier_flutter.NotificationHelper.postRunning(
            this,
            instanceName,
            ipv4Addr,
        )
        dbg("tun fd $fd attached to $instanceName")
        Log.i(TAG, "tun fd $fd attached to instance $instanceName")
        return START_STICKY
    }

    /**
     * Tile-initiated start with the app UI closed. The service promotes
     * itself to foreground FIRST (a QS tap is a valid FGS-start exemption),
     * then a background thread drives the same pipeline the Dart side uses:
     * parseConfig -> runNetworkInstance -> wait for virtual IP -> TUN attach.
     */
    private fun handleTileStart(): Int {
        // CMFA-style server-side mutual exclusion: a repeat TILE_START while
        // running or already starting is an idempotent no-op that re-broadcasts
        // STARTED — it must never become a stop (double-tap on a slow DHCP
        // start used to kill the freshly started service).
        if (isRunning || tileStartActive) {
            sendVpnStateBroadcast(started = true)
            return START_STICKY
        }
        // Must happen inside onStartCommand (post-O rule) and before any slow
        // work, or the system kills the process (ForegroundServiceDidNotStartInTime).
        startForegroundWithNotification()
        sendVpnStateBroadcast(started = true)
        tileStartActive = true
        tileStartAborted = false
        Thread {
            try {
                val snap = TileBootstrapper.load(this) ?: run {
                    Log.e(TAG, "tile start without snapshot")
                    TileRuntime.setPhase(TileRuntime.Phase.ERROR, "No saved profile for tile start")
                    stopNowSafely()
                    return@Thread
                }
                if (tileStartAborted) return@Thread
                // Same validation step the Dart orchestrator runs first.
                if (EasyTierJNI.parseConfig(snap.toml) != 0) {
                    val err = EasyTierJNI.getLastError() ?: "config parse failed"
                    Log.e(TAG, "tile start parse failed: $err")
                    TileRuntime.setPhase(TileRuntime.Phase.ERROR, err)
                    stopNowSafely()
                    return@Thread
                }
                if (tileStartAborted) return@Thread
                if (EasyTierJNI.runNetworkInstance(snap.toml) != 0) {
                    val err = EasyTierJNI.getLastError() ?: "core start failed"
                    Log.e(TAG, "tile start core failed: $err")
                    TileRuntime.setPhase(TileRuntime.Phase.ERROR, err)
                    stopNowSafely()
                    return@Thread
                }
                if (tileStartAborted) {
                    // Stop won the race: free the core we just started.
                    EasyTierJNI.deleteNetworkInstance(snap.instanceName)
                    return@Thread
                }
                // Static profiles have the address up front; DHCP profiles
                // wait for the core to assign one (same 90s headroom as Dart).
                val addr = if (snap.dhcp) waitForVirtualIp() else withPrefix(snap.virtualIpv4)
                if (tileStartAborted) {
                    EasyTierJNI.deleteNetworkInstance(snap.instanceName)
                    return@Thread
                }
                if (addr == null) {
                    Log.e(TAG, "tile start: no virtual IP in time")
                    TileRuntime.setPhase(TileRuntime.Phase.ERROR, "Timed out waiting for a virtual IP")
                    EasyTierJNI.deleteNetworkInstance(snap.instanceName)
                    stopNowSafely()
                    return@Thread
                }
                // Second hop: reuse the normal attach path (this same service).
                val attach = Intent(this, EasyTierVpnService::class.java)
                    .putExtra(INSTANCE_NAME, snap.instanceName)
                    .putExtra(IPV4_ADDR, addr)
                if (snap.routes.isNotEmpty()) attach.putExtra(ROUTES, snap.routes.toTypedArray())
                startService(attach)
                // computePhase() flips to RUNNING once isRunning is set in
                // onStartCommand of the attach intent.
            } catch (t: Throwable) {
                Log.e(TAG, "tile start failed", t)
                TileRuntime.setPhase(TileRuntime.Phase.ERROR, t.message ?: "tile start failed")
                stopNowSafely()
            } finally {
                tileStartActive = false
            }
        }.start()
        return START_STICKY
    }

    private fun stopNowSafely() {
        try {
            stopNow()
        } catch (_: Throwable) {
        }
    }

    /** DHCP slow path: poll the core for its assigned virtual IP. */
    private fun waitForVirtualIp(): String? {
        val deadline = SystemClock.elapsedRealtime() + IP_WAIT_MS
        while (SystemClock.elapsedRealtime() < deadline) {
            try {
                val json = EasyTierJNI.collectNetworkInfos(64)
                val map = if (json != null) JSONObject(json).optJSONObject("map") else null
                if (map != null) {
                    for (key in map.keys().asSequence()) {
                        val info = map.optJSONObject(key) ?: continue
                        if (!info.optBoolean("running")) continue
                        val v4 = info.optJSONObject("my_node_info")
                            ?.optJSONObject("virtual_ipv4") ?: continue
                        val a = v4.optJSONObject("address")?.optInt("addr") ?: 0
                        if (a != 0) {
                            val ip = "${(a shr 24) and 255}.${(a shr 16) and 255}.${(a shr 8) and 255}.${a and 255}"
                            return "$ip/${v4.optInt("network_length", 24)}"
                        }
                    }
                }
            } catch (_: Throwable) {
                // Core still booting; keep polling.
            }
            SystemClock.sleep(700)
        }
        return null
    }

    private fun withPrefix(ip: String): String = if (ip.contains('/')) ip else "$ip/24"

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
        if (isRunning) {
            isRunning = false
            TileRuntime.onVpnStopped()
        }
        if (vpnStartBroadcastSent) {
            sendVpnStateBroadcast(started = false)
        }
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
        // DHCP/OSPF convergence headroom, matching the Dart orchestrator.
        private const val IP_WAIT_MS = 150_000L
        // Shared with NotificationHelper, which renders the notification
        // content for both the service and app-level state updates.
        const val CHANNEL_ID = "easytier_vpn_channel"
        const val NOTIFICATION_ID = 1356
        private const val DEFAULT_MTU = 1300
        private const val PACKAGE_SELF = "io.github.xiaonan520.easytier_flutter"

        const val ACTION_NOTIFICATION_DISCONNECT = "io.github.xiaonan520.easytier_flutter.NOTIFICATION_DISCONNECT"

        /** Tile-initiated cold start: no extras; snapshot-driven. */
        const val ACTION_TILE_START = "io.github.xiaonan520.easytier_flutter.TILE_START"

        /** Package-internal lifecycle broadcasts the tile aggregates. */
        const val ACTION_VPN_STARTED = "io.github.xiaonan520.easytier_flutter.VPN_STARTED"
        const val ACTION_VPN_STOPPED = "io.github.xiaonan520.easytier_flutter.VPN_STOPPED"

        const val INSTANCE_NAME = "instance_name"
        const val IPV4_ADDR = "ipv4_addr"
        const val ROUTES = "routes"

        @JvmStatic var isRunning: Boolean = false
            private set

        @JvmStatic var instance: EasyTierVpnService? = null
            private set
    }

    // Tile-start orchestration state; volatile: touched from the onStartCommand
    // thread, the orchestration thread and stopNow() from any caller.
    @Volatile private var tileStartActive = false
    @Volatile private var tileStartAborted = false
    @Volatile private var vpnStartBroadcastSent = false
}
