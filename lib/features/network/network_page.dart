import 'package:flutter/material.dart';

import '../../core/models/network_config.dart';
import '../../core/services/easytier_service.dart';

/// Network configuration form. Saves locally and offers connect-from-here.
class NetworkPage extends StatefulWidget {
  const NetworkPage({required this.service, super.key});

  final EasyTierService service;

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _secret;
  late final TextEditingController _peers;
  late final TextEditingController _ipv4;
  late final TextEditingController _hostname;
  late bool _dhcp;
  late bool _latencyFirst;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _secret = TextEditingController();
    _peers = TextEditingController();
    _ipv4 = TextEditingController();
    _hostname = TextEditingController();
    _dhcp = true;
    _latencyFirst = false;
    _load();
  }

  Future<void> _load() async {
    final cfg = await widget.service.loadConfig();
    if (!mounted) return;
    setState(() {
      _name.text = cfg.networkName;
      _secret.text = cfg.networkSecret;
      _peers.text = cfg.peerUrls.join('\n');
      _ipv4.text = cfg.virtualIpv4;
      _hostname.text = cfg.hostname;
      _dhcp = cfg.dhcp;
      _latencyFirst = cfg.latencyFirst;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    _peers.dispose();
    _ipv4.dispose();
    _hostname.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final cfg = NetworkConfig(
      networkName: _name.text.trim(),
      networkSecret: _secret.text,
      peerUrls: _peers.text
          .split(RegExp(r'[\n,]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      virtualIpv4: _ipv4.text.trim(),
      hostname: _hostname.text.trim(),
      dhcp: _dhcp,
      latencyFirst: _latencyFirst,
    );
    await widget.service.saveConfig(cfg);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuration saved'), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Network name',
                hintText: 'e.g. my-mesh',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Network name is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _secret,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Network secret (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _peers,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Peer URLs (one per line)',
                hintText: 'tcp://public.easytier.top:11010',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns_outlined),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('DHCP (auto virtual IP)'),
              subtitle: const Text('Let EasyTier assign 10.144.144.x'),
              value: _dhcp,
              onChanged: (v) => setState(() => _dhcp = v),
            ),
            if (!_dhcp) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _ipv4,
                decoration: const InputDecoration(
                  labelText: 'Virtual IPv4',
                  hintText: '10.144.144.10/24',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.policy_outlined),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _hostname,
              decoration: const InputDecoration(
                labelText: 'Hostname (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Latency first'),
              subtitle: const Text('Prefer lowest-latency routes'),
              value: _latencyFirst,
              onChanged: (v) => setState(() => _latencyFirst = v),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save configuration'),
            ),
          ],
        ),
      ),
    );
  }
}
