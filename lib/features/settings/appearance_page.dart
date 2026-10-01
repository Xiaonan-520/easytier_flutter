import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/theme_controller.dart';

/// Appearance: theme preset picker (color swatch previews) and Light /
/// Dark / System mode. Both persist across restarts via ThemeStore.
class AppearancePage extends StatefulWidget {
  const AppearancePage({required this.controller, super.key});

  final ThemeController controller;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Appearance')),
        body: ListView(
          children: [
            _Group(
              title: 'Theme color',
              children: [
                for (final preset in ThemePreset.all)
                  _PresetTile(
                    preset: preset,
                    selected: preset.id == controller.preset.id,
                    onTap: () => controller.setPreset(preset),
                  ),
              ],
            ),
            _Group(
              title: 'Mode',
              children: [
                RadioGroup<ThemeMode>(
                  groupValue: controller.mode,
                  onChanged: (m) { if (m != null) controller.setMode(m); },
                  child: Column(
                    children: [
                      for (final mode in ThemeMode.values)
                        RadioListTile<ThemeMode>(
                          value: mode,
                          title: Text(_modeLabel(mode)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'The current theme keeps its light and dark variants; '
                'System follows the device setting.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _modeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: _Swatch(preset: preset),
      title: Text(preset.label),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
    );
  }
}

/// Three filled circles from the preset's primary / secondary / tertiary
/// colors — a compact, honest preview of the seed palette.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.preset});

  final ThemePreset preset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final color in preset.preview)
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          )),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16),
                ...children.skip(i).take(1),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
