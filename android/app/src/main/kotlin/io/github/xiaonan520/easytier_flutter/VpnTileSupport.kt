package io.github.xiaonan520.easytier_flutter

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.service.quicksettings.TileService
import com.easytier.jni.EasyTierVpnService

/**
 * Runtime state shared between the Quick Settings tile, the VPN service and
 * the Flutter layer. All three live in the same process (the EasyTier core
 * runs in-process through JNI), so a plain singleton is enough. The app UI
 * reconciles through its existing 3s status poll, so no extra Dart-facing
 * channel is needed.
 *
 * [phase] is only a *sticky hint* so the asynchronous STARTING/STOPPING
 * windows survive between transitions; the source of truth remains
 * [EasyTierVpnService.isRunning] — see [computePhase].
 */
object TileRuntime {
    enum class Phase { IDLE, STARTING, RUNNING, STOPPING, ERROR }

    // DHCP/OSPF slow path was observed at ~90s; give it headroom.
    private const val START_TIMEOUT_MS = 150_000L

    @Volatile
    var phase: Phase = Phase.IDLE
        private set

    @Volatile
    var errorMessage: String? = null
        private set

    @Volatile
    private var startBeganAt = 0L

    @Volatile
    private var appContext: Context? = null

    /** Cache the app context from whichever component comes up first. */
    fun attach(context: Context) {
        appContext = context.applicationContext
    }

    /** Sticky transition; truth is re-derived in [computePhase].
     *  Same-phase calls are ignored so the notification mirror pushed by
     *  Dart cannot bounce events back and forth in a loop. */
    fun setPhase(p: Phase, message: String? = null) {
        if (p == phase && p != Phase.ERROR) return
        if (p == Phase.STARTING) startBeganAt = SystemClock.elapsedRealtime()
        if (p == Phase.ERROR) errorMessage = message
        phase = p
        requestTileRefresh()
    }

    /**
     * The tile-facing truth: a live TUN always wins; the sticky phase covers
     * the windows where the service flag cannot (tile-initiated start/stop).
     * The STARTING backstop guards against an orchestration thread dying
     * without a terminal transition.
     */
    fun computePhase(): Phase {
        if (phase == Phase.STARTING &&
            SystemClock.elapsedRealtime() - startBeganAt > START_TIMEOUT_MS
        ) {
            phase = Phase.IDLE
        }
        if (EasyTierVpnService.isRunning) return Phase.RUNNING
        return phase
    }

    /** Hook from the VPN service once the TUN is really up. */
    fun onVpnRunning() = setPhase(Phase.RUNNING)

    /** Hook from the VPN service when the TUN is gone. */
    fun onVpnStopped() {
        if (phase != Phase.STOPPING) setPhase(Phase.IDLE)
    }

    fun requestTileRefresh() {
        val context = appContext ?: return
        TileService.requestListeningState(
            context,
            android.content.ComponentName(context, EasyTierTileService::class.java),
        )
    }
}

/**
 * The "last used profile" handoff between the Flutter UI and the tile.
 *
 * Rendering a profile into TOML is Dart-only logic (NetworkConfig.toToml),
 * so the app stores the fully rendered snapshot — plus what the VPN service
 * needs — into shared_preferences before starting the core. The tile reads
 * it back with no Flutter engine running. commit() on purpose: the write
 * must be durable before a tile tap can rely on it. Stored under the
 * FlutterSharedPreferences file so the existing app backup rules cover it.
 */
object TileBootstrapper {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.tile_snapshot_v1"

    data class Snapshot(
        val profileId: String,
        val displayName: String,
        val instanceName: String,
        val toml: String,
        val dhcp: Boolean,
        val virtualIpv4: String,
        val routes: List<String>,
    )

    fun save(context: Context, json: String) {
        prefs(context).edit().putString(KEY, json).commit()
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(KEY).commit()
    }

    fun load(context: Context): Snapshot? = try {
        val json = prefs(context).getString(KEY, null) ?: return null
        val o = org.json.JSONObject(json)
        Snapshot(
            profileId = o.optString("profileId"),
            displayName = o.optString("displayName"),
            instanceName = o.optString("instanceName"),
            toml = o.getString("toml"),
            dhcp = o.optBoolean("dhcp"),
            virtualIpv4 = o.optString("virtualIpv4"),
            routes = o.optJSONArray("routes")?.let { arr ->
                (0 until arr.length())
                    .mapNotNull { arr.optString(it).takeIf(String::isNotEmpty) }
            } ?: emptyList(),
        )
    } catch (_: Throwable) {
        // Corrupt payload: the tile falls back to opening the app.
        null
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
