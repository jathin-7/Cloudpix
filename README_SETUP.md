# ☁️ Cloudpix 4.0 — Google Drive Edition
## Multiple Google Accounts · 15GB Each · One Unified Gallery

---

## How It Works

```
Your Gmail        (15GB) ──┐
Friend's Gmail    (15GB) ──┤──► ONE unified gallery on your phone
Any Gmail account (15GB) ──┘
```

- Just tap "Add Google Account" and sign in
- No API keys, no complex setup
- Each account = 15GB free forever
- All photos shown in one place

---

##Quick Setup (Development)

### Prerequisites
- Flutter 3.11+ installed (`flutter --version`)
- Dart SDK (comes with Flutter)
- Android Studio + Android SDK for building APK
- Google Cloud Console account

### 1️⃣ Clone / Open Project

```bash
cd cloudpix
flutter pub get
```

### 2️⃣ Configure Google Cloud Console

1. Go to https://console.cloud.google.com
2. Click "New Project" → name it "Cloudpix" → Create
3. Enable Google Drive API:
   - Left menu → "APIs & Services" → "Library"
   - Search "Google Drive API" → Click → Enable ✅
4. Create OAuth Credentials:
   - Left menu → "APIs & Services" → "OAuth consent screen"
   - Choose "External" → Create
   - App name: `Cloudpix`
   - Your email for support
   - Click Save
5. Create Android Client ID:
   - Left menu → "Credentials" → "Create Credentials" → "OAuth Client ID"
   - Application type: **Android**
   - Package name: `com.cloudpix.app`
   - SHA-1: Get it by running:
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     ```
   - Copy your **Android Client ID**
6. Create Web Client ID:
   - Click "Create Credentials" again → "OAuth Client ID" → "Web application"
   - Copy your **Web Client ID** too

### 3️⃣ Update App Configuration

Edit `lib/utils/theme.dart` and replace:

```dart
static const googleClientId = 'YOUR_ANDROID_CLIENT_ID.apps.googleusercontent.com';
static const googleWebClientId = 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
```

Also edit `android/app/src/main/res/values/strings.xml`:

```xml
<string name="server_client_id">YOUR_WEB_CLIENT_ID.apps.googleusercontent.com</string>
```

### 4️⃣ Run the App

```bash
flutter run
```

---

## Build APK

```bash
flutter build apk --release
# Find APK at: build/app/outputs/flutter-apk/app-release.apk
```

---

## Features

- 📸 **Auto Backup** - Camera + gallery (background, app closed)
- 🖼️ **Unified Gallery** - All accounts in one place
- 🧠 **Memories** - On this day from past years
- 📁 **Albums** - Create and manage
- 👥 **People** - Face recognition (on-device ML)
- 🔒 **Secure Folder** - PIN + fingerprint protected
- ☁️ **Multi-Account** - Unlimited Google accounts
- 📊 **Storage Meter** - Per-account storage tracking

---

## Storage Calculator

| Google Accounts | Free Storage |
|---|---|
| 1 | 15 GB |
| 2 | 30 GB |
| 3 | 45 GB |
| 5 | 75 GB |
| 10 | 150 GB |

---

## Architecture

### Services

- **GoogleDriveService** - Multi-account Google Drive management
- **LocalDatabase** - SQLite for unified gallery metadata
- **AutoBackupService** - Background photo sync (WorkManager)

### Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── models.dart          # Data models (CloudPhoto, GoogleDriveAccount, etc.)
├── services/
│   ├── google_drive_service.dart
│   ├── local_database.dart
│   └── auto_backup_service.dart
├── screens/
│   ├── photos_screen.dart
│   ├── storage_screen.dart
│   ├── memories_screen.dart
│   ├── albums_screen.dart
│   ├── people_screen.dart
│   └── secure_folder_screen.dart
├── widgets/
│   └── widgets.dart
└── utils/
    └── theme.dart
```

---

## Dependencies

- **google_sign_in** - Google OAuth authentication
- **googleapis** - Google Drive API client
- **sqflite** - Local SQLite database
- **photo_manager** - Device gallery access
- **flutter_image_compress** - Image optimization
- **workmanager** - Background tasks
- **google_mlkit_face_detection** - On-device face recognition
- **flutter_secure_storage** - Secure credential storage
- **local_auth** - PIN/fingerprint authentication

---

## Troubleshooting

### "Google Sign-in Failed"
- ✅ Verify Android Client ID in Google Cloud Console
- ✅ Check SHA-1 fingerprint matches (from keytool)
- ✅ Enable Google Drive API in GCP

### Compilation Errors
```bash
flutter clean
flutter pub get
flutter run
```

### Permission Denied (Photos)
- Go to Settings → Cloudpix → Permissions
- Enable "Photos / Media" access

---

## Development Notes

- All photos are encrypted in secure folder
- Thumbnails are cached locally for fast gallery loading
- Background sync respects device storage limits
- Each account's storage is tracked separately
- Deleted files aren't removed from Drive (privacy)

---

##License

MIT License - See LICENSE file

---

**Created with ❤️ for cloud storage lovers**
