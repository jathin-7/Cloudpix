import 'package:flutter/material.dart';
import '../utils/theme.dart';

class SecureFolderScreen extends StatelessWidget {
  const SecureFolderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🔒 Secure Folder')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Private Photo 1'),
            subtitle: const Text('Locked'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Private Photo 2'),
            subtitle: const Text('Locked'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

