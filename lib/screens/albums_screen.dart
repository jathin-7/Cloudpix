import 'package:flutter/material.dart';
import '../utils/theme.dart';

class AlbumsScreen extends StatelessWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📁 Albums')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_album),
            title: const Text('Vacation 2025'),
            subtitle: const Text('12 photos'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.photo_album),
            title: const Text('Family'),
            subtitle: const Text('8 photos'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
