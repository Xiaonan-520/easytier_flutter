import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/network_config.dart';

/// Persists the single network profile locally.
class ConfigStore {
  static const _key = 'network_config_v1';

  Future<NetworkConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const NetworkConfig();
    try {
      return NetworkConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const NetworkConfig();
    }
  }

  Future<void> save(NetworkConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}
