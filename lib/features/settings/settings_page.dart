import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('EasyTier Flutter client'),
          ),
        ],
      ),
    );
  }
}
