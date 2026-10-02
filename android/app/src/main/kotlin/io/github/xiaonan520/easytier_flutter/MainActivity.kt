package io.github.xiaonan520.easytier_flutter

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.content.ComponentName
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.easytier.jni.EasyTierJNI
import com.easytier.jni.EasyTierVpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "easytier_flutter/core"
    private var pendingVpnResult: MethodChannel.Result? = null
    private var stateChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TileRuntime.attach(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "parseConfig" -> {
                        val code = EasyTierJNI.parseConfig(call.argument<String>("config") ?: "")
                        result.success(mapOf("code" to code.toLong(), "error" to EasyTierJNI.getLastError()))
                    }
                    "runNetworkInstance" -> {
                        val code = EasyTierJNI.runNetworkInstance(call.argument<String>("config") ?: "")
                        result.success(mapOf("code" to code.toLong(), "error" to EasyTierJNI.getLastError()))
                    }
                    "stopInstance" -> {
                        val name = call.argument<String>("name")
                        val code = if (name != null) EasyTierJNI.deleteNetworkInstance(name)
                        else EasyTierJNI.stopAllInstances()
                        result.success(mapOf("code" to code.toLong(), "error" to EasyTierJNI.getLastError()))
                    }
                    "collectNetworkInfos" -> {
                        result.success(mapOf("json" to EasyTierJNI.collectNetworkInfos(64)))
                    }
                    "prepareVpn" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pendingVpnResult = result
                            startActivityForResult(intent, REQUEST_VPN_PERMISSION)
                        } else {
                            result.success(true)
                        }
                    }
                    "startVpn" -> {
                        val intent = Intent(this, EasyTierVpnService::class.java)
                        intent.putExtra(EasyTierVpnService.INSTANCE_NAME, call.argument<String>("instanceName"))
                        intent.putExtra(EasyTierVpnService.IPV4_ADDR, call.argument<String>("ipv4Addr"))
                        intent.putExtra(EasyTierVpnService.ROUTES, call.argument<ArrayList<String>>("routes")?.toTypedArray())
                        startService(intent)
                        result.success(true)
                    }
                    "stopVpn" -> {
                        // Sync teardown first (closes TUN fd, removes
                        // notification), matching the official VpnServicePlugin:
                        // stopService() alone may never fire onDestroy.
                        EasyTierVpnService.instance?.stopNow()
                        stopService(Intent(this, EasyTierVpnService::class.java))
                        result.success(true)
                    }
                    "isVpnRunning" -> result.success(EasyTierVpnService.isRunning)
                    "tileSnapshotSave" -> {
                        // commit() (not apply()): the tile may tap before the
                        // async write lands.
                        TileBootstrapper.save(
                            this,
                            call.argument<String>("snapshot") ?: "{}",
                        )
                        result.success(true)
                    }
                    "tileSnapshotClear" -> {
                        TileBootstrapper.clear(this)
                        result.success(true)
                    }
                    "tileRuntimeState" -> {
                        result.success(
                            mapOf(
                                "phase" to TileRuntime.computePhase().name.lowercase(),
                                "error" to TileRuntime.errorMessage,
                            ),
                        )
                    }
                    "updateNotification" -> {
                        NotificationHelper.update(
                            this,
                            state = call.argument<String>("state") ?: "idle",
                            profileName = call.argument<String>("profileName") ?: "",
                            peers = call.argument<Int>("peers") ?: 0,
                            virtualIp = call.argument<String>("virtualIp") ?: "",
                            error = call.argument<String?>("error"),
                            rxRate = call.argument<Double>("rxRate") ?: 0.0,
                            txRate = call.argument<Double>("txRate") ?: 0.0,
                        )
                        result.success(true)
                    }
                    "openBackgroundActivitySettings" -> {
                        // Vendor startup managers differ across EMUI/HarmonyOS
                        // versions; HarmonyOS 4 guards the direct pages with
                        // com.huawei.permission.external_app_settings
                        // .USE_COMPONENT, so the phone-manager home is the
                        // reachable entry there. Fall back to the app's
                        // system settings page. Never throws.
                        result.success(openFirstResolved(listOf(
                            "com.huawei.systemmanager/.startupmgr.ui.StartupNormalAppListActivity",
                            "com.huawei.systemmanager/.mainscreen.MainScreenActivity",
                        )))
                    }
                    "openBatteryOptimizationSettings" -> {
                        // Standard, version-stable entry: the request dialog
                        // when the exemption is still off, else the list page.
                        val pm = getSystemService(PowerManager::class.java)
                        val ignoreIntent = Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName"),
                        )
                        val target = if (
                            pm != null &&
                            !pm.isIgnoringBatteryOptimizations(packageName) &&
                            ignoreIntent.resolveActivity(packageManager) != null
                        ) {
                            ignoreIntent
                        } else {
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        }
                        result.success(try {
                            startActivity(target); true
                        } catch (t: Throwable) {
                            Log.w("MainActivity", "battery settings failed", t); false
                        })
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(PowerManager::class.java)
                        result.success(
                            pm?.isIgnoringBatteryOptimizations(packageName),
                        )
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NATIVE_ERROR", e.message, null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_PERMISSION) {
            pendingVpnResult?.success(resultCode == RESULT_OK)
            pendingVpnResult = null
        }
    }

    /** Open the first component that actually resolves on this device;
     *  keep walking down the list when one exists but fails to open. */
    private fun openFirstResolved(components: List<String>): Boolean {
        for (c in components) {
            val intent = Intent().setComponent(ComponentName.unflattenFromString(c))
            if (intent.resolveActivity(packageManager) == null) continue
            try {
                startActivity(intent)
                return true
            } catch (t: Throwable) {
                Log.w("MainActivity", "open $c failed", t)
            }
        }
        return try {
            // Generic fallback: this app's system settings page.
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (t: Throwable) {
            Log.w("MainActivity", "app details failed", t); false
        }
    }

    companion object {
        private const val REQUEST_VPN_PERMISSION = 1001
    }
}
