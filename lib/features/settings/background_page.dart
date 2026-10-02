import 'package:flutter/material.dart';

import '../../native/background_launch.dart';

/// One "go to system settings" jump with honest live status. The status is
/// re-verified on every page resumption: flipping the system toggle and
/// coming back must update the row without a restart.
class BackgroundSettingTile extends StatefulWidget {
  const BackgroundSettingTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.openSettings,
    required this.checkState,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final Future<bool> Function() openSettings;
  final Future<bool?> Function() checkState;

  @override
  State<BackgroundSettingTile> createState() => _BackgroundSettingTileState();
}

class _BackgroundSettingTileState extends State<BackgroundSettingTile>
    with WidgetsBindingObserver {
  /// Three states by design: true (allowed) / false (suggested) / null
  /// (cannot be detected on this device). Never fabricate either way.
  bool? _allowed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final state = await widget.checkState();
    if (mounted) setState(() => _allowed = state);
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final opened = await widget.openSettings();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open the system settings page'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (_allowed) {
      true => ('Allowed', Colors.green.shade700),
      false => ('Suggested', theme.colorScheme.primary),
      null => ('Unknown', theme.colorScheme.onSurfaceVariant),
    };
    return ListTile(
      leading: Icon(widget.icon),
      title: Text(widget.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(widget.description),
          const SizedBox(height: 4),
          Text('Status: $label', style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
      isThreeLine: true,
      trailing: OutlinedButton(
        onPressed: _busy ? null : _go,
        child: Text(widget.buttonLabel),
      ),
    );
  }
}

/// Guidance card pointing users at the vendor background-management switches.
/// Pure guidance: it opens the official system pages and reflects the one
/// state that is verifiable (battery optimization); it never bypasses or
/// simulates anything.
class BackgroundRunningCard extends StatelessWidget {
  const BackgroundRunningCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Background running',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          BackgroundSettingTile(
            icon: Icons.refresh_outlined,
            title: 'Allow background activity',
            description: 'Let EasyTier keep running in the background and '
                'reduce the chance of the system suspending or killing it. '
                'If the jump lands on a generic page, open Phone Manager → '
                'Startup manager and allow EasyTier there.',
            buttonLabel: 'Go',
            openSettings: BackgroundLaunch.openBackgroundActivitySettings,
            // No reliable readback exists for vendor startup managers —
            // report that honestly instead of guessing.
            checkState: () async => null,
          ),
          const Divider(height: 1, indent: 16),
          BackgroundSettingTile(
            icon: Icons.battery_saver_outlined,
            title: 'Ignore battery optimization',
            description:
                'Reduce the impact of battery optimization on EasyTier.',
            buttonLabel: 'Go',
            openSettings: BackgroundLaunch.openBatteryOptimizationSettings,
            checkState: BackgroundLaunch.isIgnoringBatteryOptimizations,
          ),
        ],
      ),
    );
  }
}
