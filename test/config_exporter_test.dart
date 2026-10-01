import 'package:flutter_test/flutter_test.dart';

import 'package:easytier_flutter/core/models/network_profile.dart';
import 'package:easytier_flutter/core/services/config_exporter.dart';
import 'package:easytier_flutter/core/services/config_importer.dart';

NetworkProfile _full() => const NetworkProfile(
      id: 'x',
      displayName: 'xiaonan-home-ai',
      instanceName: 'home-node',
      secret: 's3cret',
      peers: ['tcp://183.230.36.171:11010', 'udp://peer2.example.com:11010'],
      dhcp: false,
      virtualIpv4: '10.126.126.2/24',
      hostname: 'test-phone',
      latencyFirst: true,
    );

NetworkProfile _minimal() => const NetworkProfile(
      id: 'y',
      displayName: 'Minimal Net',
      instanceName: 'minimal-net',
      peers: ['tcp://1.2.3.4:11010'],
    );

void main() {
  group('ConfigExporter', () {
    test('full profile: every field lands in the official TOML shape', () {
      final toml = ConfigExporter.tomlOf(_full());
      expect(toml, contains('instance_name = "home-node"'));
      expect(toml, contains('[network_identity]'));
      expect(toml, contains('network_name = "xiaonan-home-ai"'));
      expect(toml, contains('network_secret = "s3cret"'));
      expect(toml, contains('[[peer]]'));
      expect(toml, contains('uri = "tcp://183.230.36.171:11010"'));
      expect(toml, contains('uri = "udp://peer2.example.com:11010"'));
      expect(toml, contains('ipv4 = "10.126.126.2/24"'));
      expect(toml, contains('hostname = "test-phone"'));
      expect(toml, contains('latency_first = true'));
      // dhcp=false must be explicit so re-import does not flip to DHCP.
      expect(toml, contains('dhcp = false'));
    });

    test('minimal profile: nothing invented, defaults omitted', () {
      final toml = ConfigExporter.tomlOf(_minimal());
      // No secret -> no network_secret line at all.
      expect(toml, isNot(contains('network_secret')));
      // No hostname -> no hostname line.
      expect(toml, isNot(contains('hostname')));
      // DHCP default -> no ipv4 line.
      expect(toml, isNot(contains('ipv4')));
      expect(toml, isNot(contains('latency_first')));
      expect(toml, contains('instance_name = "minimal-net"'));
      expect(toml, contains('network_name = "Minimal Net"'));
    });

    test('round-trip: export -> import yields an equal profile', () {
      final toml = ConfigExporter.tomlOf(_full());
      final r = ConfigImporter.import(toml);
      expect(r, isA<ImportSuccess>());
      final back = (r as ImportSuccess).profile;
      expect(back.instanceName, _full().instanceName);
      expect(back.displayName, _full().displayName);
      expect(back.secret, _full().secret);
      expect(back.peers, _full().peers);
      expect(back.dhcp, _full().dhcp);
      expect(back.virtualIpv4, _full().virtualIpv4);
      expect(back.hostname, _full().hostname);
      expect(back.latencyFirst, _full().latencyFirst);
      // The importer recognised everything — no legacy-alias warnings.
      expect(r.warnings, isEmpty);
    });

    test('round-trip: minimal profile stays minimal', () {
      final toml = ConfigExporter.tomlOf(_minimal());
      final back =
          (ConfigImporter.import(toml) as ImportSuccess).profile;
      expect(back.instanceName, 'minimal-net');
      expect(back.secret, '');
      expect(back.hostname, '');
      expect(back.dhcp, isTrue);
      expect(back.virtualIpv4, '');
      expect(back.latencyFirst, isFalse);
      expect((ConfigImporter.import(toml) as ImportSuccess).warnings,
          isEmpty);
    });

    test('fileNameOf slugifies the display name', () {
      expect(ConfigExporter.fileNameOf(_full()), 'xiaonan-home-ai.toml');
      expect(
        ConfigExporter.fileNameOf(_full().copyWith(displayName: 'My Net!')),
        'My-Net-.toml',
      );
      expect(
        ConfigExporter.fileNameOf(_full().copyWith(displayName: '  ')),
        'easytier-config.toml',
      );
    });
  });
}
