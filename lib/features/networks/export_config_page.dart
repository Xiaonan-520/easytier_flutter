import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/network_profile.dart';
import '../../core/services/config_exporter.dart';

/// Shows the exact TOML that would be exported for [profile] and offers
/// Save (SAF) / Share. Warns up front that the network secret is written
/// in clear text into the file.
class ExportConfigPage extends StatefulWidget {
  const ExportConfigPage({required this.profile, super.key});

  final NetworkProfile profile;

  @override
  State<ExportConfigPage> createState() => _ExportConfigPageState();
}

class _ExportConfigPageState extends State<ExportConfigPage> {
  late final String _toml = ConfigExporter.tomlOf(widget.profile);
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final uri = await ConfigExporter.save(widget.profile, _toml);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(uri == null
            ? 'Save cancelled'
            : 'Saved ${ConfigExporter.fileNameOf(widget.profile)}'),
      ));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: ${e.message ?? e.code}'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await ConfigExporter.share(widget.profile, _toml);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSecret = widget.profile.secret.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Export config')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Official EasyTier TOML for “${widget.profile.displayName}”. '
            'The same format the app feeds the core — it can be imported '
            'back or used with easytier-core / the official GUI.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasSecret) ...[
            const SizedBox(height: 12),
            _WarningCard(
                text: 'The network secret is included in clear text. '
                    'Anyone with this file can join the network — share it '
                    'only with devices you trust.'),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.description_outlined,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(ConfigExporter.fileNameOf(widget.profile),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                  ]),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    child: Text(
                      _toml,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save to device'),
            onPressed: _busy ? null : _save,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share…'),
            onPressed: _busy ? null : _share,
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
