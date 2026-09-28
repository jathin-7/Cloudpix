import 'dart:io';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../utils/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GoogleDriveService
// Manages multiple Google accounts.
// Each account gives 15GB free storage.
// ALL photos from ALL accounts appear in ONE unified gallery.
// ─────────────────────────────────────────────────────────────────────────────

class GoogleDriveService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _accountsKey = 'cloudpix_google_accounts';
  static const _tokensPrefix = 'cloudpix_token_';

  static const MethodChannel _nativeBackupChannel = MethodChannel('cloudpix/native_backup');

  // Google Sign In scopes needed
  static final _googleSignIn = GoogleSignIn(
    serverClientId: AppTheme.googleWebClientId,
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
      'email',
      'profile',
    ],
  );

  // ── Load all saved accounts ───────────────────────────────────────────────
  static Future<List<GoogleDriveAccount>> loadAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => GoogleDriveAccount.fromJson(e)).toList();
  }

  // ── Save all accounts ─────────────────────────────────────────────────────
  static Future<void> _saveAccounts(List<GoogleDriveAccount> accounts) async {
    await _storage.write(key: _accountsKey, value: jsonEncode(accounts.map((e) => e.toJson()).toList()));
    await _syncAccountsToNative();
  }

  static Future<void> setAccountActive(String accountId, bool isActive) async {
    final accounts = await loadAccounts();
    final idx = accounts.indexWhere((a) => a.id == accountId);
    if (idx == -1) return;
    accounts[idx] = accounts[idx].copyWith(isActive: isActive);
    await _saveAccounts(accounts);
  }

  // ── Sign in with Google and add account ───────────────────────────────────
  static Future<GoogleDriveAccount?> addAccount() async {
    try {
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final accounts = await loadAccounts();
      if (accounts.any((a) => a.email == googleUser.email)) {
        throw Exception('${googleUser.email} is already added');
      }

      final auth = await googleUser.authentication;
      final accessToken = auth.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Unable to obtain access token');
      }

      await _storage.write(
        key: '$_tokensPrefix${googleUser.id}',
        value: jsonEncode({
          'accessToken': accessToken,
          'idToken': auth.idToken,
        }),
      );

      final client = await _getAuthClient(googleUser.id);
      if (client == null) throw Exception('Auth failed');
      final driveApi = drive.DriveApi(client);

      final folderId = await _getOrCreateRootFolder(driveApi);
      await _ensureRequiredSubFolders(driveApi, folderId);

      final quotaInfo = await _getDriveQuota(client);

      final account = GoogleDriveAccount(
        id: googleUser.id,
        email: googleUser.email,
        displayName: googleUser.displayName ?? googleUser.email,
        photoUrl: googleUser.photoUrl,
        usedBytes: quotaInfo['used'] ?? 0,
        totalBytes: quotaInfo['total'] ?? 16106127360,
        isActive: true,
        order: accounts.length,
        rootFolderId: folderId,
      );

      accounts.add(account);
      await _saveAccounts(accounts);
      client.close();

      return account;
    } catch (e) {
      rethrow;
    }
  }

  // ── Remove account ────────────────────────────────────────────────────────
  static Future<void> removeAccount(String accountId) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.id == accountId);
    await _saveAccounts(accounts);
    await _storage.delete(key: '$_tokensPrefix$accountId');
  }

  /// Sync current Drive accounts and access tokens into the native Android
  /// backup database so that the background worker can upload even when the
  /// Flutter side is not running. No-op on non-Android platforms.
  static Future<void> _syncAccountsToNative() async {
    if (!Platform.isAndroid) return;

    try {
      final accounts = await loadAccounts();
      if (accounts.isEmpty) {
        await _nativeBackupChannel.invokeMethod('upsertAccounts', {
          'accounts': <Map<String, dynamic>>[],
        });
        return;
      }

      final payload = <Map<String, dynamic>>[];
      for (final account in accounts) {
        final tokenRaw = await _storage.read(key: '$_tokensPrefix${account.id}');
        if (tokenRaw == null || tokenRaw.isEmpty) continue;

        String? accessToken;
        try {
          final data = jsonDecode(tokenRaw) as Map<String, dynamic>;
          accessToken = data['accessToken'] as String?;
        } catch (_) {
          accessToken = null;
        }

        if (accessToken == null || accessToken.isEmpty) continue;

        payload.add({
          'id': account.id,
          'email': account.email,
          'accessToken': accessToken,
          'rootFolderId': account.rootFolderId,
          'usedBytes': account.usedBytes,
          'totalBytes': account.totalBytes,
          'isActive': account.isActive,
          'order': account.order,
        });
      }

      await _nativeBackupChannel.invokeMethod('upsertAccounts', {
        'accounts': payload,
      });
    } catch (_) {
      // Native backup is best-effort; failures here should not break the app.
    }
  }

  /// Force a one-time sync of Drive accounts/tokens into native backup.
  /// Useful on app startup so existing users are migrated without needing
  /// to add/remove accounts again.
  static Future<void> syncAccountsToNativeNow() async {
    await _syncAccountsToNative();
  }

  // ── Get authenticated HTTP client for an account ──────────────────────────
  static Future<http.Client?> _getAuthClient(String accountId) async {
    try {
      GoogleSignInAccount? currentUser = _googleSignIn.currentUser;
      currentUser ??= await _googleSignIn.signInSilently();
      if (currentUser != null && currentUser.id == accountId) {
        final auth = await currentUser.authentication;
        final accessToken = auth.accessToken;
        if (accessToken != null && accessToken.isNotEmpty) {
          await _storage.write(
            key: '$_tokensPrefix$accountId',
            value: jsonEncode({
              'accessToken': accessToken,
              'idToken': auth.idToken,
            }),
          );
          return GoogleAuthClient(accessToken);
        }
      }

      final tokenRaw = await _storage.read(key: '$_tokensPrefix$accountId');
      if (tokenRaw == null) return null;
      final tokenData = jsonDecode(tokenRaw);
      final token = tokenData['accessToken'] as String?;
      if (token == null || token.isEmpty) return null;

      return GoogleAuthClient(token);
    } catch (_) {
      return null;
    }
  }

  // ── Get Drive API for an account ─────────────────────────────────────────
  static Future<drive.DriveApi?> getDriveApi(String accountId) async {
    final client = await _getAuthClient(accountId);
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  // ── Get Drive storage quota ───────────────────────────────────────────────
  static Future<Map<String, int>> _getDriveQuota(http.Client client) async {
    try {
      final driveApi = drive.DriveApi(client);
      final about = await driveApi.about.get($fields: 'storageQuota');
      return {
        'used': int.tryParse(about.storageQuota?.usage ?? '0') ?? 0,
        'total': int.tryParse(about.storageQuota?.limit ?? '16106127360') ?? 16106127360,
      };
    } catch (_) {
      return {'used': 0, 'total': 16106127360};
    }
  }

  // ── Upload file to Google Drive ───────────────────────────────────────────
  static Future<UploadResult> uploadFile({
    required File file,
    required GoogleDriveAccount account,
    required String fileName,
    required String mimeType,
    required String subFolder,
    void Function(int percent)? onProgress,
  }) async {
    return _uploadFileInternal(
      file: file,
      account: account,
      fileName: fileName,
      mimeType: mimeType,
      subFolder: subFolder,
      onProgress: onProgress,
      allowAuthRetry: true,
    );
  }

  static Future<UploadResult> _uploadFileInternal({
    required File file,
    required GoogleDriveAccount account,
    required String fileName,
    required String mimeType,
    required String subFolder,
    void Function(int percent)? onProgress,
    required bool allowAuthRetry,
  }) async {
    try {
      final client = await _getAuthClient(account.id);
      if (client == null) throw Exception('Not authenticated');

      final driveApi = drive.DriveApi(client);
      final fileLength = await file.length();

      final fixedAccount = await _ensureAccountFolderStructure(account, driveApi);

      final parentId = await _getOrCreateSubFolder(
        driveApi: driveApi,
        rootFolderId: fixedAccount.rootFolderId!,
        subFolder: subFolder,
      );

      // Upload
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [parentId];

      onProgress?.call(10);

      final media = drive.Media(
        file.openRead(),
        fileLength,
        contentType: mimeType,
      );

      final uploaded = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id,name,size',
      );

      onProgress?.call(100);
      client.close();

      // Update used bytes
      await _updateUsedBytes(fixedAccount.id, fileLength);

      return UploadResult(
        success: true,
        driveFileId: uploaded.id!,
        sizeBytes: fileLength,
      );
    } catch (e) {
      if (allowAuthRetry && _looksLikeAuthError(e)) {
        final refreshed = await _refreshTokenFromGoogleSession(account.id);
        if (refreshed) {
          return _uploadFileInternal(
            file: file,
            account: account,
            fileName: fileName,
            mimeType: mimeType,
            subFolder: subFolder,
            onProgress: onProgress,
            allowAuthRetry: false,
          );
        }
      }
      return UploadResult(success: false, error: e.toString());
    }
  }

  static bool _looksLikeAuthError(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauth') ||
        lower.contains('invalid_grant') ||
        lower.contains('access_denied') ||
        lower.contains('token');
  }

  static Future<bool> refreshSessionTokenForAccount(String accountId) async {
    try {
      final accounts = await loadAccounts();
      final target = accounts.where((a) => a.id == accountId).firstOrNull;
      if (target == null) return false;

      final currentUser = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (currentUser == null) return false;

      final sameId = currentUser.id == accountId;
      final sameEmail = currentUser.email.toLowerCase() == target.email.toLowerCase();
      if (!sameId && !sameEmail) {
        return false;
      }

      final auth = await currentUser.authentication;
      final accessToken = auth.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        return false;
      }

      await _storage.write(
        key: '$_tokensPrefix$accountId',
        value: jsonEncode({
          'accessToken': accessToken,
          'idToken': auth.idToken,
        }),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> validateAccountAuth(String accountId) async {
    try {
      final client = await _getAuthClient(accountId);
      if (client == null) return false;
      final api = drive.DriveApi(client);
      await api.about.get($fields: 'user(emailAddress)');
      client.close();
      return true;
    } catch (e) {
      if (!_looksLikeAuthError(e)) {
        return false;
      }

      final refreshed = await refreshSessionTokenForAccount(accountId);
      if (!refreshed) return false;

      try {
        final client = await _getAuthClient(accountId);
        if (client == null) return false;
        final api = drive.DriveApi(client);
        await api.about.get($fields: 'user(emailAddress)');
        client.close();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static Future<void> reauthenticateAccount(String accountId) async {
    final accounts = await loadAccounts();
    final target = accounts.where((a) => a.id == accountId).firstOrNull;
    if (target == null) {
      throw Exception('Account not found.');
    }

    await _googleSignIn.signOut();
    final user = await _googleSignIn.signIn();
    if (user == null) {
      throw Exception('Sign-in cancelled.');
    }

    if (user.email.toLowerCase() != target.email.toLowerCase()) {
      throw Exception('Please select ${target.email} to reconnect this account.');
    }

    final auth = await user.authentication;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Unable to refresh access token.');
    }

    await _storage.write(
      key: '$_tokensPrefix$accountId',
      value: jsonEncode({
        'accessToken': token,
        'idToken': auth.idToken,
      }),
    );
  }

  static Future<bool> _refreshTokenFromGoogleSession(String accountId) async {
    try {
      final currentUser = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (currentUser == null || currentUser.id != accountId) {
        return false;
      }

      final auth = await currentUser.authentication;
      final accessToken = auth.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        return false;
      }

      await _storage.write(
        key: '$_tokensPrefix$accountId',
        value: jsonEncode({
          'accessToken': accessToken,
          'idToken': auth.idToken,
        }),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Get direct download URL for a file ───────────────────────────────────
  static Future<String?> getDownloadUrl(String accountId, String fileId) async {
    try {
      final client = await _getAuthClient(accountId);
      if (client == null) return null;

      final driveApi = drive.DriveApi(client);
      final file = await driveApi.files.get(
        fileId, $fields: 'webContentLink,thumbnailLink',
      ) as drive.File;

      client.close();
      return file.webContentLink ?? file.thumbnailLink;
    } catch (_) {
      return null;
    }
  }

  // ── Get thumbnail URL ─────────────────────────────────────────────────────
  static Future<String?> getThumbnailUrl(String accountId, String fileId) async {
    try {
      final client = await _getAuthClient(accountId);
      if (client == null) return null;

      final driveApi = drive.DriveApi(client);
      final file = await driveApi.files.get(
        fileId, $fields: 'thumbnailLink,webContentLink',
      ) as drive.File;

      client.close();
      return file.thumbnailLink ?? file.webContentLink;
    } catch (_) {
      return null;
    }
  }

  // ── Delete a file ─────────────────────────────────────────────────────────
  static Future<void> deleteFile(String accountId, String fileId) async {
    try {
      final client = await _getAuthClient(accountId);
      if (client == null) return;
      final driveApi = drive.DriveApi(client);
      await driveApi.files.delete(fileId);
      client.close();
    } catch (_) {}
  }

  // ── Get upload account using fill-first strategy ───────────────────────────
  static Future<GoogleDriveAccount?> getUploadAccount({
    int requiredBytes = 5 * 1024 * 1024,
    Set<String>? excludedAccountIds,
  }) async {
    final accounts = await loadAccounts();
    final excluded = excludedAccountIds ?? <String>{};

    final ordered = [...accounts]..sort((a, b) => a.order.compareTo(b.order));
    for (final account in ordered) {
      if (excluded.contains(account.id)) {
        continue;
      }
      if (account.availableBytes > requiredBytes) {
        return account;
      }
    }
    return null;
  }

  // ── Get combined stats ────────────────────────────────────────────────────
  static Future<CombinedStats> getCombinedStats() async {
    final accounts = await loadAccounts();
    return CombinedStats(
      totalBytes: accounts.fold(0, (s, a) => s + a.totalBytes),
      usedBytes: accounts.fold(0, (s, a) => s + a.usedBytes),
      accountCount: accounts.length,
      accounts: accounts,
    );
  }

  // ── Refresh account quota from Drive ─────────────────────────────────────
  static Future<void> refreshQuota(String accountId) async {
    try {
      final client = await _getAuthClient(accountId);
      if (client == null) return;
      final quota = await _getDriveQuota(client);
      client.close();

      final accounts = await loadAccounts();
      final idx = accounts.indexWhere((a) => a.id == accountId);
      if (idx != -1) {
        accounts[idx] = accounts[idx].copyWith(usedBytes: quota['used']);
        await _saveAccounts(accounts);
      }
    } catch (_) {}
  }

  // ── Update used bytes locally ─────────────────────────────────────────────
  static Future<void> _updateUsedBytes(String accountId, int deltaBytes) async {
    final accounts = await loadAccounts();
    final idx = accounts.indexWhere((a) => a.id == accountId);
    if (idx != -1) {
      accounts[idx] = accounts[idx].copyWith(usedBytes: accounts[idx].usedBytes + deltaBytes);
      await _saveAccounts(accounts);
    }
  }

  static Future<GoogleDriveAccount> _ensureAccountFolderStructure(
    GoogleDriveAccount account,
    drive.DriveApi driveApi,
  ) async {
    String? rootId = account.rootFolderId;

    if (rootId != null && rootId.isNotEmpty) {
      try {
        await driveApi.files.get(rootId, $fields: 'id');
      } catch (_) {
        rootId = null;
      }
    }

    if (rootId == null || rootId.isEmpty) {
      rootId = await _getOrCreateRootFolder(driveApi);
      await _updateAccountRootFolder(account.id, rootId);
    }

    await _ensureRequiredSubFolders(driveApi, rootId);
    return account.copyWith(rootFolderId: rootId);
  }

  static Future<String> _getOrCreateRootFolder(drive.DriveApi driveApi) async {
    final list = await driveApi.files.list(
      q: "name='${AppConstants.driveFolderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false",
      $fields: 'files(id,name)',
      pageSize: 1,
    );

    final existing = list.files?.firstOrNull?.id;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final folder = drive.File()
      ..name = AppConstants.driveFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await driveApi.files.create(folder, $fields: 'id');
    return created.id!;
  }

  static Future<void> _ensureRequiredSubFolders(drive.DriveApi driveApi, String rootFolderId) async {
    for (final sub in [
      AppConstants.drivePhotoFolder,
      AppConstants.driveVideoFolder,
      AppConstants.driveThumbFolder,
      AppConstants.driveSecureFolder,
    ]) {
      await _getOrCreateSubFolder(
        driveApi: driveApi,
        rootFolderId: rootFolderId,
        subFolder: sub,
      );
    }
  }

  static Future<String> _getOrCreateSubFolder({
    required drive.DriveApi driveApi,
    required String rootFolderId,
    required String subFolder,
  }) async {
    final list = await driveApi.files.list(
      q: "name='$subFolder' and '$rootFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false",
      $fields: 'files(id,name)',
      pageSize: 1,
    );

    final existing = list.files?.firstOrNull?.id;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final sub = drive.File()
      ..name = subFolder
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [rootFolderId];
    final created = await driveApi.files.create(sub, $fields: 'id');
    return created.id!;
  }

  static Future<void> _updateAccountRootFolder(String accountId, String rootFolderId) async {
    final accounts = await loadAccounts();
    final index = accounts.indexWhere((a) => a.id == accountId);
    if (index == -1) return;
    accounts[index] = accounts[index].copyWith(rootFolderId: rootFolderId);
    await _saveAccounts(accounts);
  }

  // ── Get auth headers for an account (for authenticated image loading) ─────
  static Future<Map<String, String>?> getAuthHeaders(String accountId) async {
    try {
      final tokenRaw = await _storage.read(key: '$_tokensPrefix$accountId');
      if (tokenRaw == null) return null;
      final tokenData = jsonDecode(tokenRaw);
      return {'Authorization': 'Bearer ${tokenData['accessToken']}'};
    } catch (_) {
      return null;
    }
  }

  // ── Download file bytes directly from Drive ───────────────────────────────
  static Future<List<int>?> downloadFileBytes(String accountId, String fileId) async {
    Future<List<int>?> attempt() async {
      final client = await _getAuthClient(accountId);
      if (client == null) return null;
      try {
        final driveApi = drive.DriveApi(client);
        final media = await driveApi.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;
        final bytes = <int>[];
        await for (final chunk in media.stream) {
          bytes.addAll(chunk);
        }
        return bytes;
      } finally {
        client.close();
      }
    }

    try {
      final first = await attempt();
      if (first != null) return first;

      final refreshed = await refreshSessionTokenForAccount(accountId);
      if (!refreshed) return null;
      return await attempt();
    } catch (e) {
      if (_looksLikeAuthError(e)) {
        final refreshed = await refreshSessionTokenForAccount(accountId);
        if (refreshed) {
          try {
            return await attempt();
          } catch (_) {
            return null;
          }
        }
      }
      return null;
    }
  }
}

// ── Custom HTTP client that adds Google auth token ────────────────────────────
class GoogleAuthClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class UploadResult {
  final bool success;
  final String? driveFileId;
  final int? sizeBytes;
  final String? error;
  const UploadResult({required this.success, this.driveFileId, this.sizeBytes, this.error});
}
