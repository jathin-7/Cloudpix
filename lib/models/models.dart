// ── Google Account ────────────────────────────────────────────────────────────
class GoogleDriveAccount {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int usedBytes;
  final int totalBytes;
  final bool isActive;
  final int order;
  final String? rootFolderId; // Cloudpix folder in this Drive

  const GoogleDriveAccount({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.usedBytes = 0,
    this.totalBytes = 16106127360, // 15GB
    this.isActive = true,
    this.order = 0,
    this.rootFolderId,
  });

  double get usedGB => usedBytes / (1024 * 1024 * 1024);
  double get totalGB => totalBytes / (1024 * 1024 * 1024);
  double get percentUsed => totalBytes > 0 ? usedBytes / totalBytes : 0;
  int get availableBytes => totalBytes - usedBytes;

  GoogleDriveAccount copyWith({
    int? usedBytes, bool? isActive, String? rootFolderId,
  }) => GoogleDriveAccount(
    id: id, email: email, displayName: displayName, photoUrl: photoUrl,
    usedBytes: usedBytes ?? this.usedBytes, totalBytes: totalBytes,
    isActive: isActive ?? this.isActive, order: order,
    rootFolderId: rootFolderId ?? this.rootFolderId,
  );

  factory GoogleDriveAccount.fromJson(Map<String, dynamic> j) => GoogleDriveAccount(
    id: j['id'], email: j['email'], displayName: j['displayName'],
    photoUrl: j['photoUrl'], usedBytes: j['usedBytes'] ?? 0,
    totalBytes: j['totalBytes'] ?? 16106127360,
    isActive: j['isActive'] ?? true, order: j['order'] ?? 0,
    rootFolderId: j['rootFolderId'],
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'email': email, 'displayName': displayName,
    'photoUrl': photoUrl, 'usedBytes': usedBytes, 'totalBytes': totalBytes,
    'isActive': isActive, 'order': order, 'rootFolderId': rootFolderId,
  };
}

// ── Combined stats ─────────────────────────────────────────────────────────────
class CombinedStats {
  final int totalBytes;
  final int usedBytes;
  final int accountCount;
  final List<GoogleDriveAccount> accounts;

  const CombinedStats({
    required this.totalBytes, required this.usedBytes,
    required this.accountCount, required this.accounts,
  });

  double get usedGB => usedBytes / (1024 * 1024 * 1024);
  double get totalGB => totalBytes / (1024 * 1024 * 1024);
  double get percentUsed => totalBytes > 0 ? (usedBytes / totalBytes * 100) : 0;
  int get availableBytes => totalBytes - usedBytes;
}

// ── Photo ─────────────────────────────────────────────────────────────────────
class CloudPhoto {
  final String id;
  final String name;
  final int size;
  final String? mimeType;
  final String driveFileId;   // Google Drive file ID
  final String? thumbFileId;  // Thumbnail Drive file ID
  final String accountId;     // Which Google account
  final String accountEmail;  // For display
  final DateTime takenAt;
  final bool isFavourite;
  final bool isDeleted;
  final bool isSecure;
  final String? personId;
  final String? albumId;
  final DateTime createdAt;

  const CloudPhoto({
    required this.id, required this.name, required this.size,
    this.mimeType, required this.driveFileId, this.thumbFileId,
    required this.accountId, required this.accountEmail,
    required this.takenAt, this.isFavourite = false,
    this.isDeleted = false, this.isSecure = false,
    this.personId, this.albumId, required this.createdAt,
  });

  bool get isVideo => mimeType?.startsWith('video/') ?? false;

  static DateTime _parseDate(dynamic raw, {DateTime? fallback}) {
    final text = (raw ?? '').toString();
    final parsed = DateTime.tryParse(text);
    return parsed ?? fallback ?? DateTime.now();
  }

  factory CloudPhoto.fromMap(Map<String, dynamic> m) => CloudPhoto(
    id: m['id'], name: m['name'], size: m['size'],
    mimeType: m['mime_type'], driveFileId: m['drive_file_id'],
    thumbFileId: m['thumb_file_id'], accountId: m['account_id'],
    accountEmail: m['account_email'] ?? '',
    takenAt: _parseDate(m['taken_at']),
    isFavourite: m['is_favourite'] == 1,
    isDeleted: m['is_deleted'] == 1,
    isSecure: m['is_secure'] == 1,
    personId: m['person_id'], albumId: m['album_id'],
    createdAt: _parseDate(m['created_at'], fallback: _parseDate(m['taken_at'])),
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'size': size, 'mime_type': mimeType,
    'drive_file_id': driveFileId, 'thumb_file_id': thumbFileId,
    'account_id': accountId, 'account_email': accountEmail,
    'taken_at': takenAt.toIso8601String(),
    'is_favourite': isFavourite ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
    'is_secure': isSecure ? 1 : 0,
    'person_id': personId, 'album_id': albumId,
    'created_at': createdAt.toIso8601String(),
  };

  CloudPhoto copyWith({bool? isFavourite, bool? isDeleted, bool? isSecure, String? personId, String? albumId}) =>
    CloudPhoto(
      id: id, name: name, size: size, mimeType: mimeType,
      driveFileId: driveFileId, thumbFileId: thumbFileId,
      accountId: accountId, accountEmail: accountEmail, takenAt: takenAt,
      isFavourite: isFavourite ?? this.isFavourite,
      isDeleted: isDeleted ?? this.isDeleted,
      isSecure: isSecure ?? this.isSecure,
      personId: personId ?? this.personId,
      albumId: albumId ?? this.albumId,
      createdAt: createdAt,
    );
}

// ── Photo group ────────────────────────────────────────────────────────────────
class PhotoGroup {
  final String dateLabel;
  final List<CloudPhoto> photos;
  const PhotoGroup({required this.dateLabel, required this.photos});
}

// ── Album ──────────────────────────────────────────────────────────────────────
class CloudAlbum {
  final String id;
  final String name;
  final String? description;
  final String? coverPhotoId;
  final DateTime createdAt;
  final int photoCount;

  const CloudAlbum({
    required this.id, required this.name, this.description,
    this.coverPhotoId, required this.createdAt, this.photoCount = 0,
  });

  factory CloudAlbum.fromMap(Map<String, dynamic> m) => CloudAlbum(
    id: m['id'], name: m['name'], description: m['description'],
    coverPhotoId: m['cover_photo_id'],
    createdAt: DateTime.parse(m['created_at']),
    photoCount: m['photo_count'] ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'description': description,
    'cover_photo_id': coverPhotoId,
    'created_at': createdAt.toIso8601String(),
    'photo_count': photoCount,
  };
}

// ── Person ─────────────────────────────────────────────────────────────────────
class CloudPerson {
  final String id;
  String name;
  final String? coverPhotoId;
  final int photoCount;
  final List<String> photoIds;

  CloudPerson({
    required this.id, required this.name, this.coverPhotoId,
    this.photoCount = 0, this.photoIds = const [],
  });

  factory CloudPerson.fromMap(Map<String, dynamic> m) => CloudPerson(
    id: m['id'], name: m['name'] ?? 'Unknown',
    coverPhotoId: m['cover_photo_id'], photoCount: m['photo_count'] ?? 0,
    photoIds: (m['photo_ids'] as String? ?? '').split(',').where((s) => s.isNotEmpty).toList(),
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'cover_photo_id': coverPhotoId,
    'photo_count': photoCount, 'photo_ids': photoIds.join(','),
  };
}

// ── Memory ─────────────────────────────────────────────────────────────────────
class Memory {
  final int year;
  final List<CloudPhoto> photos;
  const Memory({required this.year, required this.photos});
}

// ── Backup progress ────────────────────────────────────────────────────────────
class BackupProgress {
  final int current;
  final int total;
  final int percent;
  final String fileName;
  final String accountEmail;
  const BackupProgress({
    required this.current, required this.total, required this.percent,
    required this.fileName, required this.accountEmail,
  });
}
