/// User-facing network configuration. Serialized to the official EasyTier
/// TOML format (keys match easytier-android-jni/example_config.toml).
class NetworkConfig {
  const NetworkConfig({
    this.networkName = '',
    this.networkSecret = '',
    this.peerUrls = const [],
    this.virtualIpv4 = '',
    this.hostname = '',
    this.dhcp = true,
    this.latencyFirst = false,
  });

  final String networkName;
  final String networkSecret;
  final List<String> peerUrls;
  final String virtualIpv4;
  final String hostname;
  final bool dhcp;
  final bool latencyFirst;

  NetworkConfig copyWith({
    String? networkName,
    String? networkSecret,
    List<String>? peerUrls,
    String? virtualIpv4,
    String? hostname,
    bool? dhcp,
    bool? latencyFirst,
  }) {
    return NetworkConfig(
      networkName: networkName ?? this.networkName,
      networkSecret: networkSecret ?? this.networkSecret,
      peerUrls: peerUrls ?? this.peerUrls,
      virtualIpv4: virtualIpv4 ?? this.virtualIpv4,
      hostname: hostname ?? this.hostname,
      dhcp: dhcp ?? this.dhcp,
      latencyFirst: latencyFirst ?? this.latencyFirst,
    );
  }

  /// Render as official EasyTier TOML matching the core TomlConfigLoader
  /// Config struct (easytier-core/src/config/toml.rs): network name/secret
  /// live under [network_identity], peers are [[peer]] arrays with `uri`.
  /// Empty optional fields are omitted entirely.
  String toToml(String instanceName) {
    final b = StringBuffer()
      // NOTE: the core Config struct field is instance_name (no inst_name
      // alias) — the old key was silently ignored and the instance fell back
      // to the default name "default", breaking setTunFd lookups.
      ..writeln('instance_name = "$instanceName"')
      ..writeln('listeners = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010", "wg://0.0.0.0:11011"]');
    if (!dhcp && virtualIpv4.isNotEmpty) {
      b.writeln('ipv4 = "$virtualIpv4"');
    } else if (dhcp) {
      b.writeln('dhcp = true');
    }
    if (hostname.isNotEmpty) {
      b.writeln('hostname = "${_esc(hostname)}"');
    }
    b.writeln('\n[network_identity]');
    b.writeln('network_name = "${_esc(networkName)}"');
    if (networkSecret.isNotEmpty) {
      b.writeln('network_secret = "${_esc(networkSecret)}"');
    }
    for (final uri in peerUrls) {
      b.writeln('\n[[peer]]');
      b.writeln('uri = "${_esc(uri)}"');
    }
    b.writeln('\n[flags]');
    if (latencyFirst) {
      b.writeln('latency_first = true');
    }
    b.writeln('bind_device = false');
    b.writeln('dev_name = "easytier0"');
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'networkName': networkName,
        'networkSecret': networkSecret,
        'peerUrls': peerUrls,
        'virtualIpv4': virtualIpv4,
        'hostname': hostname,
        'dhcp': dhcp,
        'latencyFirst': latencyFirst,
      };

  factory NetworkConfig.fromJson(Map<String, dynamic> j) => NetworkConfig(
        networkName: j['networkName'] as String? ?? '',
        networkSecret: j['networkSecret'] as String? ?? '',
        peerUrls: (j['peerUrls'] as List<dynamic>? ?? []).cast<String>(),
        virtualIpv4: j['virtualIpv4'] as String? ?? '',
        hostname: j['hostname'] as String? ?? '',
        dhcp: j['dhcp'] as bool? ?? true,
        latencyFirst: j['latencyFirst'] as bool? ?? false,
      );

  static String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
