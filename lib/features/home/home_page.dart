import 'package:flutter/material.dart';

import '../../core/models/network_profile.dart';
import '../../core/services/easytier_service.dart';
import '../../native/easytier_bridge.dart';

/// Home: the control center. Current network, connection state, primary
/// action, traffic (when real data exists), network summary, recent peers.
class HomePage extends StatelessWidget {
  const HomePage({required this.service, this.onNavigate, super.key});

  final EasyTierService service;

  /// Jump to a bottom-nav tab (index into the root IndexedStack).
  final ValueChanged<int>? onNavigate;

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
              StreamBuilder<void>(
                stream: service.profiles.changes,
                builder: (context, _) => _ConnectionCard(
                  state: state,
                  service: service,
                  profile: service.currentProfile,
                ),
              ),
              const SizedBox(height: 16),
              Text('Traffic', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const _TrafficCard(),
              const SizedBox(height: 16),
              Text('Network', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              StreamBuilder<NodeStatus>(
                stream: service.statusStream,
                initialData: service.status,
                builder: (context, s) => _NetworkSummaryCard(
                  status: s.data ?? NodeStatus.empty,
                  onPeers: () => onNavigate?.call(2),
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<NodeStatus>(
                stream: service.statusStream,
                initialData: service.status,
                builder: (context, s) {
                  final peers = (s.data ?? NodeStatus.empty).peers;
                  return _RecentPeers(
                    peers: peers.take(3).toList(),
                    onViewAll: () => onNavigate?.call(2),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// User-facing labels for the internal state machine. Internal names
/// (idle/starting/running/stopping) never leak into the UI.
(String, Color, bool busy, IconData) _stateVisual(CoreState state, ColorScheme scheme) =>
    switch (state) {
      CoreState.idle => ('Disconnected', scheme.outline, false, Icons.circle_outlined),
      CoreState.starting => ('Connecting…', scheme.tertiary, true, Icons.autorenew),
      CoreState.running => ('Connected', scheme.primary, false, Icons.circle),
      CoreState.stopping => ('Disconnecting…', scheme.tertiary, true, Icons.autorenew),
      CoreState.error => ('Connection failed', scheme.error, false, Icons.error_outline),
    };

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.state,
    required this.service,
    required this.profile,
  });

  final CoreState state;
  final EasyTierService service;
  final NetworkProfile? profile;

  Future<void> _toggle() async {
    if (state == CoreState.running || state == CoreState.starting) {
      await service.disconnect();
      return;
    }
    final profile = service.currentProfile;
    if (profile == null) return;
    await service.connect(profile);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, busy, icon) = _stateVisual(state, theme.colorScheme);
    final connecting = state == CoreState.starting || state == CoreState.stopping;
    final connected = state == CoreState.running;
    final failed = state == CoreState.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (profile != null)
              Text(
                profile!.displayName,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            Icon(
              icon,
              size: busy ? 26 : 40,
              color: color,
            ).busy(busy),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            StreamBuilder<NodeStatus>(
              stream: service.statusStream,
              initialData: service.status,
              builder: (context, s) {
                final ip = (s.data ?? NodeStatus.empty).virtualIp;
                final showIp = connected && ip.isNotEmpty;
                final subtitle = showIp
                    ? ip
                    : (profile?.displayName.isEmpty ?? true ? 'No network' : '');
                return Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: showIp ? const [FontFeature.tabularFigures()] : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: connecting || profile == null ? null : _toggle,
              icon: Icon(connected ? Icons.stop : Icons.play_arrow),
              label: Text(
                connected ? 'Disconnect' : (failed ? 'Retry' : 'Connect'),
              ),
            ),
            if (failed && (service.lastError?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Text(
                'View details in Diagnostics',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Traffic card. The core does not expose per-flow traffic counters yet, so
/// there is nothing real to show — deliberately left as a placeholder rather
/// than fabricating numbers.
class _TrafficCard extends StatelessWidget {
  const _TrafficCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: _TrafficSlot(
                icon: Icons.south,
                label: 'Download',
                value: '—',
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _TrafficSlot(
                icon: Icons.north,
                label: 'Upload',
                value: '—',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficSlot extends StatelessWidget {
  const _TrafficSlot({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.titleLarge),
      ],
    );
  }
}

class _NetworkSummaryCard extends StatelessWidget {
  const _NetworkSummaryCard({required this.status, required this.onPeers});

  final NodeStatus status;
  final VoidCallback onPeers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subnet = _subnetOf(status.virtualIp);
    final best = status.peers
        .map((p) => p.latencyMs)
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null || b < a ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.hub_outlined),
              title: Text(status.networkName.isEmpty ? 'No network' : status.networkName),
              subtitle: Text(
                subnet ?? 'Connect to see the network',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.people_outline),
              title: Text('${status.peers.length} peers'),
              trailing: Text(
                best == null ? '' : 'best ${best.toStringAsFixed(0)} ms',
                style: theme.textTheme.bodySmall,
              ),
              onTap: onPeers,
            ),
          ],
        ),
      ),
    );
  }

  /// "10.126.126.2/24" -> "10.126.126.0/24"; null when not a valid CIDR.
  static String? _subnetOf(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final o = parts[0].split('.');
    if (o.length != 4) return null;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return null;
    return '${o[0]}.${o[1]}.${o[2]}.0/$prefix';
  }
}

class _RecentPeers extends StatelessWidget {
  const _RecentPeers({required this.peers, required this.onViewAll});

  final List<PeerRow> peers;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (peers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Recent peers', style: theme.textTheme.titleMedium)),
            TextButton(onPressed: onViewAll, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: 4),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < peers.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(Icons.circle, size: 10),
                  iconColor: theme.colorScheme.primary,
                  title: Text(peers[i].hostname, overflow: TextOverflow.ellipsis),
                  subtitle: Text(peers[i].virtualIp, style: theme.textTheme.bodySmall),
                  trailing: peers[i].latencyMs == null
                      ? null
                      : Text(
                          '${peers[i].latencyMs!.toStringAsFixed(0)} ms',
                          style: theme.textTheme.bodyMedium,
                        ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

extension _BusyIcon on Icon {
  /// Swap a static icon for a spinner while a transition is in flight.
  Widget busy(bool busy) => busy
      ? SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
        )
      : this;
}
