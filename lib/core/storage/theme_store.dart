import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the selected theme preset id and theme mode across restarts.
class ThemeStore {
  static const _presetKey = 'theme_preset_v1';
  static const _modeKey = 'theme_mode_v1';

  Future<String> loadPresetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_presetKey) ?? 'default';
  }

  Future<void> savePresetId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, id);
  }

  /// Stored as the [ThemeMode] name; 'system' on any parse failure.
  Future<ThemeMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modeKey);
    return ThemeMode.values.asNameMap()[raw] ?? ThemeMode.system;
  }

  Future<void> saveMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }
}
