class AppConstants {
  static const String appName = 'Cloudpix';
  static const String rootFolderName = 'Cloudpix';
  static const String secureFolderName = 'SecureFolder';
  
  // Storage
  static const int standardGoogleStorageBytes = 15 * 1024 * 1024 * 1024; // 15GB
  
  // Database
  static const String dbName = 'cloudpix.db';
  static const int dbVersion = 1;
  
  // Mime Types
  static const String folderMimeType = 'application/vnd.google-apps.folder';
  static const List<String> imageMimeTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic'
  ];
  
  // Pagination
  static const int defaultPageSize = 50;
}
