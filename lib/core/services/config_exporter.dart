import 'dart:convert' show utf8;
import 'dart:io' show Directory, File;

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/network_profile.dart';
import '../models/network_config.dart';

/// Renders a [NetworkProfile] as an official EasyTier TOML config and hands
/// it to the system save/share sheets. The TOML itself is the existing
/// [NetworkConfig.toToml] renderer — the same bytes we feed the core — so
/// an exported file round-trips through ConfigImporter into an equal
/// profile.
class ConfigExporter {
  /// Sanitized file name: the display name slugified plus .toml, so every
  /// filesystem accepts it.
  static String fileNameOf(NetworkProfile profile) {
    final base = profile.displayName.trim().isEmpty
        ? 'easytier-config'
        : profile.displayName.trim();
    final slug = base.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
    return '$slug.toml';
  }

  /// The exact TOML the core would accept for this profile.
  static String tomlOf(NetworkProfile profile) =>
      profile.toConfig().toToml(profile.instanceName);

  /// Open the Android save sheet (SAF). Returns null when cancelled.
  static Future<Object?> save(NetworkProfile profile, String toml) {
    return FilePicker.saveFile(
      fileName: fileNameOf(profile),
      bytes: utf8.encode(toml),
      mimeType: 'text/plain',
      dialogTitle: 'Save EasyTier config',
      type: FileType.custom,
      allowedExtensions: ['toml'],
    );
  }

  /// Open the system share sheet with the config as a .toml file.
  static Future<void> share(NetworkProfile profile, String toml) async {
    final file = File('${Directory.systemTemp.path}/${fileNameOf(profile)}');
    await file.writeAsString(toml, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      subject: 'EasyTier config — ${profile.displayName}',
      title: fileNameOf(profile),
    ));
  }
}
