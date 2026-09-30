import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/easytier_service.dart';
import '../../native/easytier_bridge.dart';

/// In-memory event log: records state transitions and status snapshots
/// produced by the service's periodic refresh, newest first.
class LogsPage extends StatefulWidget {
  const LogsPage({required this.service, super.key});

  final EasyTierService service;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _lines = <_LogLine>[];
  StreamSubscription<CoreState>? _stateSub;
  StreamSubscription<NodeStatus>? _statusSub;
  CoreState? _lastState;
  String _lastPeerCount = '';

  @override
  void initState() {
    super.initState();
    _add('log opened, state=${widget.service.state.name}');
    _stateSub = widget.service.stateStream.listen(_onState);
    _statusSub = widget.service.statusStream.listen(_onStatus);
    _lastState = widget.service.state;
  }

  void _onState(CoreState s) {
    if (s != _lastState) {
      _add('state: ${_lastState?.name ?? '?'} → ${s.name}');
      _lastState = s;
    }
  }

  void _onStatus(NodeStatus status) {
    if (status.errorMessage != null) {
      _add('error: ${status.errorMessage}');
      return;
    }
    if (status.running && status.virtualIp.isNotEmpty) {
      final peerCount = '${status.peers.length}';
      // Log once per peer-count change, not every 3s tick.
      if (peerCount != _lastPeerCount) {
        _add('running: ip=${status.virtualIp} peers=$peerCount '
            'core=${status.version.isEmpty ? '?' : status.version}');
        _lastPeerCount = peerCount;
      }
    }
  }

  void _add(String message) {
    setState(() {
      _lines.insert(
        0,
        _LogLine(time: DateTime.now(), message: message),
      );
      if (_lines.length > 200) _lines.removeLast();
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: () => setState(_lines.clear),
          ),
        ],
      ),
      body: _lines.isEmpty
          ? Center(
              child: Text('No events yet', style: theme.textTheme.bodySmall),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_fmt(line.time)}  ${line.message}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

class _LogLine {
  const _LogLine({required this.time, required this.message});

  final DateTime time;
  final String message;
}
