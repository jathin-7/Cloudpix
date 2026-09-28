import 'package:flutter/material.dart';
import 'utils/theme.dart';
import 'providers/theme_provider.dart';
import 'screens/photos_screen.dart';
import 'screens/memories_screen.dart';
import 'screens/albums_screen.dart';
import 'screens/people_screen.dart';
import 'screens/secure_folder_screen.dart';
import 'screens/storage_screen.dart';
import 'services/auto_backup_service.dart';
import 'services/google_drive_service.dart';
import 'screens/collection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AutoBackupService.initialize();
  await GoogleDriveService.syncAccountsToNativeNow();
  await AutoBackupService.ensureScheduledIfEnabled();
  await AutoBackupService.startLiveMonitoring();
  runApp(const CloudpixApp());
}

class CloudpixApp extends StatefulWidget {
  const CloudpixApp({super.key});

  @override
  State<CloudpixApp> createState() => _CloudpixAppState();
}

class _CloudpixAppState extends State<CloudpixApp> {
  late ThemeProvider _themeProvider;

  @override
  void initState() {
    super.initState();
    _themeProvider = ThemeProvider();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeProvider,
      builder: (context, _) {
        return MaterialApp(
          title: 'Cloudpix',
          debugShowCheckedModeBanner: false,
          theme: _themeProvider.isDarkMode ? AppTheme.dark : AppTheme.light,
          home: MainShell(themeProvider: _themeProvider),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  final ThemeProvider themeProvider;

  const MainShell({super.key, required this.themeProvider});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  final _tabs = const [
    (icon: Icons.photo_library_outlined, activeIcon: Icons.photo_library_rounded, label: 'Photos'),
    (icon: Icons.grid_view_rounded, activeIcon: Icons.grid_view_rounded, label: 'Collections'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeProvider.isDarkMode;
    final bgColor = isDark ? AppTheme.surface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.border : AppTheme.lightBorder;
    final tabColor = isDark ? AppTheme.textHint : AppTheme.lightTextHint;
    final activeTabColor = AppTheme.primary;

    final screens = [
      PhotosScreen(themeProvider: widget.themeProvider),
      CollectionScreen(),
    ];

    // Google colors
    const blue = Color(0xFF4285F4);
    const red = Color(0xFFDB4437);
    const yellow = Color(0xFFF4B400);
    const green = Color(0xFF0F9D58);
    const white = Color(0xFFFFFFFF);

    return Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: borderColor, width: 0.5)),
        ),
        child: SafeArea(
          child: Row(children: [
            // Photos tab (all colors)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = 0),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return SweepGradient(
                          colors: [green, red, yellow, blue, green],
                          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                        ).createShader(bounds);
                      },
                      child: Icon(_tab == 0 ? _tabs[0].activeIcon : _tabs[0].icon,
                        color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 5),
                    Text(_tabs[0].label, style: TextStyle(
                      color: blue,
                      fontSize: 13,
                      fontWeight: _tab == 0 ? FontWeight.w600 : FontWeight.w400,
                    )),
                  ]),
                ),
              ),
            ),
            // Collections tab (all colors)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = 1),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return SweepGradient(
                          colors: [green, red, yellow, blue, green],
                          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                        ).createShader(bounds);
                      },
                      child: Icon(_tab == 1 ? _tabs[1].activeIcon : _tabs[1].icon,
                        color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 5),
                    Text(_tabs[1].label, style: TextStyle(
                      color: red,
                      fontSize: 13,
                      fontWeight: _tab == 1 ? FontWeight.w600 : FontWeight.w400,
                    )),
                  ]),
                ),
              ),
            ),
            // Storage tab (all colors)
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageScreen())),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return SweepGradient(
                          colors: [green, red, yellow, blue, green],
                          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                        ).createShader(bounds);
                      },
                      child: const Icon(Icons.storage_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 5),
                    Text('Storage', style: TextStyle(color: yellow, fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
      // Removed FloatingActionButton because we are migrating to Instant Automatic Backups via Foreground Service.
      floatingActionButton: null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}
