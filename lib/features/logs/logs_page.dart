import 'package:flutter/material.dart';

import '../../core/services/easytier_service.dart';
import '../../native/easytier_bridge.dart';

/// Simple in-memory log view backed by core status refreshes.
class LogsPage extends StatelessWidget {
  const LogsPage({required this.service, super.key});

  final EasyTierService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh status',
            onPressed: () => service.refreshStatus(),
          ),
        ],
      ),
      body: StreamBuilder<NodeStatus>(
        stream: service.statusStream,
        initialData: service.status,
        builder: (context, snap) {
          final status = snap.data ?? NodeStatus.empty;
          final lines = <String>[
            '${DateTime.now().toIso8601String()}  state=${service.state.name}',
            if (status.errorMessage != null)
              '${DateTime.now().toIso8601String()}  error: ${status.errorMessage}',
          ];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: lines.length,
            itemBuilder: (context, i) => Text(
              lines[i],
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          );
        },
      ),
    );
  }
}
