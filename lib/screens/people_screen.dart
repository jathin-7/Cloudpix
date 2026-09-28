import 'package:flutter/material.dart';
import '../utils/theme.dart';

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('👥 People')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('John Doe'),
            subtitle: const Text('Sample recognized person'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Jane Smith'),
            subtitle: const Text('Sample recognized person'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
