import 'package:flutter/material.dart';

import '../../core/services/easytier_service.dart';
import '../../native/easytier_bridge.dart';

/// Live peer list projected from NetworkInstanceRunningInfo routes.
class PeersPage extends StatelessWidget {
  const PeersPage({required this.service, super.key});

  final EasyTierService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Peers')),
      body: StreamBuilder<NodeStatus>(
        stream: service.statusStream,
        initialData: service.status,
        builder: (context, snap) {
          final status = snap.data ?? NodeStatus.empty;
          final peers = status.peers;
          if (peers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lan_outlined, size: 48,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('No peers yet'),
                  const SizedBox(height: 4),
                  Text('Connect to a network to see peers',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: peers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _PeerTile(peer: peers[i]),
          );
        },
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});

  final PeerRow peer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latency = peer.latencyMs;
    final latencyText = latency == null
        ? '—'
        : latency >= 1000
            ? '${(latency / 1000).toStringAsFixed(1)} s'
            : '${latency.toStringAsFixed(0)} ms';
    final latencyColor = latency == null
        ? theme.colorScheme.outline
        : latency < 50
            ? theme.colorScheme.primary
            : latency < 200
                ? theme.colorScheme.tertiary
                : theme.colorScheme.error;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            peer.hostname.isNotEmpty ? peer.hostname[0].toUpperCase() : '?',
            style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        title: Text(peer.hostname, overflow: TextOverflow.ellipsis),
        subtitle: Text(peer.virtualIp, style: theme.textTheme.bodySmall),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(latencyText,
                style: theme.textTheme.titleSmall?.copyWith(color: latencyColor)),
            Text('cost ${peer.cost}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
