import 'dart:async';

import '../../native/easytier_bridge.dart';
import '../models/network_config.dart';
import '../storage/config_store.dart';

enum CoreState { idle, starting, running, stopping, error }

/// App-level facade over [EasyTierBridge]. Owns the instance name, config
/// rendering, VPN orchestration and a periodic status refresh. UI listens to
/// this; it never calls the bridge directly.
class EasyTierService {
  EasyTierService({ConfigStore? configStore}) : _configStore = configStore ?? ConfigStore();

  static const _instanceName = 'easytier_flutter_default';

  final ConfigStore _configStore;
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

  Future<NetworkConfig> loadConfig() => _configStore.load();
  Future<void> saveConfig(NetworkConfig c) => _configStore.save(c);

  Future<void> connect(NetworkConfig config) async {
    if (_state == CoreState.starting || _state == CoreState.running) return;
    _setState(CoreState.starting);
    try {
      // 1. Validate TOML with the official parser before touching the VPN.
      final toml = config.toToml(_instanceName);
      final (ok, parseErr) = await EasyTierBridge.parseConfig(toml);
      if (!ok) {
        throw EasyTierError(EasyTierErrorCode.configurationFailed, parseErr ?? 'parse failed');
      }

      // 2. Start the core instance.
      await EasyTierBridge.runNetworkInstance(toml);

      // 3. Establish the VPN TUN and attach it. DHCP configs don't know their
      //    IP yet, so default to the EasyTier virtual range and let routes
      //    come from status on the next refresh.
      await EasyTierBridge.prepareVpn();
      await EasyTierBridge.startVpn(
        instanceName: _instanceName,
        ipv4Addr: config.dhcp ? '10.144.144.1/24' : config.virtualIpv4,
      );

      _lastError = null;
      _setState(CoreState.running);
      await refreshStatus();
      _startPolling();
    } on EasyTierError catch (e) {
      _lastError = e.userMessage;
      _setState(CoreState.error);
      await _safeStopCore();
    }
  }

  Future<void> disconnect() async {
    if (_state == CoreState.stopping) return;
    _setState(CoreState.stopping);
    _stopPolling();
    try {
      await EasyTierBridge.stopVpn();
      await _safeStopCore();
      _lastError = null;
      _lastStatus = NodeStatus.empty;
      _statusCtrl.add(_lastStatus);
      _setState(CoreState.idle);
    } on EasyTierError catch (e) {
      _lastError = e.userMessage;
      _setState(CoreState.error);
    }
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

  Future<void> _safeStopCore() async {
    try {
      await EasyTierBridge.stopInstance();
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
