import 'package:flutter/material.dart';

class PeersPage extends StatelessWidget {
  const PeersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Peers')),
      body: const Center(child: Text('No peers — core not integrated yet')),
    );
  }
}
