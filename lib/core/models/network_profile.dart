import 'network_config.dart';

/// A user-facing network profile: one named EasyTier network the user can
/// connect to. [displayName] is what the UI shows; [instanceName] is the
/// core instance registration name (must be unique per instance, becomes the
/// TOML `instance_name` key).
class NetworkProfile {
  const NetworkProfile({
    required this.id,
    required this.displayName,
    required this.instanceName,
    this.secret = '',
    this.peers = const [],
    this.dhcp = true,
    this.virtualIpv4 = '',
    this.hostname = '',
    this.latencyFirst = false,
  });

  final String id;
  final String displayName;
  final String instanceName;
  final String secret;
  final List<String> peers;
  final bool dhcp;
  final String virtualIpv4;
  final String hostname;
  final bool latencyFirst;

  NetworkProfile copyWith({
    String? displayName,
    String? instanceName,
    String? secret,
    List<String>? peers,
    bool? dhcp,
    String? virtualIpv4,
    String? hostname,
    bool? latencyFirst,
  }) {
    return NetworkProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      instanceName: instanceName ?? this.instanceName,
      secret: secret ?? this.secret,
      peers: peers ?? this.peers,
      dhcp: dhcp ?? this.dhcp,
      virtualIpv4: virtualIpv4 ?? this.virtualIpv4,
      hostname: hostname ?? this.hostname,
      latencyFirst: latencyFirst ?? this.latencyFirst,
    );
  }

  /// Project onto the legacy NetworkConfig used for TOML rendering and the
  /// connect chain. [networkName] (the EasyTier identity name) is derived
  /// from the display name; keep it stable per profile.
  NetworkConfig toConfig() => NetworkConfig(
        networkName: displayName,
        networkSecret: secret,
        peerUrls: peers,
        virtualIpv4: virtualIpv4,
        hostname: hostname,
        dhcp: dhcp,
        latencyFirst: latencyFirst,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'instanceName': instanceName,
        'secret': secret,
        'peers': peers,
        'dhcp': dhcp,
        'virtualIpv4': virtualIpv4,
        'hostname': hostname,
        'latencyFirst': latencyFirst,
      };

  factory NetworkProfile.fromJson(Map<String, dynamic> j) => NetworkProfile(
        id: j['id'] as String,
        displayName: j['displayName'] as String? ?? 'Unnamed',
        instanceName: j['instanceName'] as String? ?? '',
        secret: j['secret'] as String? ?? '',
        peers: (j['peers'] as List<dynamic>? ?? []).cast<String>(),
        dhcp: j['dhcp'] as bool? ?? true,
        virtualIpv4: j['virtualIpv4'] as String? ?? '',
        hostname: j['hostname'] as String? ?? '',
        latencyFirst: j['latencyFirst'] as bool? ?? false,
      );

  /// Unique-enough local id: millis timestamp + 3 hex chars is fine for a
  /// phone-local list of a handful of profiles.
  static String newId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rnd = (ms ^ identityHashCode(ms)) & 0xfff;
    return '${ms.toRadixString(36)}${rnd.toRadixString(36).padLeft(3, '0')}';
  }
}
