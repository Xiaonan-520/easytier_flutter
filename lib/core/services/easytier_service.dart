import 'dart:async';

import '../../native/easytier_bridge.dart';
import '../models/network_profile.dart';
import '../storage/profile_store.dart';

enum CoreState { idle, starting, running, stopping, error }

/// Real traffic rates computed from cumulative core counters by sampling
/// [NodeStatus.rxBytes]/[txBytes] on each poll tick. No synthetic values.
class TrafficStats {
  const TrafficStats({
    required this.rxRate,
    required this.txRate,
    required this.rxBytes,
    required this.txBytes,
    required this.timestamp,
  });

  final double rxRate;
  final double txRate;
  final int rxBytes;
  final int txBytes;
  final DateTime? timestamp;

  static final TrafficStats zero = TrafficStats(
    rxRate: 0, txRate: 0, rxBytes: 0, txBytes: 0, timestamp: null,
  );
}

/// App-level facade over [EasyTierBridge]. Owns the profile store, config
/// rendering, VPN orchestration and a periodic status refresh. UI listens to
/// this; it never calls the bridge directly.
class EasyTierService {
  EasyTierService({ProfileStore? profileStore})
      : _profileStore = profileStore ?? ProfileStore() {
    // Keep the tile snapshot in step with profile CRUD; every mutation
    // re-persists through [_persist] so the tile always boots the latest
    // current profile. Errors are swallowed inside [_syncTileSnapshot].
    _profileStore.changes.listen((_) => _syncTileSnapshot());
  }

  static const _defaultInstanceName = 'easytier_flutter_default';

  final ProfileStore _profileStore;
  final _stateCtrl = StreamController<CoreState>.broadcast();
  final _statusCtrl = StreamController<NodeStatus>.broadcast();
  final _trafficCtrl = StreamController<TrafficStats>.broadcast();
  Timer? _pollTimer;
  CoreState _state = CoreState.idle;
  NodeStatus _lastStatus = NodeStatus.empty;
  String? _lastError;
  int? _prevRx;
  int? _prevTx;
  DateTime? _prevAt;

  /// Latest sampled traffic rates (bytes/s) and cumulative totals.
  TrafficStats _traffic = TrafficStats.zero;
  TrafficStats get traffic => _traffic;
  Stream<TrafficStats> get trafficStream => _trafficCtrl.stream;

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

  /// Persist what the QS tile needs to cold-start the VPN with no Flutter
  /// engine: the rendered TOML plus the address/route facts. Mirrors the
  /// values the Dart orchestrator itself would use, so the tile path and
  /// the app path start the exact same instance.
  Future<void> _saveTileSnapshot(NetworkProfile profile) async {
    final instanceName = instanceNameOf(profile);
    final toml = profile.toConfig().toToml(instanceName);
    final addr = _withPrefix(profile.virtualIpv4);
    try {
      await EasyTierBridge.tileSnapshotSave({
        'profileId': profile.id,
        'displayName': profile.displayName,
        'instanceName': instanceName,
        'toml': toml,
        'dhcp': profile.dhcp,
        'virtualIpv4': addr,
        'routes': [
          ?_cidrOf(addr),
        ],
      });
    } on Object {
      // Snapshot persistence must never break the connect flow (e.g. tests
      // with mocked channels); tile start just falls back to open-app.
    }
  }

  Future<void> _clearTileSnapshot() async {
    try {
      await EasyTierBridge.tileSnapshotClear();
    } on Object {
      // Same tolerance as the save path.
    }
  }

  /// Re-persist the tile snapshot when profiles change. Skipped while the
  /// core is running: connect() already wrote the exact started snapshot,
  /// and a mid-session edit must not change what a tile STOP tears down.
  Future<void> _syncTileSnapshot() async {
    if (_state == CoreState.running || _state == CoreState.starting) return;
    final profile = currentProfile;
    if (profile == null) {
      await _clearTileSnapshot();
    } else {
      await _saveTileSnapshot(profile);
    }
  }

  /// App-start reconciliation: if a QS tile tap started (or tried to start)
  /// the VPN while the UI was closed, adopt that state instead of showing
  /// 'idle' while the TUN is actually up. The poll keeps it fresh after.
  Future<void> reconcileWithNative() async {
    try {
      final phase = await EasyTierBridge.tileRuntimeState();
      switch (phase) {
        case 'running':
          _lastError = null;
          _setState(CoreState.running);
          await refreshStatus();
          _startPolling();
        case 'starting':
          _setState(CoreState.starting);
          _startPolling();
        case 'error':
          _setState(CoreState.error);
        case 'stopping':
          _setState(CoreState.stopping);
          _startPolling();
        default:
          break;
      }
    } on Object {
      // Native side unavailable (tests, teardown): stay idle.
    }
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

      // 3. Establish the VPN TUN with a real address. Static profiles have
      //    it up front; DHCP profiles wait for the core to assign one (needs
      //    peer routes first). Symmetric-NAT phones can take >60s for OSPF
      //    convergence (observed 55-60s on EMUI); 90s covers the slow path.
      final addr = profile.dhcp
          ? await _waitForVirtualIp(timeout: const Duration(seconds: 90))
          : _withPrefix(profile.virtualIpv4);
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
      // Written only after a verified-good start: the tile must never cold
      // start from a config the app could not start itself.
      await _saveTileSnapshot(profile);
    } on EasyTierError catch (e) {
      _lastError = e.userMessage;
      _setState(CoreState.error);
      // The TUN may already be up (timeout hit after startVpn in a previous
      // attempt, or the OS kept it); tear it down with the core.
      await EasyTierBridge.stopVpn();
      await _safeStopCore(instanceNameOf(profile));
    } on Object catch (e) {
      // Unexpected failures (e.g. malformed native JSON) must not leave the
      // state machine stuck in starting.
      _lastError = 'Unexpected error: $e';
      _setState(CoreState.error);
      await EasyTierBridge.stopVpn();
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
      // Snapshot is intentionally kept: the tile must stay able to start
      // this profile again — a quick-toggle that stops working after the
      // first in-app disconnect would just be a launcher shortcut.
      _lastError = null;
      _lastStatus = NodeStatus.empty;
      _statusCtrl.add(_lastStatus);
      _prevRx = null;
      _prevTx = null;
      _prevAt = null;
      _traffic = TrafficStats.zero;
      _trafficCtrl.add(_traffic);
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

  /// Users (and stored legacy data) may give a bare IP; VpnService needs the
  /// prefix length. Default to /24, matching the standard EasyTier subnet.
  String _withPrefix(String ip) =>
      ip.contains('/') ? ip : '$ip/24';

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
      _sampleTraffic(s);
      // Peer count / virtual IP change while running -> refresh the shade.
      if (_state == CoreState.running) _syncNotification();
      return s;
    } on EasyTierError {
      return _lastStatus;
    }
  }

  /// Differential sampling: the core only exposes cumulative bytes, so the
  /// rate is (current - previous) / elapsed. Counters can reset on reconnect
  /// (current < previous) — treat that as 0 for one sample.
  void _sampleTraffic(NodeStatus s) {
    final now = DateTime.now();
    final rx = s.rxBytes;
    final tx = s.txBytes;
    final prevAt = _prevAt;
    if (prevAt == null || _prevRx == null || _prevTx == null) {
      _prevRx = rx;
      _prevTx = tx;
      _prevAt = now;
      return;
    }
    final elapsed = now.difference(prevAt).inMilliseconds / 1000.0;
    if (elapsed <= 0) return;
    final rxRate = rx >= _prevRx! ? (rx - _prevRx!) / elapsed : 0.0;
    final txRate = tx >= _prevTx! ? (tx - _prevTx!) / elapsed : 0.0;
    _prevRx = rx;
    _prevTx = tx;
    _prevAt = now;
    _traffic = TrafficStats(
      rxRate: rxRate,
      txRate: txRate,
      rxBytes: rx,
      txBytes: tx,
      timestamp: now,
    );
    _trafficCtrl.add(_traffic);
    if (_state == CoreState.running) {
      EasyTierBridge.updateNotification(
        state: _state.name,
        profileName: currentProfile?.displayName ?? '',
        peers: s.peers.length,
        virtualIp: s.virtualIp,
        error: _lastError,
        rxRate: rxRate,
        txRate: txRate,
      );
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
    _syncNotification();
  }

  /// Mirror the current state into the Android notification so the shade and
  /// the Home page always render the same state machine.
  void _syncNotification() {
    final profile = currentProfile;
    final status = _lastStatus;
    EasyTierBridge.updateNotification(
      state: _state.name,
      profileName: profile?.displayName ?? '',
      peers: status.peers.length,
      virtualIp: status.virtualIp,
      error: _lastError,
      rxRate: _traffic.rxRate,
      txRate: _traffic.txRate,
    );
  }

  Future<void> dispose() async {
    _stopPolling();
    await _stateCtrl.close();
    await _statusCtrl.close();
    await _trafficCtrl.close();
  }
}
