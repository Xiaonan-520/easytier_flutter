import 'package:flutter/material.dart';

/// Placeholder dashboard. Real connection state arrives with the native
/// EasyTier integration (Phase 3).
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('EasyTier')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle, size: 12, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Text('Not running', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Connect'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Network', style: theme.textTheme.titleMedium),
          const Card(child: ListTile(title: Text('No configuration yet'))),
        ],
      ),
    );
  }
}
