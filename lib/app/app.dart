import 'package:flutter/material.dart';

import '../core/models/network_profile.dart';
import '../core/models/network_config.dart' show NetworkConfig;
import '../core/services/easytier_service.dart';
import '../core/storage/config_store.dart';
import '../features/home/home_page.dart';
import '../features/networks/networks_page.dart';
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
  late final EasyTierService _service;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _service = EasyTierService();
    _init();
  }

  Future<void> _init() async {
    await _service.loadProfiles();
    // One-time migration: a pre-profiles install kept a single config under
    // network_config_v1 — turn it into the first profile.
    if (_service.profiles.profiles.isEmpty) {
      final legacy = await ConfigStore().load();
      if (legacy.networkName.isNotEmpty || legacy.peerUrls.isNotEmpty) {
        await _service.profiles.add(_profileFromLegacy(legacy));
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  NetworkProfile _profileFromLegacy(NetworkConfig c) => NetworkProfile(
        id: NetworkProfile.newId(),
        displayName: c.networkName,
        instanceName: 'easytier_flutter_default',
        secret: c.networkSecret,
        peers: c.peerUrls,
        dhcp: c.dhcp,
        virtualIpv4: c.virtualIpv4,
        hostname: c.hostname,
        latencyFirst: c.latencyFirst,
      );

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(service: _service, onNavigate: (i) => setState(() => _index = i)),
          NetworksPage(service: _service),
          PeersPage(service: _service),
          SettingsPage(service: _service),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'Networks',
          ),
          NavigationDestination(
            icon: Icon(Icons.lan_outlined),
            selectedIcon: Icon(Icons.lan),
            label: 'Peers',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
