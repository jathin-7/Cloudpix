Write-Host "Stopping all possible locking processes..." -ForegroundColor Yellow

# Stop Gradle
if (Test-Path "android/gradlew.bat") {
    try {
        Set-Location android
        .\gradlew --stop
        Set-Location ..
    } catch {}
}

# Kill Java and Dart processes
taskkill /F /FI "IMAGENAME eq java*" /T /FI "STATUS eq running" 2>$null
taskkill /F /FI "IMAGENAME eq dart*" /T /FI "STATUS eq running" 2>$null
taskkill /F /FI "IMAGENAME eq adb*" /T /FI "STATUS eq running" 2>$null

Write-Host "Forcing deletion of lock-prone directories..." -ForegroundColor Yellow

$localBuildCache = Join-Path $env:LOCALAPPDATA "cloudpix-build"

# List of directories to nuke
$dirs = @(
    "build",
    ".dart_tool",
    "android/.cloudpix-build",
    "windows/flutter/ephemeral",
    "ios/Flutter/ephemeral",
    "macos/Flutter/ephemeral",
    "C:\\flutter_builds\\cloudpix",
    $localBuildCache
)

# PowerShell can struggle with read-only reparse points under .plugin_symlinks.
# Force-delete these with cmd's rmdir first.
$pluginLinkDirs = @(
    "windows\\flutter\\ephemeral\\.plugin_symlinks",
    "linux\\flutter\\ephemeral\\.plugin_symlinks"
)

foreach ($linkDir in $pluginLinkDirs) {
    if (Test-Path $linkDir) {
        Write-Host "Force removing $linkDir..."
        attrib -R $linkDir /S /D 2>$null
        cmd /c rmdir /s /q $linkDir 2>$null
    }
}

foreach ($dir in $dirs) {
    if (Test-Path $dir) {
        Write-Host "Deleting $dir..."
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Running flutter clean..." -ForegroundColor Green
flutter clean

Write-Host "Cleanup complete! You can now run 'flutter run'." -ForegroundColor Cyan
