import 'package:flutter/material.dart';

import '../../core/models/network_profile.dart';
import '../../core/services/easytier_service.dart';
import 'import_config_page.dart';
import 'network_editor_page.dart';

/// Profile manager: list of user networks, create/edit/delete/select.
class NetworksPage extends StatelessWidget {
  const NetworksPage({required this.service, super.key});

  final EasyTierService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Networks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Import config (.toml)',
            onPressed: () => _openImport(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add network',
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: StreamBuilder<void>(
        stream: service.profiles.changes,
        builder: (context, _) {
          final profiles = service.profiles.profiles;
          if (profiles.isEmpty) {
            return _EmptyState(
              onAdd: () => _openEditor(context),
              onImport: () => _openImport(context),
            );
          }
          final currentId = service.profiles.current?.id;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Your networks', style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
              const SizedBox(height: 8),
              for (final p in profiles)
                _ProfileCard(
                  profile: p,
                  isCurrent: p.id == currentId,
                  onTap: () => _openEditor(context, p),
                  onSetCurrent: () => service.profiles.setCurrent(p.id),
                  onDelete: () => _confirmDelete(context, p),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openImport(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ImportConfigPage(service: service),
    ));
  }

  Future<void> _openEditor(BuildContext context, [NetworkProfile? existing]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NetworkEditorPage(service: service, existing: existing),
    ));
  }

  Future<void> _confirmDelete(BuildContext context, NetworkProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${p.displayName}?'),
        content: const Text(
          'The profile and its settings will be removed from this device. '
          'Disconnect first if it is currently connected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await service.profiles.remove(p.id);
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.isCurrent,
    required this.onTap,
    required this.onSetCurrent,
    required this.onDelete,
  });

  final NetworkProfile profile;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onSetCurrent;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          isCurrent ? Icons.circle : Icons.circle_outlined,
          size: isCurrent ? 12 : 22,
          color: theme.colorScheme.primary,
        ),
        title: Text(profile.displayName, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          profile.peers.isEmpty ? 'No peers configured' : '${profile.peers.length} peers',
          style: theme.textTheme.bodySmall,
        ),
        // Editor entry; selection happens via the menu to keep taps distinct.
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'use') onSetCurrent();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'use',
              enabled: !isCurrent,
              child: const Text('Set as current'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.onImport});

  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          const Text('No networks yet'),
          const SizedBox(height: 4),
          Text('Create your first network to get started',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Network'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Import config (.toml)'),
          ),
        ],
      ),
    );
  }
}
