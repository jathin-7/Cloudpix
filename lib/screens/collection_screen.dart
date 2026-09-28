import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'people_screen.dart';
import 'memories_screen.dart';
import 'secure_folder_screen.dart';
import 'albums_screen.dart';
import 'settings_screen.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<_CollectionItem> items = [
      _CollectionItem('People', Icons.people, () => const PeopleScreen()),
      _CollectionItem('Memories', Icons.auto_awesome, () => const MemoriesScreen()),
      _CollectionItem('Secure', Icons.lock, () => const SecureFolderScreen()),
      _CollectionItem('Albums', Icons.photo_album, () => const AlbumsScreen()),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 24,
            crossAxisSpacing: 24,
            children: items.map((item) => _CollectionBox(item: item, isDark: isDark)).toList(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final name = await showDialog<String>(
            context: context,
            builder: (context) {
              String albumName = '';
              return AlertDialog(
                title: const Text('Create New Album'),
                content: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Album name'),
                  onChanged: (value) => albumName = value,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, albumName),
                    child: const Text('Create'),
                  ),
                ],
              );
            },
          );
          if (name != null && name.trim().isNotEmpty) {
            // TODO: Add album creation logic here
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Album "$name" created!')),
            );
          }
        },
        child: const Icon(Icons.add),
        tooltip: 'Create Album',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}

class _CollectionItem {
  final String label;
  final IconData icon;
  final Widget Function() screenBuilder;
  _CollectionItem(this.label, this.icon, this.screenBuilder);
}

class _CollectionBox extends StatelessWidget {
  final _CollectionItem item;
  final bool isDark;
  const _CollectionBox({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final boxColor = isDark ? AppTheme.surface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.border : AppTheme.lightBorder;
    final iconColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => item.screenBuilder()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return SweepGradient(
                  colors: [
                    Color(0xFF0F9D58), // Green
                    Color(0xFFDB4437), // Red
                    Color(0xFFF4B400), // Yellow
                    Color(0xFF4285F4), // Blue
                    Color(0xFF0F9D58), // Green (to close the circle)
                  ],
                  stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                ).createShader(bounds);
              },
              child: Icon(item.icon, size: 48, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(item.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: iconColor)),
          ],
        ),
      ),
    );
  }
}
