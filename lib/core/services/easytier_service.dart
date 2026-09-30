import 'dart:async';

import '../../native/easytier_bridge.dart';
import '../models/network_profile.dart';
import '../storage/profile_store.dart';

enum CoreState { idle, starting, running, stopping, error }

/// App-level facade over [EasyTierBridge]. Owns the profile store, config
/// rendering, VPN orchestration and a periodic status refresh. UI listens to
/// this; it never calls the bridge directly.
class EasyTierService {
  EasyTierService({ProfileStore? profileStore})
      : _profileStore = profileStore ?? ProfileStore();

  static const _defaultInstanceName = 'easytier_flutter_default';

  final ProfileStore _profileStore;
  final _stateCtrl = StreamController<CoreState>.broadcast();
  final _statusCtrl = StreamController<NodeStatus>.broadcast();
  Timer? _pollTimer;
  CoreState _state = CoreState.idle;
  NodeStatus _lastStatus = NodeStatus.empty;
  String? _lastError;

  CoreState get state => _state;
  NodeStatus get status => _lastStatus;
  String? get lastError => _lastError;
  Stream<CoreState> get stateStream => _stateCtrl.stream;
  Stream<NodeStatus> get statusStream => _statusCtrl.stream;
  ProfileStore get profiles => _profileStore;

  Future<void> loadProfiles() => _profileStore.load();

  NetworkProfile? get currentProfile => _profileStore.current;

  /// Render the TOML instance name for [profile], falling back to the
  /// historical default so existing installs keep working.
  String instanceNameOf(NetworkProfile? profile) {
    final name = profile?.instanceName;
    return (name == null || name.isEmpty) ? _defaultInstanceName : name;
  }

  Future<void> connect(NetworkProfile profile) async {
    if (_state == CoreState.starting || _state == CoreState.running) return;
    _setState(CoreState.starting);
    try {
      // 1. Validate TOML with the official parser before touching the VPN.
      final instanceName = instanceNameOf(profile);
      final toml = profile.toConfig().toToml(instanceName);
      final (ok, parseErr) = await EasyTierBridge.parseConfig(toml);
      if (!ok) {
        throw EasyTierError(EasyTierErrorCode.configurationFailed, parseErr ?? 'parse failed');
      }

      // 2. Start the core instance.
      await EasyTierBridge.runNetworkInstance(toml);

      // 3. Wait for the core to assign a virtual IP (DHCP needs peer routes
      //    first), then establish the VPN TUN with that real address. Official
      //    GUI does the same polling loop before calling VpnService.
      final assigned = await _waitForVirtualIp(
        timeout: const Duration(seconds: 30),
      );
      final addr = assigned ?? (profile.dhcp ? null : profile.virtualIpv4);
      if (addr == null || addr.isEmpty) {
        throw const EasyTierError(
          EasyTierErrorCode.startFailed,
          'Timed out waiting for a virtual IP from the network',
        );
      }
      final routePrefix = _cidrOf(addr) ?? (profile.dhcp ? null : _cidrOf(profile.virtualIpv4));

      await EasyTierBridge.prepareVpn();
      await EasyTierBridge.startVpn(
        instanceName: instanceName,
        ipv4Addr: addr,
        routes: [?routePrefix],
      );

      _lastError = null;
      _setState(CoreState.running);
      await refreshStatus();
      _startPolling();
    } on EasyTierError catch (e) {
      _lastError = e.userMessage;
      _setState(CoreState.error);
      await _safeStopCore(instanceNameOf(profile));
    } on Object catch (e) {
      // Unexpected failures (e.g. malformed native JSON) must not leave the
      // state machine stuck in starting.
      _lastError = 'Unexpected error: $e';
      _setState(CoreState.error);
      await _safeStopCore(instanceNameOf(profile));
    }
  }

  Future<void> disconnect() async {
    if (_state == CoreState.stopping) return;
    _setState(CoreState.stopping);
    _stopPolling();
    try {
      await EasyTierBridge.stopVpn();
      await _safeStopCore(instanceNameOf(currentProfile));
      _lastError = null;
      _lastStatus = NodeStatus.empty;
      _statusCtrl.add(_lastStatus);
      _setState(CoreState.idle);
    } on EasyTierError catch (e) {
      _lastError = e.userMessage;
      _setState(CoreState.error);
    }
  }

  /// Poll collectNetworkInfos until the core has a virtual IP (DHCP only
  /// assigns one once peer routes exist). Returns "ip/prefix" or null on timeout.
  Future<String?> _waitForVirtualIp({Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final s = await EasyTierBridge.collectStatus();
        _lastStatus = s;
        _statusCtrl.add(s);
        if (s.running && s.virtualIp.isNotEmpty) return s.virtualIp;
      } on Object {
        // Core still starting or payload not parseable yet; keep polling.
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return null;
  }

  /// "a.b.c.d/p" -> "a.b.c.0/p"; null when the input is not a CIDR. For /32
  /// (single-host DHCP assignment) the host route is added via addAddress
  /// already, so no separate route is needed.
  String? _cidrOf(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final o = parts[0].split('.');
    if (o.length != 4) return null;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return null;
    if (prefix == 32 || prefix == 0) return null;
    return '${o[0]}.${o[1]}.${o[2]}.0/$prefix';
  }

  Future<NodeStatus> refreshStatus() async {
    try {
      final s = await EasyTierBridge.collectStatus();
      _lastStatus = s;
      _statusCtrl.add(s);
      return s;
    } on EasyTierError {
      return _lastStatus;
    }
  }

  Future<void> _safeStopCore(String instanceName) async {
    try {
      await EasyTierBridge.stopInstance(name: instanceName);
    } on EasyTierError {
      // Best effort: surface in logs, don't mask the original error.
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => refreshStatus());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _setState(CoreState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  Future<void> dispose() async {
    _stopPolling();
    await _stateCtrl.close();
    await _statusCtrl.close();
  }
}
