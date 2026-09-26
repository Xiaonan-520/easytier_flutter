import 'package:flutter/material.dart';

/// App-wide Material 3 themes. One seed for now; a dark scheme is derived
/// automatically by the system brightness setting.
const _seed = Color(0xFF2D6A4F);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: scheme.surface),
  );
}
