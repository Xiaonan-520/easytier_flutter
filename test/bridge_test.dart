import 'package:easytier_flutter/core/models/network_config.dart';
import 'package:easytier_flutter/native/easytier_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkConfig.toToml', () {
    test('renders official TOML structure', () {
      final cfg = const NetworkConfig(
        networkName: 'my-mesh',
        networkSecret: 's3cret',
        peerUrls: ['tcp://public.easytier.top:11010'],
        dhcp: true,
        latencyFirst: true,
      );
      final toml = cfg.toToml('inst1');
      expect(toml, contains('inst_name = "inst1"'));
      expect(toml, contains('[network_identity]'));
      expect(toml, contains('network_name = "my-mesh"'));
      expect(toml, contains('network_secret = "s3cret"'));
      expect(toml, contains('[[peer]]'));
      expect(toml, contains('uri = "tcp://public.easytier.top:11010"'));
      expect(toml, contains('dhcp = true'));
      expect(toml, contains('[flags]'));
      expect(toml, contains('latency_first = true'));
      expect(toml, contains('bind_device = false'));
      expect(toml, contains('dev_name = "easytier0"'));
      // Old-style top-level keys must not appear: the core Config struct
      // silently ignores them, leaving the instance out of any network.
      expect(toml, isNot(contains('\nnetwork = ')));
      expect(toml, isNot(contains('\npeers = ')));
    });

    test('omits empty optionals and uses static ip when dhcp off', () {
      final cfg = const NetworkConfig(
        networkName: 'net',
        virtualIpv4: '10.144.144.7/24',
        dhcp: false,
      );
      final toml = cfg.toToml('i');
      expect(toml, isNot(contains('network_secret')));
      expect(toml, contains('ipv4 = "10.144.144.7/24"'));
      expect(toml, isNot(contains('dhcp = true')));
      expect(toml, isNot(contains('[[peer]]')));
    });

    test('escapes quotes and backslashes', () {
      final cfg = const NetworkConfig(networkName: 'a"b\\c');
      expect(cfg.toToml('i'), contains(r'network_name = "a\"b\\c"'));
    });
  });

  group('PeerRow.fromRoute', () {
    test('projects official route JSON', () {
      // prost serializes Ipv4Addr.addr (uint32) as a big-endian packed number:
      // 10.144.144.5 == 0x0A909005 == 177246213.
      final row = PeerRow.fromRoute({
        'peer_id': 5,
        'hostname': 'node-a',
        'ipv4_addr': {
          'address': {'addr': 177246213},
          'network_length': 24,
        },
        'path_latency': 12,
        'cost': 1,
        'version': '2.6.4',
      });
      expect(row.peerId, 5);
      expect(row.hostname, 'node-a');
      expect(row.virtualIp, '10.144.144.5');
      expect(row.latencyMs, 12);
    });
  });

  group('NodeStatus.collectStatus parsing', () {
    test('parses collectNetworkInfos JSON shape', () {
      final status = EasyTierBridge.parseStatusJson(
        '{"map": {"inst1": {'
        '"dev_name": "easytier0", '
        '"my_node_info": {"virtual_ipv4": {"address": {"addr": 177246213}, '
        '"network_length": 24}, "hostname": "phone", "version": "2.6.4", "peer_id": 1}, '
        '"routes": ['
        '{"peer_id": 1, "cost": 0, "hostname": "phone"}, '
        '{"peer_id": 5, "cost": 1, "hostname": "node-a", "path_latency": 8, '
        '"ipv4_addr": {"address": {"addr": 177246213}, "network_length": 24}}'
        '], '
        '"running": true, "error_msg": null}}}',
      );
      expect(status.running, isTrue);
      expect(status.virtualIp, '10.144.144.5');
      expect(status.hostname, 'phone');
      expect(status.peers, hasLength(1));
      expect(status.peers.first.peerId, 5);
      expect(status.peers.first.virtualIp, '10.144.144.5');
    });

    test('returns empty status for empty map', () {
      final status = EasyTierBridge.parseStatusJson('{"map": {}}');
      expect(status.running, isFalse);
      expect(status.peers, isEmpty);
    });
  });

  group('EasyTierError', () {
    test('maps codes to friendly messages', () {
      const e = EasyTierError(EasyTierErrorCode.startFailed, 'boom');
      expect(e.userMessage, contains('boom'));
      expect(e.toString(), contains('startFailed'));
    });
  });
}
