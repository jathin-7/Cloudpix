import 'package:flutter/material.dart';
import '../utils/theme.dart';

class MemoriesScreen extends StatelessWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🧠 Memories')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.photo),
            title: const Text('Trip to Paris'),
            subtitle: const Text('April 2025'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.photo),
            title: const Text('Birthday Party'),
            subtitle: const Text('June 2025'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

