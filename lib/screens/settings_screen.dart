import 'package:flutter/material.dart';
import 'dart:async';
import '../services/auto_backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoBackupEnabled = false;
  bool _mediaPermissionEnabled = false;
  bool _busy = false;
  BackupStatusSnapshot _status = BackupStatusSnapshot.idle();
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _loadState();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadState() async {
    final enabled = await AutoBackupService.isEnabled();
    final mediaPermission = await AutoBackupService.isMediaPermissionEnabled();
    final status = await AutoBackupService.getLastStatus();
    if (!mounted) return;
    setState(() {
      _autoBackupEnabled = enabled;
      _mediaPermissionEnabled = mediaPermission;
      _status = status;
    });
  }

  Future<void> _refreshStatus() async {
    final status = await AutoBackupService.getLastStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _setAutoBackup(bool value) async {
    setState(() => _busy = true);
    try {
      if (value) {
        await AutoBackupService.enable();
      } else {
        await AutoBackupService.disable();
      }
      await _loadState();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMediaPermission(bool value) async {
    setState(() => _busy = true);
    try {
      if (value) {
        final granted = await AutoBackupService.requestMediaPermission();
        if (!mounted) return;
        setState(() {
          _mediaPermissionEnabled = granted;
        });
        if (granted) {
          await AutoBackupService.triggerNow();
          await _refreshStatus();
        }
      } else {
        await AutoBackupService.setMediaPermissionEnabled(false);
        if (!mounted) return;
        setState(() {
          _mediaPermissionEnabled = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      await AutoBackupService.triggerNow();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _refreshStatus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAboutCloudPix() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('About CloudPix'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'CloudPix — Auto backup, smart gallery & multi-account cloud storage.\n'
                  'Built by Jathindra Reddy | Founder, CloudPix\n'
                  'Version 4.0.0',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 16),
                Text(
                  'What is CloudPix?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'CloudPix is a photo storage and sharing app that automatically backs up your photos, '
                  'unifies all your Google accounts into one gallery, and keeps your memories safe — simply and securely.',
                ),
                SizedBox(height: 16),
                Text(
                  'Features',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  '1. Auto backup\n'
                  'Automatically backs up your camera and gallery in the background — even when the app is closed.\n\n'
                  '2. Unified gallery\n'
                  'View photos from all your Google accounts in one clean, organised gallery. No switching needed.\n\n'
                  '3. People & face recognition\n'
                  'Recognises faces on-device — completely private. No data leaves your phone, ever.\n\n'
                  '4. Secure folder\n'
                  'Lock sensitive photos behind PIN or fingerprint. Your private moments stay private.\n\n'
                  '5. Multi-account cloud storage\n'
                  'Add unlimited Google accounts. Each account shows its own live storage meter — always in control.',
                ),
                SizedBox(height: 16),
                Text(
                  'Developer info',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'Name — Jathindra Reddy\n'
                  'Role — Founder, CloudPix\n'
                  'Developer ID — jathindra07@gmail.com',
                ),
                SizedBox(height: 16),
                Text(
                  'CloudPix v4.0.0 · © 2026 Jathindra Reddy. All rights reserved.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _status.total > 0
        ? (_status.backed + _status.failed + _status.skipped) / _status.total
        : 0.0;

    final statusColor = switch (_status.stage) {
      'success' => Colors.green,
      'partial' => Colors.orange,
      'error' => Colors.red,
      'blocked' => Colors.red,
      'uploading' => Theme.of(context).colorScheme.primary,
      _ => Colors.grey,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Auto-Backup'),
            subtitle: Text(_autoBackupEnabled ? 'Auto Backup ON' : 'Auto Backup OFF'),
            trailing: Switch(
              value: _autoBackupEnabled,
              onChanged: _busy ? null : _setAutoBackup,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Allow Photos/Videos Permission'),
            subtitle: Text(
              _mediaPermissionEnabled
                  ? 'Access to gallery is ON. New photos and videos can be backed up.'
                  : 'Access to gallery is OFF. Turn this ON to let Cloudpix read your photos/videos.',
            ),
            trailing: Switch(
              value: _mediaPermissionEnabled,
              onChanged: _busy ? null : _toggleMediaPermission,
            ),
          ),
          const Divider(height: 1),
          const ListTile(
            title: Text('Backup Mode'),
            subtitle: Text('Near real-time in app, fast battery-aware background retries.'),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Sync Now'),
            subtitle: const Text('Run one background sync immediately'),
            trailing: ElevatedButton(
              onPressed: _busy ? null : _syncNow,
              child: const Text('Run'),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_status.running ? Icons.sync : Icons.cloud_done, color: statusColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _status.running ? 'Syncing in background' : 'Sync status',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(_status.message),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _status.running && _status.total > 0 ? progress.clamp(0.0, 1.0) : null,
                  minHeight: 7,
                ),
                const SizedBox(height: 8),
                Text(
                  'Backed: ${_status.backed}  Failed: ${_status.failed}  Skipped: ${_status.skipped}  Total: ${_status.total}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Secure Folder PIN'),
            subtitle: const Text('Change your Secure Folder PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            title: const Text('Storage Cleanup'),
            subtitle: const Text('Remove old backup files'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            title: const Text('About'),
            subtitle: const Text('Cloudpix 4.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAboutCloudPix,
          ),
        ],
      ),
    );
  }
}
