package io.github.xiaonan520.easytier_flutter

import android.content.Intent
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        stopService(Intent(this, EasyTierVpnService::class.java))
                        result.success(true)
                    }
                    "isVpnRunning" -> result.success(EasyTierVpnService.isRunning)
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

    companion object {
        private const val REQUEST_VPN_PERMISSION = 1001
    }
}
