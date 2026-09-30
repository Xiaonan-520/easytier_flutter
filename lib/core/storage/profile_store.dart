import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/network_profile.dart';

/// Persists the list of network profiles plus the last-used profile id.
/// Change-notifying facade so the UI can rebuild on CRUD; the storage itself
/// is synchronous JSON under two shared_preferences keys.
class ProfileStore {
  static const _profilesKey = 'network_profiles_v1';
  static const _currentKey = 'current_profile_id_v1';

  final List<NetworkProfile> _profiles = [];
  String? _currentId;
  final _changes = StreamController<void>.broadcast();
  var _loaded = false;

  Stream<void> get changes => _changes.stream;
  List<NetworkProfile> get profiles => List.unmodifiable(_profiles);
  String? get currentId => _currentId;

  /// The profile the app should show/use; falls back to the only profile or
  /// the first one when the stored id dangles.
  NetworkProfile? get current {
    if (_profiles.isEmpty) return null;
    return _profiles.where((p) => p.id == _currentId).firstOrNull ??
        _profiles.first;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(NetworkProfile.fromJson)
            .toList();
        _profiles
          ..clear()
          ..addAll(list);
      } on FormatException {
        // Corrupt payload: start empty rather than crash the app.
      }
    }
    _currentId = prefs.getString(_currentKey);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(_profiles.map((p) => p.toJson()).toList()),
    );
    final id = _currentId;
    if (id == null) {
      await prefs.remove(_currentKey);
    } else {
      await prefs.setString(_currentKey, id);
    }
    _changes.add(null);
  }

  Future<void> add(NetworkProfile profile) async {
    await load();
    _profiles.add(profile);
    _currentId ??= profile.id;
    await _persist();
  }

  Future<void> update(NetworkProfile profile) async {
    await load();
    final i = _profiles.indexWhere((p) => p.id == profile.id);
    if (i == -1) return;
    _profiles[i] = profile;
    await _persist();
  }

  Future<void> remove(String id) async {
    await load();
    _profiles.removeWhere((p) => p.id == id);
    if (_currentId == id) {
      _currentId = _profiles.firstOrNull?.id;
    }
    await _persist();
  }

  Future<void> setCurrent(String id) async {
    await load();
    if (!_profiles.any((p) => p.id == id)) return;
    _currentId = id;
    await _persist();
  }
}
