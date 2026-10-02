import 'package:flutter/services.dart';

/// Launcher for the system settings pages that govern background execution.
///
/// HarmonyOS 4 hides the stock entry points behind vendor components that
/// differ between devices and OS versions, so every jump probes availability
/// on the native side first and falls back through progressively more general
/// pages. Nothing here can crash the UI or claim a state it cannot verify.
class BackgroundLaunch {
  BackgroundLaunch._();

  static const _channel = MethodChannel('easytier_flutter/core');

  static Future<Object?>? _invoke(String method) async {
    try {
      return await _channel.invokeMethod(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Vendor "startup manager" when present (EMUI/HarmonyOS 应用启动管理),
  /// else the app's system settings page. Returns whether anything opened.
  static Future<bool> openBackgroundActivitySettings() async =>
      await _invoke('openBackgroundActivitySettings') == true;

  /// Battery-optimization exemption: the standard request dialog when the
  /// optimization is still active, else the full exemption list page.
  /// Returns whether anything opened.
  static Future<bool> openBatteryOptimizationSettings() async =>
      await _invoke('openBatteryOptimizationSettings') == true;

  /// Verified battery-optimization state (PowerManager). null means the
  /// state could not be detected — callers must show that, never a fake
  /// "allowed".
  static Future<bool?> isIgnoringBatteryOptimizations() async =>
      await _invoke('isIgnoringBatteryOptimizations') == null
          ? null
          : await _invoke('isIgnoringBatteryOptimizations') == true;
}
