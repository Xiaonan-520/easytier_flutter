import 'package:flutter/material.dart';

import '../../core/services/easytier_service.dart';
import '../../native/easytier_bridge.dart';

/// Dashboard: connection state card + network summary + quick links.
class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.service, super.key});

  final EasyTierService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('EasyTier')),
      body: StreamBuilder<CoreState>(
        stream: service.stateStream,
        initialData: service.state,
        builder: (context, snap) {
          final state = snap.data ?? CoreState.idle;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ConnectionCard(state: state, service: service),
              const SizedBox(height: 16),
              Text('Network', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              StreamBuilder<NodeStatus>(
                stream: service.statusStream,
                initialData: service.status,
                builder: (context, s) =>
                    _NetworkInfoCard(status: s.data ?? NodeStatus.empty),
              ),
              const SizedBox(height: 16),
              Text('Quick links', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Network configuration'),
                    onTap: () => DefaultTabController.maybeOf(context) == null
                        ? Scaffold.maybeOf(context)?.openDrawer()
                        : null,
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.state, required this.service});

  final CoreState state;
  final EasyTierService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (state) {
      CoreState.idle => ('Disconnected', theme.colorScheme.outline, Icons.circle_outlined),
      CoreState.starting => ('Connecting…', theme.colorScheme.tertiary, Icons.autorenew),
      CoreState.running => ('Connected', theme.colorScheme.primary, Icons.circle),
      CoreState.stopping => ('Disconnecting…', theme.colorScheme.tertiary, Icons.autorenew),
      CoreState.error => ('Error', theme.colorScheme.error, Icons.error_outline),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state == CoreState.starting || state == CoreState.stopping)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 14, color: color),
                const SizedBox(width: 8),
                Text(label, style: theme.textTheme.titleMedium),
              ],
            ),
            if (state == CoreState.error && service.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                service.lastError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: state == CoreState.running || state == CoreState.starting
                  ? () => service.disconnect()
                  : state == CoreState.idle || state == CoreState.error
                      ? () async {
                          final cfg = await service.loadConfig();
                          await service.connect(cfg);
                        }
                      : null,
              icon: Icon(state == CoreState.running ? Icons.stop : Icons.play_arrow),
              label: Text(state == CoreState.running ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkInfoCard extends StatelessWidget {
  const _NetworkInfoCard({required this.status});

  final NodeStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.hub_outlined),
        title: Text(status.networkName.isEmpty ? 'No network configured' : status.networkName),
        subtitle: Text(
          status.virtualIp.isEmpty
              ? 'Connect to get a virtual IP'
              : 'Node IP: ${status.virtualIp}',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}
