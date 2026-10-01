import 'package:flutter/material.dart';

import '../../core/models/network_profile.dart';
import '../../core/services/easytier_service.dart';
import 'export_config_page.dart';

/// Create or edit a network profile. General fields are always visible;
/// advanced options (DHCP / static IP, hostname, latency-first) are folded
/// into an expando so the common path stays short.
class NetworkEditorPage extends StatefulWidget {
  const NetworkEditorPage({required this.service, this.existing, super.key});

  final EasyTierService service;
  final NetworkProfile? existing;

  @override
  State<NetworkEditorPage> createState() => _NetworkEditorPageState();
}

class _NetworkEditorPageState extends State<NetworkEditorPage> {
  static const _instancePrefix = 'easytier_flutter_';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _instanceName;
  late final TextEditingController _secret;
  late final TextEditingController _peers;
  late final TextEditingController _ipv4;
  late final TextEditingController _hostname;
  late bool _dhcp;
  late bool _latencyFirst;
  var _advancedOpen = false;
  var _busy = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _displayName = TextEditingController(text: e?.displayName ?? '');
    _instanceName = TextEditingController(text: e?.instanceName ?? '');
    _secret = TextEditingController(text: e?.secret ?? '');
    _peers = TextEditingController(text: e?.peers.join('\n') ?? '');
    _ipv4 = TextEditingController(text: e?.virtualIpv4 ?? '');
    _hostname = TextEditingController(text: e?.hostname ?? '');
    _dhcp = e?.dhcp ?? true;
    _latencyFirst = e?.latencyFirst ?? false;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _instanceName.dispose();
    _secret.dispose();
    _peers.dispose();
    _ipv4.dispose();
    _hostname.dispose();
    super.dispose();
  }

  /// The profile as currently edited (unsaved form values included).
  NetworkProfile _buildProfile() {
    final base = widget.existing;
    return (base ??
            NetworkProfile(
                id: NetworkProfile.newId(), displayName: '', instanceName: ''))
        .copyWith(
          displayName: _displayName.text.trim(),
          instanceName: _instanceName.text.trim(),
          secret: _secret.text,
          peers: _peers.text
              .split(RegExp(r'[\n,]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          dhcp: _dhcp,
          virtualIpv4: _ipv4.text.trim(),
          hostname: _hostname.text.trim(),
          latencyFirst: _latencyFirst,
        );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final updated = _buildProfile();
    try {
      if (widget.existing == null) {
        await widget.service.profiles.add(updated);
      } else {
        await widget.service.profiles.update(updated);
      }
    } on Object catch (e) {
      // Re-enable Save and surface the failure instead of leaving the button
      // permanently disabled with no feedback.
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New Network' : 'Edit Network'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export TOML',
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) =>
                            ExportConfigPage(profile: _buildProfile()),
                      )),
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('General', style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            )),
            const SizedBox(height: 12),
            TextFormField(
              controller: _displayName,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'e.g. Home',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Display name is required' : null,
              onChanged: (v) {
                // Auto-fill the instance name once from the display name;
                // stop once the user has edited it by hand.
                if (!_instanceTouched) {
                  _instanceName.text = _slugify(v);
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _instanceName,
              decoration: const InputDecoration(
                labelText: 'Instance name',
                hintText: 'home',
                helperText: 'Internal core instance name, must be unique',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag),
              ),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return 'Instance name is required';
                if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(s)) {
                  return 'Letters, digits, _ and - only';
                }
                return null;
              },
              onChanged: (_) => _instanceTouched = true,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _secret,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Secret (optional)',
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
            const SizedBox(height: 20),
            _AdvancedSection(
              initiallyOpen: _advancedOpen,
              onOpenChanged: (open) => setState(() => _advancedOpen = open),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('DHCP (auto virtual IP)'),
                  subtitle: const Text('Let EasyTier assign an address'),
                  value: _dhcp,
                  onChanged: (v) => setState(() => _dhcp = v),
                ),
                if (!_dhcp) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _ipv4,
                    decoration: const InputDecoration(
                      labelText: 'Virtual IPv4',
                      hintText: '10.126.126.10/24',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.policy_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  controller: _hostname,
                  decoration: const InputDecoration(
                    labelText: 'Hostname (optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_android),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Latency first'),
                  subtitle: const Text('Prefer lowest-latency routes'),
                  value: _latencyFirst,
                  onChanged: (v) => setState(() => _latencyFirst = v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  var _instanceTouched = false;

  static String _slugify(String s) {
    final slug = s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? '' : '$_instancePrefix$slug';
  }
}

/// Collapsible "Advanced" group header matching the wireframe's
/// `DHCP / Hostname / Latency First >` folded layout.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.children,
    required this.initiallyOpen,
    required this.onOpenChanged,
  });

  final List<Widget> children;
  final bool initiallyOpen;
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Advanced'),
            trailing: Icon(initiallyOpen
                ? Icons.keyboard_arrow_up
                : Icons.chevron_right),
            onTap: () => onOpenChanged(!initiallyOpen),
          ),
          if (initiallyOpen) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(children: children),
            ),
          ],
        ],
      ),
    );
  }
}
