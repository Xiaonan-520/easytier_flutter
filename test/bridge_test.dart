import 'package:easytier_flutter/core/models/network_config.dart';
import 'package:easytier_flutter/native/easytier_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkConfig.toToml', () {
    test('renders official TOML keys', () {
      final cfg = const NetworkConfig(
        networkName: 'my-mesh',
        networkSecret: 's3cret',
        peerUrls: ['tcp://public.easytier.top:11010'],
        dhcp: true,
      );
      final toml = cfg.toToml('inst1');
      expect(toml, contains('inst_name = "inst1"'));
      expect(toml, contains('network = "my-mesh"'));
      expect(toml, contains('network_secret = "s3cret"'));
      expect(toml, contains('peers = ["tcp://public.easytier.top:11010"]'));
      expect(toml, contains('dhcp = true'));
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
      expect(toml, isNot(contains('peers =')));
    });

    test('escapes quotes and backslashes', () {
      final cfg = const NetworkConfig(networkName: 'a"b\\c');
      expect(cfg.toToml('i'), contains(r'network = "a\"b\\c"'));
    });
  });

  group('PeerRow.fromRoute', () {
    test('projects official route JSON', () {
      final row = PeerRow.fromRoute({
        'peer_id': 5,
        'hostname': 'node-a',
        'ipv4_addr': {'addr': '10.144.144.5', 'network_length': 24},
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

  group('EasyTierError', () {
    test('maps codes to friendly messages', () {
      const e = EasyTierError(EasyTierErrorCode.startFailed, 'boom');
      expect(e.userMessage, contains('boom'));
      expect(e.toString(), contains('startFailed'));
    });
  });
}
