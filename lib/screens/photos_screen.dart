import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../providers/theme_provider.dart';
import '../services/auto_backup_service.dart';
import '../services/google_drive_service.dart';
import '../services/local_database.dart';
import 'storage_screen.dart';
import '../utils/theme.dart';
import '../widgets/widgets.dart';

const _hiddenLocalIdsKey = 'cloudpix_hidden_local_ids';

class PhotosScreen extends StatefulWidget {
  final ThemeProvider? themeProvider;

  const PhotosScreen({Key? key, this.themeProvider}) : super(key: key);

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> with WidgetsBindingObserver {
  late ThemeProvider _themeProvider;
  List<AssetEntity> _assets = [];
  Map<String, bool> _backedByLocalId = <String, bool>{};
  Map<String, CloudPhoto> _cloudByLocalId = <String, CloudPhoto>{};
  List<_AssetGroup> _assetGroups = [];
  List<PhotoGroup> _cloudOnlyGroups = [];
  Map<String, bool> _eligibleForBackup = <String, bool>{};
  BackupStatusSnapshot _backupStatus = BackupStatusSnapshot.idle();
  bool _hasDriveAccount = true;
  bool _hasMediaPermission = false;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeProvider = widget.themeProvider ?? ThemeProvider();
    _refreshFromBackup(runSync: false);
    // Periodically refresh only backup status to keep UI responsive.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadBackupStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFromBackup(runSync: false);
    }
  }

  Future<void> _loadPhotos() async {
    try {
      final accounts = await GoogleDriveService.loadAccounts();
      final permission = await PhotoManager.requestPermissionExtend();
      final hasPermission = permission.isAuth;

      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _hasDriveAccount = accounts.isNotEmpty;
            _hasMediaPermission = false;
            _assets = [];
            _backedByLocalId = <String, bool>{};
            _loading = false;
          });
        }
        return;
      }

      final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
      final allAssets = <AssetEntity>[];
      if (paths.isNotEmpty) {
        final main = paths.first;
        final total = await main.assetCountAsync;
        const pageSize = 200;
        int start = 0;
        while (start < total) {
          final end = (start + pageSize).clamp(0, total);
          final page = await main.getAssetListRange(start: start, end: end);
          allAssets.addAll(page);
          start = end;
        }
      }

      // Remove any items the user has chosen to hide from Cloudpix.
      final prefs = await SharedPreferences.getInstance();
      final hidden = prefs.getStringList(_hiddenLocalIdsKey) ?? <String>[];
      final hiddenSet = hidden.toSet();
      allAssets.removeWhere((asset) => hiddenSet.contains(asset.id));

      // Newest first
      allAssets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      final backedIds = await LocalDatabase.getAllBackedLocalIds();
      final localIds = allAssets.map((a) => a.id).toSet();
      final cloudByLocalId = await LocalDatabase.getPhotosByLocalIds(localIds);
      final backedMap = <String, bool>{
        for (final asset in allAssets)
          asset.id: backedIds.contains(asset.id) || cloudByLocalId.containsKey(asset.id),
      };

      // Drive-backed items that no longer exist in the phone gallery
      // should still appear in Cloudpix. Fetch them and group by date.
      final cloudOnly = await LocalDatabase.getBackedPhotosWithoutLocalIds(localIds);
      final cloudOnlyGroups = _groupByDate(cloudOnly);

      // Determine which items are eligible for backup (taken on or after
      // the app's backup start cutoff, typically install day).
      final cutoffMs = await AutoBackupService.getStartCutoffMs();
      final eligibleMap = <String, bool>{};
      for (final asset in allAssets) {
        final created = asset.createDateTime.millisecondsSinceEpoch;
        final modified = asset.modifiedDateTime.millisecondsSinceEpoch;
        final timeMs = created > 0
            ? created
            : (modified > 0 ? modified : DateTime.now().millisecondsSinceEpoch);
        eligibleMap[asset.id] = timeMs >= cutoffMs;
      }

      // Group into date buckets (Today, Yesterday, then by calendar date).
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final Map<String, List<AssetEntity>> grouped = {};
      final Map<String, DateTime> groupDay = {};

      for (final asset in allAssets) {
        final dt = asset.createDateTime;
        final day = DateTime(dt.year, dt.month, dt.day);
        String label;
        if (day == today) {
          label = 'Today';
        } else if (day == yesterday) {
          label = 'Yesterday';
        } else if (day.year == now.year) {
          label = DateFormat('MMMM d').format(dt);
        } else {
          label = DateFormat('MMMM d, yyyy').format(dt);
        }
        grouped.putIfAbsent(label, () => <AssetEntity>[]).add(asset);
        groupDay[label] = day;
      }

      final groups = grouped.entries.map((entry) {
        final assetsInGroup = [...entry.value]
          ..sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
        final day = groupDay[entry.key] ?? today;
        return _AssetGroup(label: entry.key, assets: assetsInGroup, day: day);
      }).toList()
        ..sort((a, b) => b.day.compareTo(a.day));

      if (mounted) {
        setState(() {
          _hasDriveAccount = accounts.isNotEmpty;
          _hasMediaPermission = true;
          _assets = allAssets;
          _backedByLocalId = backedMap;
          _cloudByLocalId = cloudByLocalId;
          _eligibleForBackup = eligibleMap;
          _assetGroups = groups;
          _cloudOnlyGroups = cloudOnlyGroups;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadBackupStatus() async {
    final status = await AutoBackupService.getLastStatus();
    if (!mounted) return;
    setState(() => _backupStatus = status);
  }

  Future<void> _refreshFromBackup({bool runSync = true}) async {
    await _loadBackupStatus();
    await _loadPhotos();
    if (runSync && await AutoBackupService.isEnabled()) {
      // Queue a background sync instead of foreground gallery scan.
      unawaited(AutoBackupService.triggerNow());
    }
  }

  Future<void> _openStorage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StorageScreen()),
    );
    await _refreshFromBackup();
  }

  Future<void> _openPermissionSettings() async {
    try {
      final status = await PhotoManager.requestPermissionExtend();
      if (status.isAuth) {
        await _refreshFromBackup();
        return;
      }
    } catch (_) {}
    await openAppSettings();
  }

  List<PhotoGroup> _groupByDate(List<CloudPhoto> photos) {
    final sortedPhotos = [...photos]
      ..sort((a, b) {
        final byTaken = b.takenAt.compareTo(a.takenAt);
        if (byTaken != 0) return byTaken;
        return b.createdAt.compareTo(a.createdAt);
      });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final Map<String, List<CloudPhoto>> grouped = {};

    for (final photo in sortedPhotos) {
      final date = DateTime(photo.takenAt.year, photo.takenAt.month, photo.takenAt.day);
      String label;
      if (date == today) {
        label = 'Today';
      } else if (date == yesterday) {
        label = 'Yesterday';
      } else if (date.year == now.year) {
        label = DateFormat('MMMM d').format(photo.takenAt);
      } else {
        label = DateFormat('MMMM d, yyyy').format(photo.takenAt);
      }
      grouped.putIfAbsent(label, () => []).add(photo);
    }

    for (final list in grouped.values) {
      list.sort((a, b) {
        final byTaken = b.takenAt.compareTo(a.takenAt);
        if (byTaken != 0) return byTaken;
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return grouped.entries
        .map((e) => PhotoGroup(dateLabel: e.key, photos: e.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.cloud_rounded,
                  size: 32,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Photos'),
          ],
        ),
        actions: [
          // Theme toggle button with sun/moon icons
          ListenableBuilder(
            listenable: _themeProvider,
            builder: (context, _) {
              return IconButton(
                icon: Icon(
                  _themeProvider.isDarkMode
                    ? Icons.light_mode_rounded  // Sun icon for light mode
                    : Icons.dark_mode_rounded,   // Moon icon for dark mode
                  size: 24,
                ),
                onPressed: () => _themeProvider.toggleTheme(),
                tooltip: _themeProvider.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              );
            },
          ),
          const SizedBox(width: 4),
          // Profile icon with 4-color border
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
              ),
              child: CustomPaint(
                painter: GoogleCircleBorderPainter(),
                child: Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_circle, color: Color(0xFF757575), size: 26),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : !_hasDriveAccount
              ? RefreshIndicator(
              onRefresh: () => _refreshFromBackup(runSync: false),
                  color: AppTheme.primary,
                  child: ListView(
                    children: [
                      const SizedBox(height: 100),
                      const EmptyState(
                        emoji: '☁️',
                        title: 'Connect Google Account',
                        subtitle: 'Add a Google account in Storage to enable\nautomatic photo backup and gallery view.',
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ElevatedButton.icon(
                          onPressed: _openStorage,
                          icon: const Icon(Icons.storage_rounded),
                          label: const Text('Open Storage'),
                        ),
                      ),
                    ],
                  ),
                  )
          : !_hasMediaPermission
              ? RefreshIndicator(
                onRefresh: () => _refreshFromBackup(runSync: false),
                  color: AppTheme.primary,
                  child: ListView(
                    children: [
                      _BackupStatusCard(
                        status: _backupStatus,
                        onOpenStorage: _openStorage,
                        onOpenPermissionSettings: _openPermissionSettings,
                      ),
                      const SizedBox(height: 90),
                      const EmptyState(
                        emoji: '🔒',
                        title: 'Allow Photos/Videos',
                        subtitle: 'Turn on Photos/Videos permission so Cloudpix can show your gallery and start backup.',
                      ),
                    ],
                  ),
                )
            : _assets.isEmpty && _cloudOnlyGroups.isEmpty
              ? RefreshIndicator(
                onRefresh: () => _refreshFromBackup(runSync: false),
                  color: AppTheme.primary,
                  child: ListView(
                    children: [
                      _BackupStatusCard(
                        status: _backupStatus,
                        onOpenStorage: _openStorage,
                        onOpenPermissionSettings: _openPermissionSettings,
                      ),
                      const SizedBox(height: 90),
                      const EmptyState(
                        emoji: '📸',
                        title: 'No Photos Yet',
                        subtitle: 'Take a photo with your camera.\nIt will appear here and be backed up automatically.',
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshFromBackup,
                  color: AppTheme.primary,
                  child: Builder(
                    builder: (_) {
                      final allAssets = _assets;
                      final indexById = <String, int>{
                        for (int i = 0; i < allAssets.length; i++) allAssets[i].id: i,
                      };

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        itemCount: 1 + _assetGroups.length + _cloudOnlyGroups.length,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _BackupStatusCard(
                              status: _backupStatus,
                              onOpenStorage: _openStorage,
                              onOpenPermissionSettings: _openPermissionSettings,
                            );
                          }
                          final localIndex = index - 1;
                          if (localIndex < _assetGroups.length) {
                            final group = _assetGroups[localIndex];
                            return _AssetGroupSection(
                              group: group,
                              allAssets: allAssets,
                              indexById: indexById,
                              backedByLocalId: _backedByLocalId,
                              cloudByLocalId: _cloudByLocalId,
                              eligibleByLocalId: _eligibleForBackup,
                              isBackupRunning: _backupStatus.running,
                              isUploadingStage: _backupStatus.stage == 'uploading',
                            );
                          }

                          final cloudIndex = localIndex - _assetGroups.length;
                          final cloudGroup = _cloudOnlyGroups[cloudIndex];
                          return _CloudGroupSection(group: cloudGroup);
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _BackupStatusCard extends StatelessWidget {
  final BackupStatusSnapshot status;
  final VoidCallback onOpenStorage;
  final VoidCallback onOpenPermissionSettings;
  const _BackupStatusCard({
    required this.status,
    required this.onOpenStorage,
    required this.onOpenPermissionSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.surface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.border : AppTheme.lightBorder;
    final titleColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final subtitleColor = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    final statusColor = switch (status.stage) {
      'success' => AppTheme.accent,
      'partial' => AppTheme.warning,
      'error' => AppTheme.danger,
      'blocked' => AppTheme.danger,
      'uploading' => AppTheme.primary,
      _ => subtitleColor,
    };

    final timestamp = DateFormat('MMM d, yyyy · h:mm a').format(status.updatedAt);
    final messageLower = status.message.toLowerCase();
    final blockedByPermission = status.stage == 'blocked' && messageLower.contains('permission');
    final blockedByAccount = status.stage == 'blocked' &&
      (messageLower.contains('google account') ||
        messageLower.contains('session expired') ||
        messageLower.contains('reconnect') ||
        messageLower.contains('authentication') ||
        messageLower.contains('credentials'));

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.running ? Icons.sync_rounded : Icons.cloud_done_rounded, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Text(
                status.running ? 'Backup in progress' : 'Backup status',
                style: TextStyle(color: titleColor, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                timestamp,
                style: TextStyle(color: subtitleColor, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status.message,
            style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Backed: ${status.backed}   Failed: ${status.failed}   Skipped: ${status.skipped}   Total: ${status.total}',
            style: TextStyle(color: subtitleColor, fontSize: 11),
          ),
          // Permission is controlled from Settings; no extra button here.
          if (blockedByAccount) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: onOpenStorage,
              icon: const Icon(Icons.storage_rounded, size: 16),
              label: const Text('Connect Google Account'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Date Group Section (header + grid) ─────────────────────────────────────
class _AssetGroupSection extends StatelessWidget {
  final _AssetGroup group;
  final List<AssetEntity> allAssets;
  final Map<String, int> indexById;
  final Map<String, bool> backedByLocalId;
  final Map<String, CloudPhoto> cloudByLocalId;
  final Map<String, bool> eligibleByLocalId;
  final bool isBackupRunning;
  final bool isUploadingStage;

  const _AssetGroupSection({
    required this.group,
    required this.allAssets,
    required this.indexById,
    required this.backedByLocalId,
    required this.cloudByLocalId,
    required this.eligibleByLocalId,
    required this.isBackupRunning,
    required this.isUploadingStage,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(
            group.label,
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: group.assets.length,
          itemBuilder: (context, index) {
            final asset = group.assets[index];
            final isBacked = backedByLocalId[asset.id] ?? false;
            final isEligible = eligibleByLocalId[asset.id] ?? false;
            // Show the "uploading" spinner only while the backup
            // job is actually in the uploading stage, so photos
            // don't appear to be stuck forever during scanning.
            final isActiveUpload =
              isBackupRunning && isUploadingStage && !isBacked && isEligible;

            return GestureDetector(
              onTap: () async {
                final initialIndex = indexById[asset.id];
                if (initialIndex == null) return;
                final deleted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => _DeviceFullScreenPager(
                      assets: allAssets,
                      initialIndex: initialIndex,
                      backedByLocalId: backedByLocalId,
                      cloudByLocalId: cloudByLocalId,
                    ),
                  ),
                );
                if (deleted == true) {
                  final state = context.findAncestorStateOfType<_PhotosScreenState>();
                  await state?._refreshFromBackup(runSync: false);
                }
              },
              child: _DevicePhotoTile(
                asset: asset,
                isBacked: isBacked,
                isActiveUpload: isActiveUpload,
                isEligible: isEligible,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AssetGroup {
  final String label;
  final List<AssetEntity> assets;
  final DateTime day;

  const _AssetGroup({
    required this.label,
    required this.assets,
    required this.day,
  });
}

// ── Cloud-only (Drive) group section ───────────────────────────────────────
class _CloudGroupSection extends StatelessWidget {
  final PhotoGroup group;
  const _CloudGroupSection({required this.group});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            group.dateLabel,
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: group.photos.length,
          itemBuilder: (context, index) {
            final photo = group.photos[index];
            return _DrivePhotoTile(photo: photo, allPhotos: group.photos, initialIndex: index);
          },
        ),
      ],
    );
  }
}

// ── Device Photo Tile (local gallery item) ───────────────────────────────────
class _DevicePhotoTile extends StatefulWidget {
  final AssetEntity asset;
  final bool isBacked;
  final bool isActiveUpload;
  final bool isEligible;
  const _DevicePhotoTile({
    required this.asset,
    required this.isBacked,
    required this.isActiveUpload,
    required this.isEligible,
  });

  @override
  State<_DevicePhotoTile> createState() => _DevicePhotoTileState();
}

class _DevicePhotoTileState extends State<_DevicePhotoTile> {
  Uint8List? _thumbBytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      final bytes = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(512, 512));
      if (mounted) {
        setState(() {
          _thumbBytes = bytes != null ? Uint8List.fromList(bytes) : null;
          _loading = false;
          _error = bytes == null;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt;
    final isVideo = widget.asset.type == AssetType.video;

    return Container(
      decoration: BoxDecoration(
        color: placeholderColor,
      ),
      child: _loading
          ? _buildShimmer(placeholderColor)
          : _error || _thumbBytes == null
              ? _buildErrorPlaceholder(isDark)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      _thumbBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _buildErrorPlaceholder(isDark),
                    ),
                    if (isVideo)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    // Backup status icon (bottom-right)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _buildBackupStatusIcon(context),
                    ),
                  ],
                ),
    );
  }

  Widget _buildShimmer(Color color) {
    return Container(
      color: color,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(bool isDark) {
    final isVideo = widget.asset.type == AssetType.video;
    return Container(
      color: isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt,
      child: Icon(
        isVideo ? Icons.videocam_rounded : Icons.image_rounded,
        color: isDark ? AppTheme.textHint : AppTheme.lightTextHint,
        size: 28,
      ),
    );
  }

  Widget _buildBackupStatusIcon(BuildContext context) {
    if (!widget.isEligible) {
      // Pre-install or otherwise view-only media: no backup icon.
      return const SizedBox.shrink();
    }

    if (widget.isBacked) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF64B5F6),
          size: 16,
        ),
      );
    }

    if (widget.isActiveUpload) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.cloud_upload_rounded,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}

// ── Full Screen Viewer for local assets (swipe + pinch zoom) ────────────────
class _DeviceFullScreenPager extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  const _DeviceFullScreenPager({
    required this.assets,
    required this.initialIndex,
    required this.backedByLocalId,
    required this.cloudByLocalId,
  });

  final Map<String, bool> backedByLocalId;
  final Map<String, CloudPhoto> cloudByLocalId;

  @override
  State<_DeviceFullScreenPager> createState() => _DeviceFullScreenPagerState();
}

class _DeviceFullScreenPagerState extends State<_DeviceFullScreenPager> {
  late final PageController _controller;
  late int _currentIndex;
  final Map<String, Uint8List?> _fullBytesCache = <String, Uint8List?>{};
  final Set<String> _loadingIds = <String>{};
  bool _showControls = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.assets.length - 1);
    _controller = PageController(initialPage: _currentIndex);

    _loadForIndex(_currentIndex);
    _loadForIndex(_currentIndex + 1);
    _loadForIndex(_currentIndex - 1);
  }

  Future<void> _loadForIndex(int index) async {
    if (index < 0 || index >= widget.assets.length) return;
    final asset = widget.assets[index];
    if (_fullBytesCache.containsKey(asset.id) || _loadingIds.contains(asset.id)) {
      return;
    }

    _loadingIds.add(asset.id);
    try {
      final bytes = await asset.originBytes ??
          await asset.thumbnailDataWithSize(const ThumbnailSize(2048, 2048));
      if (mounted) {
        setState(() {
          _fullBytesCache[asset.id] = bytes != null ? Uint8List.fromList(bytes) : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _fullBytesCache[asset.id] = null;
        });
      }
    } finally {
      _loadingIds.remove(asset.id);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assets.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
        ),
      );
    }

    final currentAsset = widget.assets[_currentIndex];
    final currentId = currentAsset.id;
    final isBacked = widget.backedByLocalId[currentId] ?? false;
    final cloud = widget.cloudByLocalId[currentId];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _showControls = !_showControls);
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.assets.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                _loadForIndex(index);
                _loadForIndex(index + 1);
                _loadForIndex(index - 1);
              },
              itemBuilder: (context, index) {
                final asset = widget.assets[index];
                final bytes = _fullBytesCache[asset.id];
                final isLoading = _loadingIds.contains(asset.id) && bytes == null;

                return Center(
                  child: bytes != null
                      ? InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_rounded,
                              color: Colors.white38,
                              size: 64,
                            ),
                          ),
                        )
                      : isLoading
                          ? const CircularProgressIndicator(color: AppTheme.primary)
                          : const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
                );
              },
            ),
            if (_showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.black87,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: _deleting ? null : _shareCurrent,
                          child: const _BottomAction(
                            icon: Icons.share_rounded,
                            label: 'Share',
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                currentAsset.title ?? 'Photo',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (isBacked && cloud != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.email_rounded,
                                        size: 14, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        cloud.accountEmail,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 14,
                                      color: Color(0xFF64B5F6),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: _deleting ? null : () => _onDeletePressed(currentId, isBacked, cloud),
                          child: _BottomAction(
                            icon: Icons.delete_rounded,
                            label: _deleting ? 'Deleting...' : 'Delete',
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareCurrent() async {
    final asset = widget.assets[_currentIndex];
    final file = await asset.file;
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _onDeletePressed(String localId, bool isBacked, CloudPhoto? cloud) async {
    if (_deleting) return;
    String? choice;

    if (isBacked && cloud != null) {
      choice = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete photo'),
            content: const Text('This photo is backed up to Drive. What do you want to delete?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop<String>('cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop<String>('gallery'),
                child: const Text('Delete (Cloudpix only)'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop<String>('both'),
                child: const Text('Delete from Drive'),
              ),
            ],
          );
        },
      );
      if (choice == null || choice == 'cancel') return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete photo'),
            content: const Text('Remove this photo from Cloudpix gallery? The original will stay in your phone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      choice = 'gallery';
    }

    setState(() => _deleting = true);
    try {
      if (choice == 'gallery' || choice == 'both') {
        final prefs = await SharedPreferences.getInstance();
        final existing = prefs.getStringList(_hiddenLocalIdsKey) ?? <String>[];
        if (!existing.contains(localId)) {
          existing.add(localId);
          await prefs.setStringList(_hiddenLocalIdsKey, existing);
        }
        await LocalDatabase.softDeleteByLocalId(localId);
      }

      if (choice == 'both' && cloud != null) {
        await GoogleDriveService.deleteFile(cloud.accountId, cloud.driveFileId);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _BottomAction({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }
}

// ── Drive-backed (cloud-only) tiles & full screen ──────────────────────────
class _DrivePhotoTile extends StatefulWidget {
  final CloudPhoto photo;
  final List<CloudPhoto> allPhotos;
  final int initialIndex;

  const _DrivePhotoTile({
    required this.photo,
    required this.allPhotos,
    required this.initialIndex,
  });

  @override
  State<_DrivePhotoTile> createState() => _DrivePhotoTileState();
}

class _DrivePhotoTileState extends State<_DrivePhotoTile> {
  Uint8List? _thumbBytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    try {
      final fileId = widget.photo.thumbFileId ?? widget.photo.driveFileId;
      final bytes = await GoogleDriveService.downloadFileBytes(
        widget.photo.accountId,
        fileId,
      );
      if (!mounted) return;
      setState(() {
        _thumbBytes = bytes != null ? Uint8List.fromList(bytes) : null;
        _loading = false;
        _error = bytes == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt;

    Widget child;
    if (_loading) {
      child = Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary.withValues(alpha: 0.4),
          ),
        ),
      );
    } else if (_error || _thumbBytes == null) {
      child = const Icon(
        Icons.broken_image_rounded,
        color: Colors.white54,
        size: 28,
      );
    } else {
      child = Image.memory(
        _thumbBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _DriveFullScreenPager(
              photos: widget.allPhotos,
              initialIndex: widget.initialIndex,
            ),
          ),
        );
      },
      child: Container(
        color: bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: child),
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.cloud_done_rounded,
                  color: Color(0xFF64B5F6),
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriveFullScreenPager extends StatefulWidget {
  final List<CloudPhoto> photos;
  final int initialIndex;

  const _DriveFullScreenPager({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_DriveFullScreenPager> createState() => _DriveFullScreenPagerState();
}

class _DriveFullScreenPagerState extends State<_DriveFullScreenPager> {
  late final PageController _controller;
  late int _currentIndex;
  final Map<String, Uint8List?> _fullBytesCache = <String, Uint8List?>{};
  final Set<String> _loadingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.photos.length - 1);
    _controller = PageController(initialPage: _currentIndex);
    _loadForIndex(_currentIndex);
    _loadForIndex(_currentIndex + 1);
    _loadForIndex(_currentIndex - 1);
  }

  Future<void> _loadForIndex(int index) async {
    if (index < 0 || index >= widget.photos.length) return;
    final photo = widget.photos[index];
    if (_fullBytesCache.containsKey(photo.id) || _loadingIds.contains(photo.id)) return;
    _loadingIds.add(photo.id);
    try {
      final bytes = await GoogleDriveService.downloadFileBytes(
        photo.accountId,
        photo.driveFileId,
      );
      if (!mounted) return;
      setState(() {
        _fullBytesCache[photo.id] = bytes != null ? Uint8List.fromList(bytes) : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fullBytesCache[photo.id] = null;
      });
    } finally {
      _loadingIds.remove(photo.id);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
        ),
      );
    }

    final photo = widget.photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              photo.name,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              DateFormat('MMM d, yyyy · h:mm a').format(photo.takenAt),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _loadForIndex(index);
          _loadForIndex(index + 1);
          _loadForIndex(index - 1);
        },
        itemBuilder: (context, index) {
          final p = widget.photos[index];
          final bytes = _fullBytesCache[p.id];
          final isLoading = _loadingIds.contains(p.id) && bytes == null;

          return Center(
            child: bytes != null
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white38,
                        size: 64,
                      ),
                    ),
                  )
                : isLoading
                    ? const CircularProgressIndicator(color: AppTheme.primary)
                    : const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
          );
        },
      ),
    );
  }
}

// Custom painter for 4-color border (square logo)
class GoogleBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final colors = [
      Color(0xFF4285F4), // Blue
      Color(0xFFDB4437), // Red
      Color(0xFFF4B400), // Yellow
      Color(0xFF0F9D58), // Green
    ];
    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(rect, i * 1.5708, 1.5708, false, paint); // 90deg = 1.5708 rad
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom painter for 4-color border (circle profile)
class GoogleCircleBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final colors = [
      Color(0xFF0F9D58), // Green
      Color(0xFFDB4437), // Red
      Color(0xFFF4B400), // Yellow
      Color(0xFF4285F4), // Blue
    ];
    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(rect, i * 1.5708, 1.5708, false, paint); // 90deg = 1.5708 rad
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
