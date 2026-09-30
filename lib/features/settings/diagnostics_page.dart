import 'package:flutter/material.dart';

import '../../core/services/easytier_service.dart';
import 'logs_page.dart';
import '../../native/easytier_bridge.dart';

/// Advanced diagnostics hub: connection state, core/node details and the
/// application event log. The audience is advanced users; raw internal names
/// are allowed here.
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({required this.service, super.key});

  final EasyTierService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Connection', style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          )),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: StreamBuilder<CoreState>(
              stream: service.stateStream,
              initialData: service.state,
              builder: (context, snap) {
                final state = snap.data ?? CoreState.idle;
                return Column(
                  children: [
                    _Row('State', state.name),
                    if (service.lastError != null)
                      _Row('Last error', service.lastError!, error: true),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('Core', style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          )),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: StreamBuilder<NodeStatus>(
              stream: service.statusStream,
              initialData: service.status,
              builder: (context, s) {
                final st = s.data ?? NodeStatus.empty;
                return Column(
                  children: [
                    _Row('Instance', st.networkName.isEmpty ? '—' : st.networkName),
                    _Row('Core version', st.version.isEmpty ? '—' : st.version),
                    _Row('Virtual IP', st.virtualIp.isEmpty ? '—' : st.virtualIp),
                    _Row('Hostname', st.hostname.isEmpty ? '—' : st.hostname),
                    _Row('Peers', '${st.peers.length}'),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('Logs', style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          )),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Application logs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => LogsPage(service: service),
              )),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.error = false});

  final String label;
  final String value;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: error ? theme.colorScheme.error : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
