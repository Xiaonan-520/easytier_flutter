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

  /// Render as official EasyTier TOML. `net_id`-style names are quoted;
  /// empty optional fields are omitted entirely.
  String toToml(String instanceName) {
    final b = StringBuffer()
      ..writeln('inst_name = "$instanceName"')
      ..writeln('network = "${_esc(networkName)}"');
    if (networkSecret.isNotEmpty) {
      b.writeln('network_secret = "${_esc(networkSecret)}"');
    }
    if (peerUrls.isNotEmpty) {
      final urls = peerUrls.map((u) => '"${_esc(u)}"').join(', ');
      b.writeln('peers = [$urls]');
    }
    if (!dhcp && virtualIpv4.isNotEmpty) {
      b.writeln('ipv4 = "$virtualIpv4"');
    }
    if (dhcp) {
      b.writeln('dhcp = true');
    }
    if (hostname.isNotEmpty) {
      b.writeln('hostname = "${_esc(hostname)}"');
    }
    if (latencyFirst) {
      b.writeln('latency_first = true');
    }
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
