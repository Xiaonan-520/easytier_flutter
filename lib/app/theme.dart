import 'package:flutter/material.dart';

/// Material 3 theme presets. Each preset seeds a full [ColorScheme] via
/// `ColorScheme.fromSeed` for both light and dark, so text, surfaces,
/// buttons, NavigationBar, Cards etc. stay consistent and accessible —
/// same architecture as the original single-seed theme, just ×N.
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.label,
    required this.seed,
    required this.preview,
  });

  final String id;
  final String label;

  /// Seed for `ColorScheme.fromSeed`.
  final Color seed;

  /// Swatch colors shown in the picker: [primary, secondary, tertiary].
  final List<Color> preview;

  static const all = [
    ThemePreset(
      id: 'default',
      label: 'Default',
      seed: Color(0xFF2D6A4F),
      preview: [Color(0xFF2D6A4F), Color(0xFF4D7C6F), Color(0xFF3E6B5C)],
    ),
    ThemePreset(
      id: 'blue',
      label: 'Blue',
      seed: Color(0xFF1565C0),
      preview: [Color(0xFF1565C0), Color(0xFF3E6DA8), Color(0xFF3B6FA0)],
    ),
    ThemePreset(
      id: 'green',
      label: 'Green',
      seed: Color(0xFF2E7D32),
      preview: [Color(0xFF2E7D32), Color(0xFF4F7D52), Color(0xFF48704A)],
    ),
    ThemePreset(
      id: 'purple',
      label: 'Purple',
      seed: Color(0xFF6A4FA3),
      preview: [Color(0xFF6A4FA3), Color(0xFF7A5FA8), Color(0xFF705BA0)],
    ),
  ];

  static ThemePreset byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);

  ThemeData theme(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
      ),
    );
  }
}
