import 'package:flutter/material.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/logs/logs_page.dart';
import '../features/peers/peers_page.dart';
import '../features/settings/settings_page.dart';

import 'theme.dart';

class EasyTierApp extends StatelessWidget {
  const EasyTierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyTier',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const RootScaffold(),
    );
  }
}

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  var _index = 0;

  static const _destinations = [
    (label: 'Dashboard', icon: Icons.dashboard_outlined, selected: Icons.dashboard),
    (label: 'Peers', icon: Icons.lan_outlined, selected: Icons.lan),
    (label: 'Logs', icon: Icons.article_outlined, selected: Icons.article),
    (label: 'Settings', icon: Icons.settings_outlined, selected: Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardPage(),
          PeersPage(),
          LogsPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
