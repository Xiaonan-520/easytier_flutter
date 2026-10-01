import 'package:flutter/material.dart';

import '../core/storage/theme_store.dart';
import 'theme.dart';

/// Owns the selected [ThemePreset] and [ThemeMode], persists both, and
/// rebuilds the app whenever either changes.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _load();
  }

  final _store = ThemeStore();

  ThemePreset _preset = ThemePreset.byId('default');
  ThemeMode _mode = ThemeMode.system;
  var _loaded = false;

  ThemePreset get preset => _preset;
  ThemeMode get mode => _mode;
  bool get loaded => _loaded;

  Future<void> _load() async {
    _preset = ThemePreset.byId(await _store.loadPresetId());
    _mode = await _store.loadMode();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPreset(ThemePreset p) async {
    if (p.id == _preset.id) return;
    _preset = p;
    notifyListeners();
    await _store.savePresetId(p.id);
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    await _store.saveMode(m);
  }
}
