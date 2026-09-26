import 'package:flutter/material.dart';

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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('EasyTier Flutter', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Third-party Material 3 client for EasyTier',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.tag),
            title: Text('Version'),
            trailing: Text('0.1.0'),
          ),
          const ListTile(
            leading: Icon(Icons.api),
            title: Text('EasyTier core'),
            subtitle: Text('upstream v2.6.4 (8428a89)'),
          ),
          const ListTile(
            leading: Icon(Icons.link),
            title: Text('Upstream project'),
            subtitle: Text('github.com/EasyTier/EasyTier'),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'This app is an independent third-party client. It is not the '
              'official EasyTier Android app. EasyTier core is used under its '
              'license; see the upstream repository for details.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
