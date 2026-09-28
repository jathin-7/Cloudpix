import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import '../models/models.dart';
import '../utils/theme.dart';
import 'google_drive_service.dart';
import 'local_database.dart';

const _autoBackupKey = 'cloudpix_auto_backup';
const _backupStatusKey = 'cloudpix_backup_status';
const _retryStateKey = 'cloudpix_backup_retry_state_v1';
const _startCutoffMsKey = 'cloudpix_backup_start_cutoff_ms_v1';
const _mediaPermissionKey = 'cloudpix_media_permission_enabled_v1';
const _taskName = 'cloudpix_auto_backup_task';
const _periodicTaskUniqueName = 'cloudpix.auto_backup.periodic';
const _oneOffTaskUniqueName = 'cloudpix.auto_backup.immediate';
const _retryTaskUniqueName = 'cloudpix.auto_backup.retry';
const _nativeBackupChannel = MethodChannel('cloudpix/native_backup');

// Max items for a single foreground/manual sync run.
const int _maxItemsPerRun = 120;
// Max items for a single background (Workmanager) run.
// This keeps backup truly one-by-one when running in background.
const int _maxBackgroundItemsPerRun = 1;
const int _maxRetryAttempts = 10;

@pragma('vm:entry-point')
void autoBackupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (task == _taskName || task == Workmanager.iOSBackgroundTask) {
      await AutoBackupService.runBackup(isBackgroundRun: true);
    }

    return Future.value(true);
  });
}

class AutoBackupService {
  static bool _isBackupRunning = false;
  static bool _liveMonitoringStarted = false;
  static Timer? _liveChangeDebounce;

  static bool get _preferNativeBackgroundPipeline => Platform.isAndroid;

  static Future<void> _startNativeAutoBackup() async {
    try {
      await _nativeBackupChannel.invokeMethod('startAutoBackup', {
        'requireCharging': false,
      });
    } catch (_) {}
  }

  static Future<void> _stopNativeAutoBackup() async {
    try {
      await _nativeBackupChannel.invokeMethod('stopAutoBackup');
    } catch (_) {}
  }

  static Future<void> _enqueueNativeNow() async {
    try {
      await _nativeBackupChannel.invokeMethod('enqueueNow', {
        'requireCharging': false,
      });
    } catch (_) {}
  }

  static void _onGalleryChanged(MethodCall _) {
    if (!_liveMonitoringStarted) {
      return;
    }

    _liveChangeDebounce?.cancel();
    _liveChangeDebounce = Timer(const Duration(seconds: 2), () async {
      if (!await isEnabled()) {
        return;
      }

      // Fast path while app is active.
      if (_preferNativeBackgroundPipeline) {
        await _enqueueNativeNow();
      } else {
        await runBackup(isBackgroundRun: false);
      }
    });
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(autoBackupCallbackDispatcher);
  }

  static Future<bool> isMediaPermissionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mediaPermissionKey) ?? false;
  }

  static Future<void> setMediaPermissionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mediaPermissionKey, enabled);
  }

  static Future<bool> requestMediaPermission() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final status = await PhotoManager.requestPermissionExtend();
      final granted = status.isAuth;
      await prefs.setBool(_mediaPermissionKey, granted);
      return granted;
    } catch (_) {
      await prefs.setBool(_mediaPermissionKey, false);
      return false;
    }
  }

  static Future<void> startLiveMonitoring() async {
    if (_preferNativeBackgroundPipeline) {
      // Android uses native ContentObserver + WorkManager for reliability when
      // app is backgrounded or killed. Avoid duplicate foreground scans.
      return;
    }

    if (_liveMonitoringStarted) {
      return;
    }

    try {
      PhotoManager.addChangeCallback(_onGalleryChanged);
      await PhotoManager.startChangeNotify();
      _liveMonitoringStarted = true;
    } catch (_) {}
  }

  static Future<void> stopLiveMonitoring() async {
    if (!_liveMonitoringStarted) {
      return;
    }

    try {
      PhotoManager.removeChangeCallback(_onGalleryChanged);
      await PhotoManager.stopChangeNotify();
    } catch (_) {}

    _liveMonitoringStarted = false;
    _liveChangeDebounce?.cancel();
    _liveChangeDebounce = null;
  }

  static Future<void> ensureScheduledIfEnabled() async {
    if (await isEnabled()) {
      if (_preferNativeBackgroundPipeline) {
        await _startNativeAutoBackup();
      } else {
        await _schedulePeriodicTask();
        await _scheduleImmediateRun();
        await startLiveMonitoring();
      }
    }
  }

  static Future<void> enable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupKey, true);

    if (_preferNativeBackgroundPipeline) {
      await _startNativeAutoBackup();
      await _enqueueNativeNow();
      await _saveStatus(BackupStatusSnapshot(
        running: true,
        stage: 'uploading',
        message: 'Background backup is active. Sync queued.',
        backed: 0,
        failed: 0,
        skipped: 0,
        total: 0,
        updatedAt: DateTime.now(),
      ));
      return;
    }

    await _schedulePeriodicTask();
    await _scheduleImmediateRun();
    await startLiveMonitoring();
    unawaited(runBackup(isBackgroundRun: false));
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupKey, false);

    await Workmanager().cancelByUniqueName(_periodicTaskUniqueName);
    await Workmanager().cancelByUniqueName(_oneOffTaskUniqueName);
    await Workmanager().cancelByUniqueName(_retryTaskUniqueName);
    await _stopNativeAutoBackup();
    await stopLiveMonitoring();

    await _saveStatus(BackupStatusSnapshot(
      running: false,
      stage: 'idle',
      message: 'Auto backup is OFF.',
      backed: 0,
      failed: 0,
      skipped: 0,
      total: 0,
      updatedAt: DateTime.now(),
    ));
  }

  static Future<void> triggerNow() async {
    if (_preferNativeBackgroundPipeline) {
      await _enqueueNativeNow();
      await _saveStatus(BackupStatusSnapshot(
        running: true,
        stage: 'uploading',
        message: 'Background sync queued.',
        backed: 0,
        failed: 0,
        skipped: 0,
        total: 0,
        updatedAt: DateTime.now(),
      ));
      return;
    }

    unawaited(runBackup(isBackgroundRun: false));
    await _scheduleImmediateRun();
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupKey) ?? true;
  }

  static Future<void> _scheduleImmediateRun() async {
    await Workmanager().registerOneOffTask(
      _oneOffTaskUniqueName,
      _taskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      initialDelay: Duration.zero,
    );
  }

  static Future<void> _scheduleFollowUpRun(Duration delay) async {
    await Workmanager().registerOneOffTask(
      _retryTaskUniqueName,
      _taskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      initialDelay: delay,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  static Future<void> _schedulePeriodicTask() async {
    await Workmanager().registerPeriodicTask(
      _periodicTaskUniqueName,
      _taskName,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      frequency: const Duration(hours: 1),
      initialDelay: const Duration(minutes: 2),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresCharging: false,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 3),
    );
  }

  static Future<void> _saveStatus(BackupStatusSnapshot status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backupStatusKey, jsonEncode(status.toJson()));
  }

  static Future<BackupStatusSnapshot> getLastStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backupStatusKey);
    if (raw == null || raw.isEmpty) {
      return BackupStatusSnapshot.idle();
    }

    try {
      return BackupStatusSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return BackupStatusSnapshot.idle();
    }
  }

  static Future<Map<String, RetryItemState>> _loadRetryState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_retryStateKey);
    if (raw == null || raw.isEmpty) return <String, RetryItemState>{};

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final result = <String, RetryItemState>{};
      map.forEach((key, value) {
        final item = RetryItemState.fromJson(value as Map<String, dynamic>);
        if (item.nextAttemptAtMs >= nowMs - const Duration(days: 7).inMilliseconds) {
          result[key] = item;
        }
      });
      return result;
    } catch (_) {
      return <String, RetryItemState>{};
    }
  }

  static Duration _retryDelayForAttempt(int attempts) {
    const schedule = <Duration>[
      Duration(seconds: 10),
      Duration(minutes: 1),
      Duration(minutes: 5),
      Duration(minutes: 30),
      Duration(hours: 2),
    ];

    if (attempts <= 0) return schedule.first;
    if (attempts <= schedule.length) return schedule[attempts - 1];
    return schedule.last;
  }

  static Future<void> _saveRetryState(Map<String, RetryItemState> state) async {
    final prefs = await SharedPreferences.getInstance();
    final data = state.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_retryStateKey, jsonEncode(data));
  }

  static Future<int> _getOrCreateStartCutoffMs() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getInt(_startCutoffMsKey);
    if (existing != null && existing > 0) {
      return existing;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_startCutoffMsKey, nowMs);
    return nowMs;
  }

  /// Exposes the backup start cutoff timestamp so UI can distinguish
  /// between "old, view-only" media and items that are eligible for backup.
  static Future<int> getStartCutoffMs() => _getOrCreateStartCutoffMs();

  static int _assetTimeMs(AssetEntity asset) {
    final created = asset.createDateTime.millisecondsSinceEpoch;
    final modified = asset.modifiedDateTime.millisecondsSinceEpoch;
    if (created > 0) return created;
    if (modified > 0) return modified;
    return DateTime.now().millisecondsSinceEpoch;
  }

  static Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    if (result == ConnectivityResult.none) {
      return false;
    }

    // Connectivity can report online even when DNS resolution fails.
    try {
      final lookup = await InternetAddress.lookup('www.googleapis.com').timeout(
        const Duration(seconds: 4),
      );
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool _isStorageQuotaError(String? error) {
    final lower = (error ?? '').toLowerCase();
    return lower.contains('quota') ||
        lower.contains('insufficient') ||
        lower.contains('storage') ||
        lower.contains('space');
  }

  static bool _isAuthError(String? error) {
    final lower = (error ?? '').toLowerCase();
    return lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('invalid authentication') ||
        lower.contains('invalid_grant') ||
        lower.contains('access_denied') ||
        lower.contains('token') ||
        lower.contains('oauth');
  }

        static bool _isTransientNetworkError(String? error) {
          final lower = (error ?? '').toLowerCase();
          return lower.contains('socketexception') ||
          lower.contains('failed host lookup') ||
          lower.contains('no address associated') ||
          lower.contains('network is unreachable') ||
          lower.contains('connection reset') ||
          lower.contains('connection closed') ||
          lower.contains('timed out') ||
          lower.contains('dns');
        }

  static Future<BackupSummary> runBackup({
    void Function(BackupProgress)? onProgress,
    bool isBackgroundRun = false,
  }) async {
    if (_isBackupRunning) {
      return const BackupSummary(backed: 0, failed: 0, skipped: 0);
    }

    if (isBackgroundRun && !await isEnabled()) {
      return const BackupSummary(backed: 0, failed: 0, skipped: 0);
    }

    _isBackupRunning = true;

    await _saveStatus(BackupStatusSnapshot(
      running: true,
      stage: 'scanning',
      message: 'Scanning gallery for new media...',
      backed: 0,
      failed: 0,
      skipped: 0,
      total: 0,
      updatedAt: DateTime.now(),
    ));

    try {
      // Respect user toggle for gallery access first.
      final mediaPermissionEnabled = await isMediaPermissionEnabled();
      if (!mediaPermissionEnabled) {
        await _saveStatus(BackupStatusSnapshot(
          running: false,
          stage: 'blocked',
          message: 'Photos/Videos access is OFF. Enable it in Settings to start backup.',
          backed: 0,
          failed: 0,
          skipped: 0,
          total: 0,
          updatedAt: DateTime.now(),
        ));
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

      // Then check actual OS media permission. If the platform throws once
      // (some OEMs do this when waking the app), do not show a scary error
      // as long as the user toggle is ON. Instead, keep previous status and
      // quietly retry later.
      bool hasGalleryPermission = false;
      try {
        final permission = await PhotoManager.requestPermissionExtend();
        hasGalleryPermission = permission.isAuth;
      } on PlatformException {
        await _scheduleFollowUpRun(const Duration(minutes: 2));
        // Do not overwrite status with a blocked message here – the user has
        // explicitly turned gallery access ON. Just exit this run quietly.
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

      if (!hasGalleryPermission) {
        await _saveStatus(BackupStatusSnapshot(
          running: false,
          stage: 'blocked',
          message: 'Photos and videos permission not granted.',
          backed: 0,
          failed: 0,
          skipped: 0,
          total: 0,
          updatedAt: DateTime.now(),
        ));
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

       if (!await _hasInternet()) {
        await _scheduleFollowUpRun(const Duration(minutes: 2));
        await _saveStatus(BackupStatusSnapshot(
          running: false,
          stage: 'blocked',
          message: 'No internet connection. Will retry automatically.',
          backed: 0,
          failed: 0,
          skipped: 0,
          total: 0,
          updatedAt: DateTime.now(),
        ));
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

      final accounts = await GoogleDriveService.loadAccounts();
      if (accounts.isEmpty) {
        await _saveStatus(BackupStatusSnapshot(
          running: false,
          stage: 'blocked',
          message: 'No Google account connected for backup.',
          backed: 0,
          failed: 0,
          skipped: 0,
          total: 0,
          updatedAt: DateTime.now(),
        ));
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

      final hasAnyStorage = accounts.any((a) => a.availableBytes > 0);
      if (!hasAnyStorage) {
        await _saveStatus(BackupStatusSnapshot(
          running: false,
          stage: 'blocked',
          message: 'All connected Google accounts are full. Add or free storage to continue backup.',
          backed: 0,
          failed: 0,
          skipped: 0,
          total: 0,
          updatedAt: DateTime.now(),
        ));
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

      final retryState = await _loadRetryState();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final startCutoffMs = await _getOrCreateStartCutoffMs();
      bool authBlocked = false;
      String? authBlockedEmail;

      // Use the main combined gallery path (images + videos), just like the
      // Photos screen does, to keep scanning fast and predictable.
      final albums = await PhotoManager.getAssetPathList(type: RequestType.common);
      final unique = <String, AssetEntity>{};

      if (albums.isNotEmpty) {
        final main = albums.first;
        final total = await main.assetCountAsync;
        const pageSize = 300;
        int start = 0;
        while (start < total) {
          final end = (start + pageSize).clamp(0, total);
          final page = await main.getAssetListRange(start: start, end: end);
          for (final asset in page) {
            if (asset.type == AssetType.image || asset.type == AssetType.video) {
              unique[asset.id] = asset;
            }
          }
          start = end;
        }
      }


      // --- New logic: Prioritize all failed items for retry, then fill with new items up to _maxItemsPerRun ---
      final failedAssets = <AssetEntity>[];
      final newAssets = <AssetEntity>[];
      // Load all backed local IDs once to avoid repeated per-item DB queries.
      final backedLocalIds = await LocalDatabase.getAllBackedLocalIds();
      for (final asset in unique.values) {
        final timeMs = _assetTimeMs(asset);
        if (timeMs < startCutoffMs) {
          continue;
        }

        if (backedLocalIds.contains(asset.id)) {
          retryState.remove(asset.id);
          continue;
        }

        final state = retryState[asset.id];
        if (state != null) {
          // Only retry if eligible (time has come)
          if (state.nextAttemptAtMs <= nowMs) {
            failedAssets.add(asset);
          }
          continue;
        }

        newAssets.add(asset);
      }

      // Sort by most recent first
      failedAssets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      newAssets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      // Decide how many items to handle in this run.
      // Background runs (Workmanager) should be strictly one-by-one to keep
      // backup light-weight and staggered. Foreground/manual runs can process
      // more items per sync for faster catch-up.
      final maxItemsForThisRun = isBackgroundRun ? _maxBackgroundItemsPerRun : _maxItemsPerRun;

      // Always prefer failed items first, then fill with new items up to
      // maxItemsForThisRun.
      final toBackup = <AssetEntity>[];
      for (final asset in failedAssets) {
        if (toBackup.length >= maxItemsForThisRun) break;
        toBackup.add(asset);
      }

      if (toBackup.length < maxItemsForThisRun) {
        final remaining = maxItemsForThisRun - toBackup.length;
        toBackup.addAll(newAssets.take(remaining));
      }

      if (toBackup.isEmpty) {
        await _saveRetryState(retryState);
        await _saveStatus(BackupStatusSnapshot(
          running: false,
          stage: 'idle',
          message: 'No new photos or videos found.',
          backed: 0,
          failed: 0,
          skipped: 0,
          total: 0,
          updatedAt: DateTime.now(),
        ));
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

      await _saveStatus(BackupStatusSnapshot(
        running: true,
        stage: 'uploading',
        message: 'Uploading ${toBackup.length} item(s) to Google Drive...',
        backed: 0,
        failed: 0,
        skipped: 0,
        total: toBackup.length,
        updatedAt: DateTime.now(),
      ));

      final tempDir = await getTemporaryDirectory();
      const uuid = Uuid();

      int backed = 0;
      int failed = 0;
      int skipped = 0;
      String? lastError;

      for (int i = 0; i < toBackup.length; i++) {
        final asset = toBackup[i];

        await _saveStatus(BackupStatusSnapshot(
          running: true,
          stage: 'uploading',
          message: 'Uploading item ${i + 1}/${toBackup.length}...',
          backed: backed,
          failed: failed,
          skipped: skipped,
          total: toBackup.length,
          updatedAt: DateTime.now(),
        ));

        try {
          final itemId = uuid.v4();
          final source = await _resolveSourceFile(
            asset: asset,
            tempDirPath: tempDir.path,
            itemId: itemId,
          );
          if (source == null) {
            skipped++;
            lastError = 'Skipped cloud-only or unavailable gallery media item.';
            continue;
          }

          final isVideo = asset.type == AssetType.video;
          final preparedUpload = await _prepareUploadFile(
            file: source.file,
            isVideo: isVideo,
            tempDirPath: tempDir.path,
            itemId: itemId,
            sourceMimeType: asset.mimeType,
          );

          final estimatedBytes = await preparedUpload.file.length();

          final fileName = '$itemId.${preparedUpload.extension}';
          final subFolder = isVideo ? AppConstants.driveVideoFolder : AppConstants.drivePhotoFolder;

          final triedAccounts = <String>{};
          UploadResult uploadResult = const UploadResult(success: false, error: 'No account available');
          GoogleDriveAccount? usedAccount;
          bool sawAuthExpiry = false;

          for (int attempt = 0; attempt < accounts.length; attempt++) {
            final account = await GoogleDriveService.getUploadAccount(
              requiredBytes: estimatedBytes,
              excludedAccountIds: triedAccounts,
            );

            if (account == null) {
              break;
            }

            usedAccount = account;
            triedAccounts.add(account.id);

            onProgress?.call(BackupProgress(
              current: i + 1,
              total: toBackup.length,
              percent: 0,
              fileName: asset.title ?? fileName,
              accountEmail: account.email,
            ));

            final uploadTimeout = isVideo
                ? const Duration(minutes: 3)
                : const Duration(seconds: 90);

            uploadResult = await GoogleDriveService.uploadFile(
              file: preparedUpload.file,
              account: account,
              fileName: fileName,
              mimeType: preparedUpload.mimeType,
              subFolder: subFolder,
              onProgress: (pct) {
                onProgress?.call(BackupProgress(
                  current: i + 1,
                  total: toBackup.length,
                  percent: pct,
                  fileName: asset.title ?? fileName,
                  accountEmail: account.email,
                ));
              },
            ).timeout(
              uploadTimeout,
              onTimeout: () => const UploadResult(success: false, error: 'Upload timed out'),
            );

            if (uploadResult.success && uploadResult.driveFileId != null) {
              break;
            }

            if (_isAuthError(uploadResult.error)) {
              final isValid = await GoogleDriveService.validateAccountAuth(account.id);
              if (!isValid) {
                sawAuthExpiry = true;
                authBlockedEmail = account.email;
                continue;
              }
            }

            if (!_isStorageQuotaError(uploadResult.error)) {
              break;
            }
          }

          if (sawAuthExpiry && (!uploadResult.success || uploadResult.driveFileId == null)) {
            // If all currently active accounts are invalid, block and stop this run.
            final remaining = await GoogleDriveService.getUploadAccount(
              requiredBytes: 1,
              excludedAccountIds: triedAccounts,
            );
            if (remaining == null) {
              authBlocked = true;
            }
          }

          if (authBlocked) {
            skipped += (toBackup.length - i);
            lastError = 'Google session expired for ${authBlockedEmail ?? 'an account'}. Reconnect in Storage to resume backup.';
            await _cleanupTempFiles(preparedUpload: preparedUpload, source: source);
            break;
          }

          if (!uploadResult.success || uploadResult.driveFileId == null || usedAccount == null) {
            failed++;
            final previous = retryState[asset.id] ?? const RetryItemState(attempts: 0, nextAttemptAtMs: 0);
            final attempts = previous.attempts + 1;
            final delay = _retryDelayForAttempt(attempts);
            retryState[asset.id] = RetryItemState(
              attempts: attempts,
              nextAttemptAtMs: DateTime.now().add(delay).millisecondsSinceEpoch,
            );

            if (_isTransientNetworkError(uploadResult.error)) {
              // Treat this as a soft, retryable failure: keep the item in the
              // retry queue but continue with remaining items so backup stays
              // as fast as possible instead of stopping the whole run.
              lastError = 'Some items could not reach Google Drive due to a temporary connection issue. They will retry automatically.';
            } else {
              lastError = uploadResult.error ?? 'Upload failed for ${asset.title ?? 'item'}';
            }

            await _cleanupTempFiles(preparedUpload: preparedUpload, source: source);
            continue;
          }

          String? thumbFileId;
          final thumbFile = await _createThumbnailFile(
            asset: asset,
            sourceFile: source.file,
            isVideo: isVideo,
            tempDirPath: tempDir.path,
            itemId: itemId,
          );

          if (thumbFile != null) {
            final thumbResult = await GoogleDriveService.uploadFile(
              file: thumbFile,
              account: usedAccount,
              fileName: 'thumb_$itemId.jpg',
              mimeType: 'image/jpeg',
              subFolder: AppConstants.driveThumbFolder,
            ).timeout(
              const Duration(seconds: 60),
              onTimeout: () => const UploadResult(success: false, error: 'Thumbnail upload timed out'),
            );
            thumbFileId = thumbResult.driveFileId;
            try {
              thumbFile.deleteSync();
            } catch (_) {}
          }

          final takenAt = asset.createDateTime.year > 1971 ? asset.createDateTime : asset.modifiedDateTime;

          final cloudPhoto = CloudPhoto(
            id: itemId,
            name: asset.title ?? fileName,
            size: uploadResult.sizeBytes ?? estimatedBytes,
            mimeType: preparedUpload.mimeType,
            driveFileId: uploadResult.driveFileId!,
            thumbFileId: thumbFileId,
            accountId: usedAccount.id,
            accountEmail: usedAccount.email,
            takenAt: takenAt,
            createdAt: DateTime.now(),
          );

          await LocalDatabase.insertPhoto(cloudPhoto, localId: asset.id);
          await LocalDatabase.markBacked(asset.id, usedAccount.id);

          retryState.remove(asset.id);
          backed++;
          await _cleanupTempFiles(preparedUpload: preparedUpload, source: source);
        } catch (e) {
          failed++;
          final previous = retryState[asset.id] ?? const RetryItemState(attempts: 0, nextAttemptAtMs: 0);
          final attempts = previous.attempts + 1;
          final delay = _retryDelayForAttempt(attempts);
          retryState[asset.id] = RetryItemState(
            attempts: attempts,
            nextAttemptAtMs: DateTime.now().add(delay).millisecondsSinceEpoch,
          );

          if (_isTransientNetworkError(e.toString())) {
            // Same as above: keep this item queued for retry but continue
            // processing the rest instead of marking the whole run blocked.
            lastError = 'Some items could not reach Google Drive due to a temporary connection issue. They will retry automatically.';
          } else {
            lastError = e.toString();
          }
        }
      }

      await _saveRetryState(retryState);

      if (!authBlocked && retryState.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final nextAt = retryState.values
            .map((e) => e.nextAttemptAtMs)
            .reduce((a, b) => a < b ? a : b);
        final delayMs = nextAt > now ? (nextAt - now) : const Duration(seconds: 10).inMilliseconds;
        final boundedDelayMs = delayMs.clamp(
          const Duration(seconds: 10).inMilliseconds,
          const Duration(hours: 2).inMilliseconds,
        );
        await _scheduleFollowUpRun(Duration(milliseconds: boundedDelayMs));
      }

      final finalMessage = backed > 0
          ? 'Backed up $backed of ${toBackup.length} item(s).'
          : (lastError ?? 'Backup completed with no uploaded items.');

      await _saveStatus(BackupStatusSnapshot(
        running: false,
        stage: authBlocked
            ? 'blocked'
            : ((failed > 0 || skipped > 0) ? 'partial' : 'success'),
        message: finalMessage,
        backed: backed,
        failed: failed,
        skipped: skipped,
        total: toBackup.length,
        updatedAt: DateTime.now(),
      ));

      return BackupSummary(backed: backed, failed: failed, skipped: skipped);
    } catch (e) {
      if (_isTransientNetworkError(e.toString())) {
        await _scheduleFollowUpRun(const Duration(minutes: 2));
        await _saveStatus(BackupStatusSnapshot(
          running: false,
          stage: 'blocked',
          message: 'Google Drive is temporarily unreachable. Will retry automatically.',
          backed: 0,
          failed: 0,
          skipped: 0,
          total: 0,
          updatedAt: DateTime.now(),
        ));
        return const BackupSummary(backed: 0, failed: 0, skipped: 0);
      }

      await _saveStatus(BackupStatusSnapshot(
        running: false,
        stage: 'error',
        message: 'Backup failed: $e',
        backed: 0,
        failed: 1,
        skipped: 0,
        total: 0,
        updatedAt: DateTime.now(),
      ));
      return const BackupSummary(backed: 0, failed: 1, skipped: 0);
    } finally {
      _isBackupRunning = false;
    }
  }

  static Future<_PreparedUploadFile> _prepareUploadFile({
    required File file,
    required bool isVideo,
    required String tempDirPath,
    required String itemId,
    required String? sourceMimeType,
  }) async {
    if (isVideo) {
      final guessedMime = _guessMimeFromPath(file.path, fallback: sourceMimeType ?? 'video/mp4');
      return _PreparedUploadFile(
        file: file,
        mimeType: guessedMime,
        extension: _extensionForMime(guessedMime, fallback: _extensionFromPath(file.path, fallback: 'mp4')),
        shouldDelete: false,
      );
    }

    final compressed = await FlutterImageCompress.compressAndGetFile(
      file.path,
      '$tempDirPath/cp_$itemId.jpg',
      quality: 85,
      minWidth: 1920,
      minHeight: 1080,
    );

    if (compressed == null) {
      final guessedMime = _guessMimeFromPath(file.path, fallback: sourceMimeType ?? 'image/jpeg');
      return _PreparedUploadFile(
        file: file,
        mimeType: guessedMime,
        extension: _extensionForMime(guessedMime, fallback: _extensionFromPath(file.path, fallback: 'jpg')),
        shouldDelete: false,
      );
    }

    return _PreparedUploadFile(
      file: File(compressed.path),
      mimeType: 'image/jpeg',
      extension: 'jpg',
      shouldDelete: true,
    );
  }

  static Future<_ResolvedSourceFile?> _resolveSourceFile({
    required AssetEntity asset,
    required String tempDirPath,
    required String itemId,
  }) async {
    final direct = await asset.file.timeout(
      const Duration(seconds: 18),
      onTimeout: () => null,
    );
    if (direct != null && await direct.exists()) {
      return _ResolvedSourceFile(file: direct, isTemporary: false);
    }

    final original = await asset.originFile.timeout(
      const Duration(seconds: 18),
      onTimeout: () => null,
    );
    if (original != null && await original.exists()) {
      return _ResolvedSourceFile(file: original, isTemporary: false);
    }

    final bytes = await asset.originBytes.timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
    if (bytes != null && bytes.isNotEmpty) {
      final fallbackExt = asset.type == AssetType.video ? 'mp4' : 'jpg';
      final extFromMime = _extensionForMime(asset.mimeType, fallback: fallbackExt);
      final tempFile = File('$tempDirPath/source_$itemId.$extFromMime');
      await tempFile.writeAsBytes(bytes, flush: true);
      return _ResolvedSourceFile(file: tempFile, isTemporary: true);
    }

    return null;
  }

  static Future<void> _cleanupTempFiles({
    required _PreparedUploadFile preparedUpload,
    required _ResolvedSourceFile source,
  }) async {
    if (preparedUpload.shouldDelete) {
      try {
        if (await preparedUpload.file.exists()) {
          await preparedUpload.file.delete();
        }
      } catch (_) {}
    }

    if (source.isTemporary) {
      try {
        if (await source.file.exists()) {
          await source.file.delete();
        }
      } catch (_) {}
    }
  }

  static String _guessMimeFromPath(String path, {required String fallback}) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    return fallback;
  }

  static String _extensionForMime(String? mimeType, {required String fallback}) {
    if (mimeType == null || mimeType.isEmpty) return fallback;
    final lower = mimeType.toLowerCase();
    if (lower.contains('jpeg') || lower.contains('jpg')) return 'jpg';
    if (lower.contains('png')) return 'png';
    if (lower.contains('heic')) return 'heic';
    if (lower.contains('webp')) return 'webp';
    if (lower.contains('quicktime')) return 'mov';
    if (lower.contains('x-matroska')) return 'mkv';
    if (lower.contains('x-msvideo')) return 'avi';
    if (lower.contains('mp4')) return 'mp4';
    return fallback;
  }

  static String _extensionFromPath(String path, {required String fallback}) {
    final index = path.lastIndexOf('.');
    if (index == -1 || index == path.length - 1) return fallback;
    return path.substring(index + 1).toLowerCase();
  }

  static Future<File?> _createThumbnailFile({
    required AssetEntity asset,
    required File sourceFile,
    required bool isVideo,
    required String tempDirPath,
    required String itemId,
  }) async {
    final thumbPath = '$tempDirPath/thumb_$itemId.jpg';

    if (!isVideo) {
      final thumb = await FlutterImageCompress.compressAndGetFile(
        sourceFile.path,
        thumbPath,
        quality: 40,
        minWidth: 500,
        minHeight: 500,
      );
      return thumb == null ? null : File(thumb.path);
    }

    final bytes = await asset.thumbnailDataWithSize(const ThumbnailSize(512, 512));
    if (bytes == null || bytes.isEmpty) return null;

    final f = File(thumbPath);
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}

class _ResolvedSourceFile {
  final File file;
  final bool isTemporary;

  const _ResolvedSourceFile({
    required this.file,
    required this.isTemporary,
  });
}

class _PreparedUploadFile {
  final File file;
  final String mimeType;
  final String extension;
  final bool shouldDelete;

  const _PreparedUploadFile({
    required this.file,
    required this.mimeType,
    required this.extension,
    required this.shouldDelete,
  });
}

class BackupSummary {
  final int backed;
  final int failed;
  final int skipped;

  const BackupSummary({required this.backed, required this.failed, required this.skipped});
}

class RetryItemState {
  final int attempts;
  final int nextAttemptAtMs;

  const RetryItemState({
    required this.attempts,
    required this.nextAttemptAtMs,
  });

  factory RetryItemState.fromJson(Map<String, dynamic> json) => RetryItemState(
        attempts: (json['attempts'] ?? 0) as int,
        nextAttemptAtMs: (json['nextAttemptAtMs'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {
        'attempts': attempts,
        'nextAttemptAtMs': nextAttemptAtMs,
      };
}

class BackupStatusSnapshot {
  final bool running;
  final String stage;
  final String message;
  final int backed;
  final int failed;
  final int skipped;
  final int total;
  final DateTime updatedAt;

  const BackupStatusSnapshot({
    required this.running,
    required this.stage,
    required this.message,
    required this.backed,
    required this.failed,
    required this.skipped,
    required this.total,
    required this.updatedAt,
  });

  factory BackupStatusSnapshot.idle() => BackupStatusSnapshot(
        running: false,
        stage: 'idle',
        message: 'Backup status will appear after first sync run.',
        backed: 0,
        failed: 0,
        skipped: 0,
        total: 0,
        updatedAt: DateTime.now(),
      );

  factory BackupStatusSnapshot.fromJson(Map<String, dynamic> j) => BackupStatusSnapshot(
        running: j['running'] == true,
        stage: (j['stage'] ?? 'idle').toString(),
        message: (j['message'] ?? '').toString(),
        backed: (j['backed'] ?? 0) as int,
        failed: (j['failed'] ?? 0) as int,
        skipped: (j['skipped'] ?? 0) as int,
        total: (j['total'] ?? 0) as int,
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '').toString()) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'running': running,
        'stage': stage,
        'message': message,
        'backed': backed,
        'failed': failed,
        'skipped': skipped,
        'total': total,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
