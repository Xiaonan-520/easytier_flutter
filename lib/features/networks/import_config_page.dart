import 'dart:convert';
import 'dart:io' show IOException;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/config_importer.dart';
import '../../core/services/easytier_service.dart';
import 'network_editor_page.dart';

/// Import an official EasyTier TOML config as a NEW profile: pick a .toml
/// file or paste the text. Nothing is saved until the user confirms in the
/// pre-filled editor — the current profile is never touched.
class ImportConfigPage extends StatefulWidget {
  const ImportConfigPage({required this.service, super.key});

  final EasyTierService service;

  @override
  State<ImportConfigPage> createState() => _ImportConfigPageState();
}

class _ImportConfigPageState extends State<ImportConfigPage> {
  final _text = TextEditingController();
  String? _fileName;
  ImportResult? _result;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['toml', 'conf'],
      );
      final file = picked.singleOrNull;
      if (file == null) return; // user cancelled
      final content = await _readAsText(file);
      if (content == null) {
        setState(() => _result = const ImportFailure(
            'Could not read the file as UTF-8 text.'));
        return;
      }
      setState(() {
        _fileName = file.name;
        _text.text = content;
        _result = ConfigImporter.import(content, suggestedName: _suggest(file.name));
      });
    } on PlatformException catch (e) {
      setState(() => _result = ImportFailure('File picker failed: ${e.message ?? e.code}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Read the picked file as UTF-8; null when unreadable or not valid text.
  Future<String?> _readAsText(PlatformFile file) async {
    try {
      return const Utf8Decoder(allowMalformed: false)
          .convert(await file.readAsBytes());
    } on FormatException {
      return null;
    } on IOException {
      return null;
    }
  }

  void _parsePasted() {
    setState(() {
      _fileName = null;
      _result = ConfigImporter.import(_text.text);
    });
  }

  Future<void> _confirm(ImportSuccess ok) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import this network?'),
        content: Text(
          '“${ok.profile.displayName}”\n'
          '${ok.profile.peers.length} peer(s), '
          '${ok.profile.dhcp ? 'DHCP' : 'static IP ${ok.profile.virtualIpv4}'}\n\n'
          'It will be added as a new profile — your current network is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.service.profiles.add(ok.profile);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Imported “${ok.profile.displayName}”'),
    ));
    // Let the user review/adjust the imported values before connecting.
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => NetworkEditorPage(
        service: widget.service,
        existing: ok.profile,
      ),
    ));
  }

  String _suggest(String fileName) {
    final base = fileName.endsWith('.toml') || fileName.endsWith('.conf')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    return base.replaceAll('_', ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import config')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Bring an official EasyTier .toml config into EasyTier.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_open_outlined),
            label: const Text('Choose .toml file'),
            onPressed: _busy ? null : _pickFile,
          ),
          const SizedBox(height: 8),
          if (_fileName != null)
            Text('File: $_fileName', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or paste TOML',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ),
            Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLines: 10,
            minLines: 6,
            maxLength: 64 * 1024,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              hintText:
                  'instance_name = "my-node"\n\n[network_identity]\nnetwork_name = "…"\n\n[[peer]]\nuri = "tcp://…"',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.rule),
            label: const Text('Check & import'),
            onPressed: _busy ? null : _parsePasted,
          ),
          const SizedBox(height: 16),
          ..._resultView(theme),
        ],
      ),
    );
  }

  List<Widget> _resultView(ThemeData theme) {
    final r = _result;
    if (r == null) return const [];
    switch (r) {
      case ImportFailure(:final message):
        return [
          _ResultCard(
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
            title: 'Import failed',
            body: message,
          ),
        ];
      case ImportSuccess(:final profile, :final warnings):
        return [
          _ResultCard(
            icon: Icons.check_circle_outline,
            color: theme.colorScheme.primary,
            title: 'Parsed “${profile.displayName}”',
            body: [
              '${profile.peers.length} peer(s)',
              profile.dhcp ? 'DHCP' : 'Static IP ${profile.virtualIpv4}',
              if (profile.hostname.isNotEmpty) 'Hostname ${profile.hostname}',
              'Instance name: ${profile.instanceName}',
            ].join(' · '),
            actions: [
              FilledButton.icon(
                icon: const Icon(Icons.download_done),
                label: const Text('Save as new network'),
                onPressed: () => _confirm(r),
              ),
            ],
          ),
          for (final w in warnings)
            ListTile(
              dense: true,
              leading: Icon(Icons.info_outline,
                  size: 18, color: theme.colorScheme.tertiary),
              title: Text(w, style: theme.textTheme.bodySmall),
            ),
        ];
    }
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...actions,
            ],
          ],
        ),
      ),
    );
  }
}
