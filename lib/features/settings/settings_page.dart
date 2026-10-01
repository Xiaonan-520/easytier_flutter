import 'package:flutter/material.dart';

import '../../app/theme_controller.dart';
import '../../core/services/easytier_service.dart';
import 'about_page.dart';
import 'appearance_page.dart';
import 'diagnostics_page.dart';

/// Settings: grouped entry points. Developer/advanced info lives under
/// Diagnostics, not here.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.service,
    required this.themeController,
    super.key,
  });

  final EasyTierService service;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _Group(
            title: 'General',
            children: [
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Appearance'),
                subtitle: const Text('Theme color and light / dark mode'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => AppearancePage(controller: themeController),
                )),
              ),
            ],
          ),
          _Group(
            title: 'Network & VPN',
            children: [
              ListTile(
                leading: const Icon(Icons.vpn_lock_outlined),
                title: const Text('VPN permission'),
                subtitle: const Text('Requested on first connect'),
                onTap: () => _todoSnack(context, 'VPN settings'),
              ),
            ],
          ),
          _Group(
            title: 'Advanced',
            children: [
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Diagnostics'),
                subtitle: const Text('Connection state, core status, logs'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => DiagnosticsPage(service: service),
                )),
              ),
            ],
          ),
          _Group(
            title: 'About',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About EasyTier'),
                subtitle: const Text('Version, upstream, license'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _todoSnack(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$what — coming soon'),
      behavior: SnackBarBehavior.floating,
    ));
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
