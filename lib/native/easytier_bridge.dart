import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Typed errors surfaced by the native bridge. UI must never crash on a
/// native failure; everything funnels through [EasyTierError].
enum EasyTierErrorCode {
  initializationFailed,
  startFailed,
  stopFailed,
  configurationFailed,
  vpnPermissionDenied,
  vpnStartFailed,
  nativeLibraryMissing,
  unknown,
}

class EasyTierError implements Exception {
  const EasyTierError(this.code, this.message);

  final EasyTierErrorCode code;
  final String message;

  String get userMessage {
    switch (code) {
      case EasyTierErrorCode.startFailed:
        return 'Failed to start EasyTier: $message';
      case EasyTierErrorCode.stopFailed:
        return 'Failed to stop EasyTier: $message';
      case EasyTierErrorCode.configurationFailed:
        return 'Invalid configuration: $message';
      case EasyTierErrorCode.vpnPermissionDenied:
        return 'VPN permission was denied. Grant it to connect.';
      case EasyTierErrorCode.vpnStartFailed:
        return 'Failed to establish the VPN interface: $message';
      case EasyTierErrorCode.nativeLibraryMissing:
        return 'EasyTier native library is missing from this build.';
      case EasyTierErrorCode.initializationFailed:
      case EasyTierErrorCode.unknown:
        return message;
    }
  }

  @override
  String toString() => 'EasyTierError(${code.name}): $message';
}

/// One row in the peer list, projected from the official
/// NetworkInstanceRunningInfo JSON (api_manage.proto / api_instance.proto).
class PeerRow {
  const PeerRow({
    required this.peerId,
    required this.hostname,
    required this.virtualIp,
    required this.latencyMs,
    required this.cost,
    required this.version,
  });

  final int peerId;
  final String hostname;
  final String virtualIp;
  final double? latencyMs;
  final int cost;
  final String version;

  /// Format a protobuf Ipv4Addr JSON value. prost serializes uint32 fields
  /// as JSON numbers (big-endian octets packed into one int).
  static String ipv4FromU32(Object? v) {
    if (v is int) {
      return [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255].join('.');
    }
    return v is String ? v : '';
  }


  factory PeerRow.fromRoute(Map<String, dynamic> route) {
    final latency = route['path_latency'];
    final addr = EasyTierBridge._map(EasyTierBridge._map(route['ipv4_addr'])?['address']);
    return PeerRow(
      peerId: (route['peer_id'] as num?)?.toInt() ?? 0,
      hostname: (route['hostname'] as String?)?.isNotEmpty == true
          ? route['hostname'] as String
          : 'peer-${route['peer_id']}',
      virtualIp: ipv4FromU32(addr?['addr']),
      latencyMs: latency is num ? latency.toDouble() : null,
      cost: (route['cost'] as num?)?.toInt() ?? 0,
      version: route['version'] as String? ?? '',
    );
  }
}

/// Snapshot of the local node and the running network.
class NodeStatus {
  const NodeStatus({
    required this.running,
    required this.networkName,
    required this.virtualIp,
    required this.hostname,
    required this.version,
    required this.peers,
    required this.errorMessage,
  });

  final bool running;
  final String networkName;
  final String virtualIp;
  final String hostname;
  final String version;
  final List<PeerRow> peers;
  final String? errorMessage;

  static const empty = NodeStatus(
    running: false,
    networkName: '',
    virtualIp: '',
    hostname: '',
    version: '',
    peers: [],
    errorMessage: null,
  );
}

/// Dart bridge to the Android native layer. All calls go through a single
/// MethodChannel; native side returns `{code, error}` maps for lifecycle ops
/// and JSON strings for state, mirroring the official EasyTierJNI API.
class EasyTierBridge {
  EasyTierBridge._();

  static const _channel = MethodChannel('easytier_flutter/core');

  /// Safe cast: MethodChannel/jsonDecode payloads can surface const
  /// dynamic-keyed maps that blow up on a plain `as Map<String, dynamic>`.
  static Map<String, dynamic>? _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static Future<Object?>? _invokeRaw(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      return await _channel.invokeMethod(method, args);
    } on PlatformException catch (e) {
      throw EasyTierError(EasyTierErrorCode.unknown, e.message ?? e.code);
    } on MissingPluginException {
      throw const EasyTierError(
        EasyTierErrorCode.nativeLibraryMissing,
        'Native bridge not available',
      );
    }
  }

  /// Invoke a method whose native side answers `{code, error}`.
  static Future<Map<Object?, Object?>?> _invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    final res = await _invokeRaw(method, args);
    return res is Map ? Map<Object?, Object?>.from(res) : null;
  }

  /// Validate a TOML config string via the official parseConfig JNI API.
  static Future<(bool, String?)> parseConfig(String config) async {
    final res = await _invoke('parseConfig', {'config': config});
    final code = res?['code'] as int? ?? -1;
    return (code == 0, res?['error'] as String?);
  }

  /// Start an EasyTier instance from TOML config text.
  static Future<void> runNetworkInstance(String config) async {
    final res = await _invoke('runNetworkInstance', {'config': config});
    if ((res?['code'] as int? ?? -1) != 0) {
      throw EasyTierError(
        EasyTierErrorCode.startFailed,
        res?['error'] as String? ?? 'runNetworkInstance failed',
      );
    }
  }

  /// Stop one instance (or all when [name] is null).
  static Future<void> stopInstance({String? name}) async {
    final res = await _invoke('stopInstance', {'name': name});
    if ((res?['code'] as int? ?? -1) != 0) {
      throw EasyTierError(
        EasyTierErrorCode.stopFailed,
        res?['error'] as String? ?? 'stopInstance failed',
      );
    }
  }

  static Future<bool> prepareVpn() async => await _invokeRaw('prepareVpn') == true;

  static Future<void> startVpn({
    required String instanceName,
    required String ipv4Addr,
    List<String> routes = const [],
  }) async {
    await _invokeRaw('startVpn', {
      'instanceName': instanceName,
      'ipv4Addr': ipv4Addr,
      'routes': routes,
    });
  }

  static Future<void> stopVpn() async {
    await _invokeRaw('stopVpn');
  }

  static Future<bool> isVpnRunning() async => await _invokeRaw('isVpnRunning') == true;

  /// Collect the running-state JSON (official collectNetworkInfos) and
  /// project it into a [NodeStatus]. Returns [NodeStatus.empty] when no
  /// instance is running.
  static Future<NodeStatus> collectStatus() async {
    final res = await _invoke('collectNetworkInfos');
    final json = res?['json'] as String?;
    if (json == null || json.isEmpty) return NodeStatus.empty;
    return parseStatusJson(json);
  }

  /// Project the NetworkInstanceRunningInfoMap JSON (serde +
  /// preserve_proto_field_names, prost u32 fields as JSON numbers) into a
  /// [NodeStatus].
  static NodeStatus parseStatusJson(String json) {
    final decoded = jsonDecode(json);
    final map = _map(_map(decoded)?['map']) ?? {};
    if (map.isEmpty) return NodeStatus.empty;

    // Single-instance client: prefer the running entry.
    final entry = map.entries
            .where((e) => _map(e.value)?['running'] == true)
            .firstOrNull ??
        map.entries.first;
    final info = _map(entry.value) ?? const {};
    final myInfo = _map(info['my_node_info']);
    final virtualIpv4 = _map(myInfo?['virtual_ipv4']);
    final vaddr = _map(virtualIpv4?['address']);

    final vlen = virtualIpv4?['network_length'];

    final routes = (info['routes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        // Skip our own entry (cost 0 to self).
        .where((r) => (r['cost'] as num? ?? 0) != 0)
        .map(PeerRow.fromRoute)
        .toList();

    return NodeStatus(
      running: info['running'] as bool? ?? true,
      // NetworkInstanceRunningInfo carries no network name; show instance name.
      networkName: entry.key,
      // "ip/prefix" — startVpn/VpnService need the prefix length too.
      virtualIp:
          '${PeerRow.ipv4FromU32(vaddr?['addr'])}${vlen is num ? '/${vlen.toInt()}' : ''}',
      hostname: myInfo?['hostname'] as String? ?? '',
      version: myInfo?['version'] as String? ?? '',
      peers: routes,
      errorMessage: info['error_msg'] as String?,
    );
  }
}
