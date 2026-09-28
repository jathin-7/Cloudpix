import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

class LocalDatabase {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'cloudpix4.db');
    return openDatabase(path, version: 2, onCreate: (db, _) async {
      await db.execute('''CREATE TABLE photos (
        id TEXT PRIMARY KEY, name TEXT, size INTEGER, mime_type TEXT,
        drive_file_id TEXT NOT NULL, thumb_file_id TEXT,
        account_id TEXT NOT NULL, account_email TEXT,
        taken_at TEXT NOT NULL, is_favourite INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0, is_secure INTEGER DEFAULT 0,
        person_id TEXT, album_id TEXT, created_at TEXT NOT NULL, local_id TEXT
      )''');
      await db.execute('''CREATE TABLE albums (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
        cover_photo_id TEXT, created_at TEXT NOT NULL, photo_count INTEGER DEFAULT 0
      )''');
      await db.execute('''CREATE TABLE people (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, cover_photo_id TEXT,
        photo_count INTEGER DEFAULT 0, photo_ids TEXT DEFAULT ''
      )''');
      await db.execute('''CREATE TABLE backup_log (
        local_id TEXT PRIMARY KEY, backed_up_at TEXT, account_id TEXT
      )''');
      await db.execute('CREATE INDEX idx_taken ON photos(taken_at DESC)');
      await db.execute('CREATE INDEX idx_secure ON photos(is_secure)');
      await db.execute('CREATE INDEX idx_deleted ON photos(is_deleted)');
      await db.execute('CREATE INDEX idx_person ON photos(person_id)');
      await db.execute('CREATE INDEX idx_album ON photos(album_id)');
    }, onOpen: (db) async {
      await _ensureSchema(db);
    }, onUpgrade: (db, oldVersion, newVersion) async {
      await _ensureSchema(db);
    });
  }

  static Future<void> _ensureSchema(Database db) async {
    // Legacy installs may have older tables; keep them compatible without data loss.
    await db.execute('''CREATE TABLE IF NOT EXISTS photos (
      id TEXT PRIMARY KEY, name TEXT, size INTEGER, mime_type TEXT,
      drive_file_id TEXT NOT NULL, thumb_file_id TEXT,
      account_id TEXT NOT NULL, account_email TEXT,
      taken_at TEXT NOT NULL, is_favourite INTEGER DEFAULT 0,
      is_deleted INTEGER DEFAULT 0, is_secure INTEGER DEFAULT 0,
      person_id TEXT, album_id TEXT, created_at TEXT NOT NULL, local_id TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS albums (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
      cover_photo_id TEXT, created_at TEXT NOT NULL, photo_count INTEGER DEFAULT 0
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS people (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, cover_photo_id TEXT,
      photo_count INTEGER DEFAULT 0, photo_ids TEXT DEFAULT ''
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS backup_log (
      local_id TEXT PRIMARY KEY, backed_up_at TEXT, account_id TEXT
    )''');

    final photosInfo = await db.rawQuery('PRAGMA table_info(photos)');
    final photoColumns = photosInfo.map((e) => e['name'] as String).toSet();

    if (!photoColumns.contains('local_id')) {
      await db.execute('ALTER TABLE photos ADD COLUMN local_id TEXT');
    }
    if (!photoColumns.contains('account_email')) {
      await db.execute('ALTER TABLE photos ADD COLUMN account_email TEXT');
    }
    if (!photoColumns.contains('created_at')) {
      await db.execute("ALTER TABLE photos ADD COLUMN created_at TEXT DEFAULT ''");
      await db.execute("UPDATE photos SET created_at = COALESCE(created_at, taken_at, datetime('now'))");
    }

    await db.execute('CREATE INDEX IF NOT EXISTS idx_taken ON photos(taken_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_secure ON photos(is_secure)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_deleted ON photos(is_deleted)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_person ON photos(person_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_album ON photos(album_id)');
  }

  // ── Photos ──────────────────────────────────────────────────────────────────
  static Future<void> insertPhoto(CloudPhoto p, {String? localId}) async {
    final d = await db;
    await d.insert('photos', {...p.toMap(), 'local_id': localId},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<CloudPhoto>> getPhotos({
    bool deleted = false, bool secure = false,
    bool favourites = false, String? personId,
    String? albumId, String? search,
  }) async {
    final d = await db;
    String where = 'is_deleted = ? AND is_secure = ?';
    List<dynamic> args = [deleted ? 1 : 0, secure ? 1 : 0];
    if (favourites) where += ' AND is_favourite = 1';
    if (personId != null) { where += ' AND person_id = ?'; args.add(personId); }
    if (albumId != null) { where += ' AND album_id = ?'; args.add(albumId); }
    if (search != null) { where += ' AND name LIKE ?'; args.add('%$search%'); }
    final rows = await d.query(
      'photos',
      where: where,
      whereArgs: args,
      orderBy: 'taken_at DESC, created_at DESC',
    );
    return rows.map(CloudPhoto.fromMap).toList();
  }

  static Future<void> updatePhoto(String id, Map<String, dynamic> updates) async {
    final d = await db;
    final mapped = updates.map((k, v) => MapEntry(k, v is bool ? (v ? 1 : 0) : v));
    await d.update('photos', mapped, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deletePhotoRecord(String id) async {
    final d = await db;
    await d.delete('photos', where: 'id = ?', whereArgs: [id]);
  }
  
  static Future<Map<String, CloudPhoto>> getPhotosByLocalIds(Set<String> localIds) async {
    if (localIds.isEmpty) return {};
    final d = await db;
    final placeholders = List.filled(localIds.length, '?').join(',');
    final rows = await d.query(
      'photos',
      where: 'local_id IN ($placeholders) AND is_deleted = 0',
      whereArgs: localIds.toList(),
    );
    final map = <String, CloudPhoto>{};
    for (final row in rows) {
      final photo = CloudPhoto.fromMap(row);
      final localId = row['local_id'] as String?;
      if (localId != null) {
        map[localId] = photo;
      }
    }
    return map;
  }
  
  static Future<void> softDeleteByLocalId(String localId) async {
    final d = await db;
    await d.update(
      'photos',
      {'is_deleted': 1},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  static Future<List<CloudPhoto>> getBackedPhotosWithoutLocalIds(Set<String> presentLocalIds) async {
    final d = await db;
    // Return all non-deleted photos that *do not* currently have a
    // matching local gallery item. This ensures that when a photo is
    // deleted from the device gallery but has already been backed up
    // to Drive, it still appears in Cloudpix as a cloud-only item.

    final rows = await d.query(
      'photos',
      where: 'is_deleted = 0',
      orderBy: 'taken_at DESC, created_at DESC',
    );

    // Filter out any rows that still have a local_id present in the
    // current gallery set so we don't duplicate items between the
    // device section and the cloud-only section.
    if (presentLocalIds.isEmpty) {
      return rows.map(CloudPhoto.fromMap).toList();
    }

    final result = <CloudPhoto>[];
    for (final row in rows) {
      final localId = row['local_id'] as String?;
      if (localId != null && presentLocalIds.contains(localId)) {
        continue;
      }
      result.add(CloudPhoto.fromMap(row));
    }
    return result;
  }

  static Future<bool> isAlreadyBacked(String localId) async {
    final d = await db;
    final rows = await d.query('backup_log', where: 'local_id = ?', whereArgs: [localId]);
    return rows.isNotEmpty;
  }

  static Future<Set<String>> getAllBackedLocalIds() async {
    final d = await db;
    final rows = await d.query('backup_log', columns: ['local_id']);
    return rows
        .map((row) => row['local_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  static Future<void> markBacked(String localId, String accountId) async {
    final d = await db;
    await d.insert('backup_log', {
      'local_id': localId, 'backed_up_at': DateTime.now().toIso8601String(), 'account_id': accountId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Memory>> getMemories() async {
    final d = await db;
    final now = DateTime.now();
    final memories = <Memory>[];
    for (int y = 1; y <= 5; y++) {
      final year = now.year - y;
      final from = DateTime(year, now.month, now.day - 3).toIso8601String();
      final to = DateTime(year, now.month, now.day + 3).toIso8601String();
      final rows = await d.query('photos',
        where: 'taken_at >= ? AND taken_at <= ? AND is_deleted = 0 AND is_secure = 0',
        whereArgs: [from, to], orderBy: 'taken_at DESC', limit: 20);
      if (rows.isNotEmpty) memories.add(Memory(year: year, photos: rows.map(CloudPhoto.fromMap).toList()));
    }
    return memories;
  }

  // ── Albums ──────────────────────────────────────────────────────────────────
  static Future<void> insertAlbum(CloudAlbum a) async {
    final d = await db;
    await d.insert('albums', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<CloudAlbum>> getAlbums() async {
    final d = await db;
    final rows = await d.query('albums', orderBy: 'created_at DESC');
    return rows.map(CloudAlbum.fromMap).toList();
  }

  static Future<void> deleteAlbum(String id) async {
    final d = await db;
    await d.delete('albums', where: 'id = ?', whereArgs: [id]);
    await d.update('photos', {'album_id': null}, where: 'album_id = ?', whereArgs: [id]);
  }

  // ── People ──────────────────────────────────────────────────────────────────
  static Future<void> insertPerson(CloudPerson p) async {
    final d = await db;
    await d.insert('people', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<CloudPerson>> getPeople() async {
    final d = await db;
    final rows = await d.query('people', orderBy: 'photo_count DESC');
    return rows.map(CloudPerson.fromMap).toList();
  }

  static Future<void> updatePerson(String id, Map<String, dynamic> updates) async {
    final d = await db;
    await d.update('people', updates, where: 'id = ?', whereArgs: [id]);
  }
}
