import '../models/network_profile.dart';

/// Result of importing an official EasyTier TOML config.
sealed class ImportResult {
  const ImportResult();
}

class ImportSuccess extends ImportResult {
  const ImportSuccess(this.profile, this.warnings);

  /// Newly built profile — never persisted yet; the caller decides.
  final NetworkProfile profile;

  /// Non-fatal notes: unknown keys skipped, legacy aliases used, etc.
  final List<String> warnings;
}

class ImportFailure extends ImportResult {
  const ImportFailure(this.message);

  /// Human-readable reason (parse error with line info, missing identity…).
  final String message;
}

/// Parses an official EasyTier TOML config into a [NetworkProfile].
///
/// The field mapping follows the core `Config` struct
/// (easytier-core/src/config/toml.rs, `deny_unknown_fields`):
/// - `instance_name` → [NetworkProfile.instanceName]
/// - `[network_identity]` `network_name` / `network_secret` → display name /
///   secret
/// - `[[peer]]` `uri` entries → [NetworkProfile.peers]
/// - `ipv4` (with or without prefix) + absence/presence of `dhcp`
/// - `hostname`
/// - `[flags]` `latency_first`
///
/// Also accepted for convenience (they appear in the wild — e.g. the
/// official android-jni example config and some generated files):
/// `inst_name` (legacy alias), top-level `network_name`/`network_secret`,
/// top-level `peers = [...]`, and `virtual_ipv4`. Ambiguities are surfaced
/// as warnings rather than silently picked.
class ConfigImporter {
  /// Minimal TOML for EasyTier configs: comments, `[table]`, `[[array]]`,
  /// basic strings, booleans, and one-line arrays of strings. Deliberately
  /// not a full TOML implementation — anything else surfaces as an error
  /// naming the offending line, never as a wrong profile.
  static ImportResult import(String source, {String? suggestedName}) {
    if (source.trim().isEmpty) {
      return const ImportFailure('The file is empty.');
    }

    final toplevel = <String, Object?>{};
    final networkIdentity = <String, Object?>{};
    final flags = <String, Object?>{};
    final peerList = <Map<String, Object?>>[];
    final warnings = <String>[];

    var section = toplevel;
    var i = 0;
    for (var rawLine in source.split('\n')) {
      i++;
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Strip trailing comments outside quotes.
      line = _stripComment(line);
      if (line.isEmpty) continue;

      final tableHeader = RegExp(r'^\[\[([A-Za-z0-9_-]+)\]\]$').firstMatch(line);
      if (tableHeader != null) {
        switch (tableHeader.group(1)) {
          case 'peer':
            final peer = <String, Object?>{};
            peerList.add(peer);
            section = peer;
          case 'network_identity':
            return ImportFailure(
                'Line $i: [[network_identity]] is not valid — use the [network_identity] table (single brackets).');
          default:
            return ImportFailure(
                'Line $i: unsupported section [[${tableHeader.group(1)}]] — this app supports the main config, [network_identity], [flags] and [[peer]].');
        }
        continue;
      }

      final header = RegExp(r'^\[([A-Za-z0-9_.-]+)\]$').firstMatch(line);
      if (header != null) {
        switch (header.group(1)) {
          case 'network_identity':
            section = networkIdentity;
          case 'flags':
            section = flags;
          case 'peer':
            return ImportFailure(
                'Line $i: [peer] must be [[peer]] (double brackets).');
          default:
            warnings.add('Skipped section [${header.group(1)}] (not supported on mobile)');
            section = _deadSection;
          }
        continue;
      }

      final kv = RegExp('^([A-Za-z0-9_-]+)\\s*=\\s*(.+)\$').firstMatch(line);
      if (kv == null) {
        return ImportFailure(
            'Line $i: cannot understand "$rawLine" (expected key = value).');
      }
      final key = kv.group(1)!;
      Object? value;
      try {
        value = _parseValue(kv.group(2)!.trim());
      } on _ValueError catch (e) {
        return ImportFailure('Line $i: ${e.message}');
      }

      final target = section == _deadSection ? null : section;
      if (target == null) continue;
      if (target.containsKey(key)) {
        warnings.add('Line $i: "$key" is set twice; the later value wins');
      }
      target[key] = value;
    }

    // --- Legacy alias handling (warn, never guess silently) ---------------
    final top = Map<String, Object?>.of(toplevel);
    if (!top.containsKey('instance_name') && top.containsKey('inst_name')) {
      top['instance_name'] = top['inst_name'];
      warnings.add('Legacy key "inst_name" used as instance_name');
    }
    if (!networkIdentity.containsKey('network_name') &&
        top.containsKey('network')) {
      networkIdentity['network_name'] = top['network'];
      warnings.add('Legacy key "network" used as network_name');
    }
    if (!networkIdentity.containsKey('network_name') &&
        top.containsKey('network_name')) {
      networkIdentity['network_name'] = top['network_name'];
      warnings.add('Top-level "network_name" used as [network_identity].network_name');
    }
    if (!networkIdentity.containsKey('network_secret') &&
        top.containsKey('network_secret')) {
      networkIdentity['network_secret'] = top['network_secret'];
      warnings.add('Top-level "network_secret" used as [network_identity].network_secret');
    }
    if (peerList.isEmpty && top['peers'] != null) {
      final legacy = top['peers'];
      if (legacy is List<Object?>) {
        for (final u in legacy) {
          peerList.add({'uri': u});
        }
        warnings.add('Top-level "peers" array used as [[peer]] entries');
      }
    }

    // --- Required fields --------------------------------------------------
    final networkName =
        (networkIdentity['network_name'] as String?)?.trim() ?? '';
    if (networkName.isEmpty) {
      return const ImportFailure(
          'Missing network name: expected [network_identity] network_name = "…" (or legacy top-level network = "…").');
    }

    final peers = <String>[];
    for (final peer in peerList) {
      final uri = peer['uri'];
      if (uri is! String || uri.trim().isEmpty) {
        return const ImportFailure(
            'A [[peer]] entry is missing its uri = "tcp://host:port" field.');
      }
      peers.add(uri.trim());
    }

    // --- Optional fields --------------------------------------------------
    final dhcpRaw = top['dhcp'];
    var dhcp = true;
    if (dhcpRaw is bool) {
      dhcp = dhcpRaw;
    } else if (dhcpRaw is String) {
      // Some configs write dhcp = "yes"/"no" (the CLI accepts it).
      switch (dhcpRaw.toLowerCase()) {
        case 'yes' || 'true':
          dhcp = true;
        case 'no' || 'false':
          dhcp = false;
        default:
          return const ImportFailure(
              'dhcp must be true/false ("yes"/"no" accepted).');
      }
    } else if (dhcpRaw != null) {
      return const ImportFailure('dhcp must be true or false.');
    }

    var virtualIpv4 =
        (top['ipv4'] as String?) ?? (top['virtual_ipv4'] as String?) ?? '';
    if (dhcp && virtualIpv4.isNotEmpty) {
      warnings.add('Both dhcp and ipv4 are set; ipv4 is kept but unused while DHCP is on');
    }

    var latencyFirst = false;
    final lf = flags['latency_first'];
    if (lf is bool) latencyFirst = lf;

    final hostname = (top['hostname'] as String?)?.trim() ?? '';

    var instanceName = ((top['instance_name'] as String?) ?? '').trim();
    instanceName = _slugify(instanceName);

    final displayName = (suggestedName?.trim().isNotEmpty ?? false)
        ? suggestedName!.trim()
        : networkName;

    final profile = NetworkProfile(
      id: NetworkProfile.newId(),
      displayName: displayName,
      instanceName: instanceName.isEmpty ? _slugify(networkName) : instanceName,
      secret: (networkIdentity['network_secret'] as String?) ?? '',
      peers: peers,
      dhcp: dhcp,
      virtualIpv4: virtualIpv4,
      hostname: hostname,
      latencyFirst: latencyFirst,
    );
    return ImportSuccess(profile, warnings);
  }

  /// Sections we recognise but do not support: swallow their keys.
  static final Map<String, Object?> _deadSection = {};

  static String _stripComment(String line) {
    var inString = false;
    for (var i = 0; i < line.length; i++) {
      final c = line.codeUnitAt(i);
      if (c == 0x22 /* " */ ) inString = !inString;
      if (c == 0x23 /* # */ && !inString) return line.substring(0, i).trim();
    }
    return line;
  }

  static Object? _parseValue(String raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    if (raw.startsWith('"')) {
      final closed = raw.endsWith('"') && raw.length >= 2;
      if (!closed) throw const _ValueError('unterminated string');
      return _unescape(raw.substring(1, raw.length - 1));
    }
    if (raw.startsWith('[')) {
      if (!raw.endsWith(']')) throw const _ValueError('unterminated array');
      final inner = raw.substring(1, raw.length - 1).trim();
      if (inner.isEmpty) return <Object?>[];
      return [
        for (final part in _splitTopLevel(inner, ','))
          if (part.trim().isNotEmpty) _parseValue(part.trim()),
      ];
    }
    // Bare key / number: accept as string only when it looks harmless.
    throw _ValueError(
        'only strings ("…"), booleans (true/false) and string arrays are supported, got: $raw');
  }

  static Iterable<String> _splitTopLevel(String s, String sep) sync* {
    var inString = false;
    var depth = 0;
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') inString = !inString;
      if (!inString) {
        if (c == '[') depth++;
        if (c == ']') depth--;
        if (c == sep && depth == 0) {
          yield buf.toString();
          buf.clear();
          continue;
        }
      }
      buf.write(c);
    }
    yield buf.toString();
  }

  static String _unescape(String s) => s
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t');

  /// TOML instance names must stay [a-zA-Z0-9_-] for our core usage; map
  /// anything else to '-' like the editor's slug does.
  static String _slugify(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
}

class _ValueError implements Exception {
  const _ValueError(this.message);
  final String message;
}
