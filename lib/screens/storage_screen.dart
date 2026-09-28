import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/google_drive_service.dart';
import '../utils/theme.dart';
import '../widgets/widgets.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<GoogleDriveAccount> _accounts = [];
  CombinedStats? _stats;
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await GoogleDriveService.getCombinedStats();
    setState(() { _accounts = stats.accounts; _stats = stats; _loading = false; });
  }

  Future<void> _addAccount() async {
    setState(() => _adding = true);
    try {
      final account = await GoogleDriveService.addAccount();
      if (account != null) {
        setState(() => _accounts.add(account));
        _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ ${account.email} added! +15GB storage'),
          backgroundColor: AppTheme.accent,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ ${e.toString()}'), backgroundColor: AppTheme.danger,
      ));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeAccount(GoogleDriveAccount account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Remove Account?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Remove ${account.email}?\n\nYour photos are still safe in Google Drive. They just won\'t show in Cloudpix from this account.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await GoogleDriveService.removeAccount(account.id);
      _load();
    }
  }

  Future<void> _reconnectAccount(GoogleDriveAccount account) async {
    try {
      await GoogleDriveService.reauthenticateAccount(account.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reconnected ${account.email} successfully.'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reconnect failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surface : AppTheme.lightSurface;
    final surfaceAlt = isDark ? AppTheme.surfaceAlt : AppTheme.lightSurfaceAlt;
    final textPrimary = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;
    final border = isDark ? AppTheme.border : AppTheme.lightBorder;
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: _loading
        ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Combined storage card ──────────────────────────────────────
              if (_stats != null) Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primary.withOpacity(0.15), AppTheme.accent.withOpacity(0.08)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.cloud_rounded, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text('Total Storage', style: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                      child: Text('${_stats!.accountCount} Google accounts',
                        style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  RichText(text: TextSpan(children: [
                    TextSpan(text: '${_stats!.usedGB.toStringAsFixed(1)} GB ',
                      style: TextStyle(color: textPrimary, fontSize: 32, fontWeight: FontWeight.w700, fontFamily: 'Outfit')),
                    TextSpan(text: '/ ${_stats!.totalGB.toStringAsFixed(0)} GB',
                      style: TextStyle(color: textSecondary, fontSize: 18, fontFamily: 'Outfit')),
                  ])),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (_stats!.percentUsed / 100).clamp(0.0, 1.0),
                      backgroundColor: surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(
                        _stats!.percentUsed > 90 ? AppTheme.danger
                          : _stats!.percentUsed > 70 ? AppTheme.warning : AppTheme.primary),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${_stats!.percentUsed.toStringAsFixed(1)}% used · ${(_stats!.availableBytes / (1024*1024*1024)).toStringAsFixed(1)} GB free',
                    style: TextStyle(color: textHint, fontSize: 12)),
                ]),
              ),

              const SizedBox(height: 20),

              // ── Add Google Account button ──────────────────────────────────
              Builder(
                builder: (context) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final fgColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
                  final borderColor = isDark ? AppTheme.border : AppTheme.lightBorder;
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _adding ? null : _addAccount,
                      icon: _adding
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                        : Image.asset('assets/google_logo.png', width: 18, height: 18,
                            errorBuilder: (_, __, ___) => const Icon(Icons.account_circle_outlined, size: 18)),
                      label: Text(_adding ? 'Signing in...' : 'Add Google Account (+15GB)',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: fgColor,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),
              // Tip
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.15)),
                ),
                child: const Row(children: [
                  Text('💡', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Each Google account gives 15GB free! Add more accounts to get more storage.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  )),
                ]),
              ),

              const SizedBox(height: 20),
              const Text('YOUR GOOGLE ACCOUNTS', style: TextStyle(
                color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1,
              )),
              const SizedBox(height: 12),

              // ── Account list ───────────────────────────────────────────────
              if (_accounts.isEmpty)
                const EmptyState(
                  emoji: '☁️',
                  title: 'No Accounts Yet',
                  subtitle: 'Tap "Add Google Account" above\nto connect your first account',
                )
              else
                for (final acc in _accounts) ...[
                  _AccountTile(
                    account: acc,
                    onRemove: () => _removeAccount(acc),
                    onReconnect: () => _reconnectAccount(acc),
                  ),
                  const SizedBox(height: 10),
                ],

              const SizedBox(height: 20),
              // Storage math
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Storage Calculator', style: TextStyle(
                    color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 10),
                  for (final row in [
                    ('1 account', '15 GB'),
                    ('2 accounts', '30 GB'),
                    ('3 accounts', '45 GB'),
                    ('5 accounts', '75 GB'),
                    ('10 accounts', '150 GB'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Text(row.$1, style: TextStyle(color: textSecondary, fontSize: 13)),
                        const Spacer(),
                        Text(row.$2, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final GoogleDriveAccount account;
  final VoidCallback onRemove;
  final VoidCallback onReconnect;
  const _AccountTile({required this.account, required this.onRemove, required this.onReconnect});

  @override
  Widget build(BuildContext context) {
    final pct = account.percentUsed;
    final color = pct > 0.9 ? AppTheme.danger : pct > 0.7 ? AppTheme.warning : AppTheme.accent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Google avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.surfaceAlt,
            backgroundImage: account.photoUrl != null ? NetworkImage(account.photoUrl!) : null,
            child: account.photoUrl == null
              ? Text(account.displayName[0].toUpperCase(),
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700))
              : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(account.displayName,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
            Text(account.email, style: const TextStyle(color: AppTheme.textHint, fontSize: 12)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: account.isActive ? AppTheme.accent.withOpacity(0.1) : AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(account.isActive ? '● Active' : '● Full',
              style: TextStyle(
                color: account.isActive ? AppTheme.accent : AppTheme.textHint,
                fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onReconnect,
            child: const Icon(Icons.refresh_rounded, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 8),
          GestureDetector(onTap: onRemove,
            child: const Icon(Icons.remove_circle_outline_rounded, color: AppTheme.danger, size: 20)),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${account.usedGB.toStringAsFixed(1)} GB used',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
          Text('${account.totalGB.toStringAsFixed(0)} GB',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ]),
    );
  }
}
