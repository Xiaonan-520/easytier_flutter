import 'package:flutter/material.dart';

import '../../core/services/easytier_service.dart';
import '../../native/easytier_bridge.dart';

/// Full peer list projected from NetworkInstanceRunningInfo routes.
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
            return _EmptyPeers(connected: status.running);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${peers.length} peers',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              for (final p in peers)
                _PeerCard(
                  peer: p,
                  onTap: () => _showDetail(context, p),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, PeerRow peer) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(peer.hostname, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _DetailRow('Virtual IP', peer.virtualIp.isEmpty ? '—' : peer.virtualIp),
              _DetailRow('Latency', peer.latencyMs == null ? '—' : '${peer.latencyMs!.toStringAsFixed(0)} ms'),
              _DetailRow('Cost', '${peer.cost}'),
              if (peer.version.isNotEmpty) _DetailRow('Version', peer.version),
              _DetailRow('Peer ID', '${peer.peerId}'),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, required this.onTap});

  final PeerRow peer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latency = peer.latencyMs;
    final online = latency != null;
    final latencyText = latency == null
        ? '—'
        : latency >= 1000
            ? '${(latency / 1000).toStringAsFixed(1)} s'
            : '${latency.toStringAsFixed(0)} ms';
    final latencyColor = !online
        ? theme.colorScheme.outline
        : latency < 50
            ? theme.colorScheme.primary
            : latency < 200
                ? theme.colorScheme.tertiary
                : theme.colorScheme.error;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          online ? Icons.circle : Icons.circle_outlined,
          size: online ? 12 : 20,
          color: online ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        title: Text(peer.hostname, overflow: TextOverflow.ellipsis),
        subtitle: Text(peer.virtualIp, style: theme.textTheme.bodySmall),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              online ? 'Connected' : 'Offline',
              style: theme.textTheme.labelSmall?.copyWith(
                color: online ? theme.colorScheme.primary : theme.colorScheme.outline,
              ),
            ),
            Text(latencyText,
                style: theme.textTheme.titleSmall?.copyWith(color: latencyColor)),
          ],
        ),
      ),
    );
  }
}

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lan_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(connected ? 'No peers in this network yet' : 'Not connected'),
          const SizedBox(height: 4),
          Text(
            connected
                ? 'Peers appear once other nodes join'
                : 'Connect to a network to see peers',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
