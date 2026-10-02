package io.github.xiaonan520.easytier_flutter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.core.content.ContextCompat
import com.easytier.jni.EasyTierJNI
import com.easytier.jni.EasyTierVpnService

/**
 * Quick Settings tile, following the CMFA architecture: the tile is a pure
 * "intent launcher + broadcast aggregator".
 *
 * - onClick decides from [Tile.getState] (the UI truth the user sees), never
 *   from an in-process sticky state — a second tap while the first start is
 *   still connecting must not flip into a stop.
 * - The colour flip is driven by the VPN service's own lifecycle broadcasts
 *   (ACTION_VPN_STARTED / ACTION_VPN_STOPPED) received while listening — no
 *   requestListeningState round-trip, which HarmonyOS does not honour.
 * - Truth is calibrated once per listening window from the in-process
 *   [EasyTierVpnService.isRunning] (CMFA's StatusClient analog).
 *
 * START hands off to [EasyTierVpnService] via ACTION_TILE_START; the service
 * promotes itself to foreground first, broadcasts STARTED (tile turns active
 * immediately), then a background thread runs the core. STOP is the
 * same-process equivalent of CMFA's stop broadcast: synchronous teardown
 * through [EasyTierVpnService.stopNow] (whose onDestroy broadcasts STOPPED
 * and greys the tile), then the core instance is freed through the same JNI
 * path the app uses.
 *
 * When no usable snapshot exists or VPN consent is missing, the tile opens
 * the app instead — consent is never bypassed (official behaviour).
 */
class EasyTierTileService : TileService() {

    private var vpnRunning = false
    private var profileLabel = ""

    /** Live only during a listening window, like CMFA's TileService. */
    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                EasyTierVpnService.ACTION_VPN_STARTED -> vpnRunning = true
                EasyTierVpnService.ACTION_VPN_STOPPED -> vpnRunning = false
            }
            updateTile()
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        Log.i(TAG, "onStartListening")
        ContextCompat.registerReceiver(
            applicationContext,
            stateReceiver,
            IntentFilter().apply {
                addAction(EasyTierVpnService.ACTION_VPN_STARTED)
                addAction(EasyTierVpnService.ACTION_VPN_STOPPED)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        vpnRunning = EasyTierVpnService.isRunning
        profileLabel = TileBootstrapper.load(applicationContext)?.displayName ?: ""
        updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        Log.i(TAG, "onStopListening")
        try {
            unregisterReceiver(stateReceiver)
        } catch (_: IllegalArgumentException) {
        }
    }

    override fun onClick() {
        super.onClick()
        Log.i(TAG, "onClick state=${qsTile?.state}")
        val tile = qsTile ?: return
        when (tile.state) {
            Tile.STATE_ACTIVE -> stopVpn()
            else -> startVpn()
        }
    }

    /** Tile long-press "App settings" opens the app, like CMFA does. */
    override fun onTileAdded() {
        super.onTileAdded()
        Log.i(TAG, "onTileAdded")
        updateTile()
    }

    // ------------------------------------------------------------------ //

    private fun startVpn() {
        val snapshot = TileBootstrapper.load(applicationContext)
        if (snapshot == null || VpnService.prepare(this) != null) {
            // No snapshot or consent still missing: route through the
            // app UI — never bypass VpnService.prepare().
            startApp()
            return
        }
        val svc = Intent(this, EasyTierVpnService::class.java)
            .setAction(EasyTierVpnService.ACTION_TILE_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(svc)
        } else {
            startService(svc)
        }
        // Colour flips when the service answers with ACTION_VPN_STARTED.
    }

    private fun stopVpn() {
        // 1. Tear the TUN down synchronously (EMUI stopService gap), then
        //    2. stop the service — its onDestroy broadcasts ACTION_VPN_STOPPED
        //    and the tile greys out, and
        //    3. free the core through the same JNI path the app uses.
        EasyTierVpnService.instance?.stopNow()
        stopService(Intent(this, EasyTierVpnService::class.java))
        Thread {
            try {
                val snapshot = TileBootstrapper.load(applicationContext)
                val instance = snapshot?.instanceName
                    ?: DEFAULT_INSTANCE_NAME
                EasyTierJNI.deleteNetworkInstance(instance)
            } catch (t: Throwable) {
                Log.e(TAG, "tile core teardown failed", t)
            }
        }.start()
    }

    private fun startApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        intent?.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        if (intent != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // API 34+ requires the PendingIntent overload.
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this, 0, intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        tile.state = if (vpnRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.subtitle = if (vpnRunning) {
            profileLabel.ifEmpty { getString(R.string.tile_subtitle_connected) }
        } else {
            null
        }
        tile.updateTile()
    }

    companion object {
        private const val TAG = "EasyTierTileService"
        private const val DEFAULT_INSTANCE_NAME = "easytier_flutter_default"
    }
}
