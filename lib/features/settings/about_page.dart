import 'package:flutter/material.dart';

/// About: identity, versions, upstream, license, disclaimer. Kept short.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Column(
            children: [
              Icon(Icons.hub, size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text('EasyTier', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('v0.1.0', style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.api),
                  title: const Text('EasyTier core'),
                  subtitle: Text('upstream main @ ff3921c (post-v2.6.4)',
                      style: theme.textTheme.bodySmall),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Upstream project'),
                  subtitle: Text('github.com/EasyTier/EasyTier',
                      style: theme.textTheme.bodySmall),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('License'),
                  subtitle: Text('LGPL-3.0 (see LICENSE-NOTICES.md)',
                      style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'This app is an independent third-party client and is not the '
              'official EasyTier Android app. It is not affiliated with or '
              'endorsed by the EasyTier project or its authors. EasyTier core '
              'is used under its upstream license.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
