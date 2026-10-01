import 'package:flutter_test/flutter_test.dart';

import 'package:easytier_flutter/core/models/network_profile.dart';
import 'package:easytier_flutter/core/services/config_importer.dart';

void main() {
  group('ConfigImporter', () {
    test('parses the official Config TOML shape', () {
      final r = ConfigImporter.import('''
# my network
instance_name = "home-node"
hostname = "phone"
dhcp = false
ipv4 = "10.126.126.2/24"

[network_identity]
network_name = "xiaonan-home-ai"
network_secret = "s3cret"

[[peer]]
uri = "tcp://183.230.36.171:11010"

[[peer]]
uri = "udp://peer2.example.com:11010"

[flags]
latency_first = true
''');
      expect(r, isA<ImportSuccess>());
      final ok = r as ImportSuccess;
      expect(ok.profile.instanceName, 'home-node');
      expect(ok.profile.displayName, 'xiaonan-home-ai');
      expect(ok.profile.secret, 's3cret');
      expect(ok.profile.peers, [
        'tcp://183.230.36.171:11010',
        'udp://peer2.example.com:11010',
      ]);
      expect(ok.profile.dhcp, isFalse);
      expect(ok.profile.virtualIpv4, '10.126.126.2/24');
      expect(ok.profile.hostname, 'phone');
      expect(ok.profile.latencyFirst, isTrue);
      expect(ok.warnings, isEmpty);
    });

    test('dhcp-only config with no ipv4', () {
      final r = ConfigImporter.import('''
[network_identity]
network_name = "net"

[[peer]]
uri = "tcp://1.2.3.4:11010"
''');
      final ok = r as ImportSuccess;
      expect(ok.profile.dhcp, isTrue);
      expect(ok.profile.virtualIpv4, isEmpty);
    });

    test('dhcp = true with ipv4 keeps ipv4 but warns', () {
      final r = ConfigImporter.import('''
dhcp = true
ipv4 = "10.0.0.5/24"

[network_identity]
network_name = "net"
''');
      final ok = r as ImportSuccess;
      expect(ok.profile.dhcp, isTrue);
      expect(ok.profile.virtualIpv4, '10.0.0.5/24');
      expect(ok.warnings, isNotEmpty);
    });

    test('dhcp = "yes" string accepted', () {
      final r = ConfigImporter.import('''
dhcp = "yes"
[network_identity]
network_name = "net"
''');
      expect((r as ImportSuccess).profile.dhcp, isTrue);
    });

    test('legacy android-jni example style: inst_name/network/peers', () {
      final r = ConfigImporter.import('''
inst_name = "android_instance"
network = "my_easytier_network"
network_secret = "pw"
peers = ["tcp://peer1.example.com:11010", "udp://peer2.example.com:11010"]
hostname = "android-device"
''');
      final ok = r as ImportSuccess;
      expect(ok.profile.instanceName, 'android_instance');
      expect(ok.profile.displayName, 'my_easytier_network');
      expect(ok.profile.secret, 'pw');
      expect(ok.profile.peers, hasLength(2));
      expect(ok.profile.hostname, 'android-device');
      expect(
          ok.warnings.any((w) => w.contains('inst_name')), isTrue);
      expect(
          ok.warnings.any((w) => w.contains('"network"')), isTrue);
      expect(
          ok.warnings.any((w) => w.contains('Top-level "peers"')), isTrue);
    });

    test('bare instance_name with weird chars is slugged', () {
      final r = ConfigImporter.import('''
instance_name = "my node!"
[network_identity]
network_name = "net"
''');
      expect((r as ImportSuccess).profile.instanceName, 'my-node-');
    });

    test('empty instance_name falls back to slug of network name', () {
      final r = ConfigImporter.import('''
[network_identity]
network_name = "my net"
''');
      expect((r as ImportSuccess).profile.instanceName, 'my-net');
    });

    test('suggestedName overrides display name', () {
      final r = ConfigImporter.import('''
[network_identity]
network_name = "official-name"
''', suggestedName: 'Imported file');
      expect((r as ImportSuccess).profile.displayName, 'Imported file');
    });

    test('unknown top-level sections are skipped with a warning', () {
      final r = ConfigImporter.import('''
[network_identity]
network_name = "net"

[socks5_proxy]
some_key = "x"
''');
      final ok = r as ImportSuccess;
      expect(ok.profile.displayName, 'net');
      expect(ok.warnings.any((w) => w.contains('[socks5_proxy]')), isTrue);
    });

    test('unterminated string reports the line', () {
      final r = ConfigImporter.import('''
instance_name = "broken
[network_identity]
network_name = "net"
''');
      expect(r, isA<ImportFailure>());
      expect((r as ImportFailure).message, contains('Line 1'));
    });

    test('single-bracket peer table is a clear error', () {
      final r = ConfigImporter.import('''
[network_identity]
network_name = "net"
[peer]
uri = "tcp://1.2.3.4:1"
''');
      expect((r as ImportFailure).message, contains('[[peer]]'));
    });

    test('empty [[peer]] entry is an error', () {
      final r = ConfigImporter.import('''
[network_identity]
network_name = "net"

[[peer]]
''');
      expect((r as ImportFailure).message, contains('missing its uri'));
    });

    test('missing network identity is an error naming the expectation', () {
      final r = ConfigImporter.import('''
instance_name = "x"
''');
      final f = r as ImportFailure;
      expect(f.message, contains('network_name'));
    });

    test('empty input', () {
      expect(ConfigImporter.import('   \n# only a comment\n'),
          isA<ImportFailure>());
    });

    test('imported profile renders valid TOML round-trip fields', () {
      final r = ConfigImporter.import('''
instance_name = "rt"
dhcp = false
ipv4 = "10.126.126.9/24"
[network_identity]
network_name = "round-trip"
network_secret = "abc"

[[peer]]
uri = "tcp://h:1"
''');
      final p = (r as ImportSuccess).profile;
      expect(p.instanceName, 'rt');
      expect(p.toConfig().toToml(p.instanceName), contains('instance_name = "rt"'));
      expect(p.toConfig().toToml(p.instanceName), contains('ipv4 = "10.126.126.9/24"'));
      expect(p.toConfig().toToml(p.instanceName), contains('network_name = "round-trip"'));
      expect(p.toConfig().toToml(p.instanceName), contains('uri = "tcp://h:1"'));
    });

    test('new id is generated per import', () {
      final a = (ConfigImporter.import('[network_identity]\nnetwork_name = "n1"')
              as ImportSuccess)
          .profile;
      final b = (ConfigImporter.import('[network_identity]\nnetwork_name = "n2"')
              as ImportSuccess)
          .profile;
      expect(a.id, isNot(b.id));
      expect(a.id, isNotEmpty);
      expect(a, isA<NetworkProfile>());
    });
  });
}
