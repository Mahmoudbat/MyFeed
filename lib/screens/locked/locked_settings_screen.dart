import 'package:flutter/material.dart';

import '../../services/app_settings.dart';
import '../../util/format.dart';
import '../../vault/vault_keys.dart';
import '../../vault/vault_session.dart';
import '../../widgets/progress_dialog.dart';
import '../../widgets/vault_auto_lock_setting.dart';
import 'vault_actions.dart';

VaultSession get _session => VaultSession.instance;

class LockedSettingsScreen extends StatefulWidget {
  const LockedSettingsScreen({super.key});

  @override
  State<LockedSettingsScreen> createState() => _LockedSettingsScreenState();
}

class _LockedSettingsScreenState extends State<LockedSettingsScreen> {
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _session.isBiometricAvailable().then((v) {
      if (mounted) setState(() => _biometricAvailable = v);
    });
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirmCtl = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
              TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
              TextField(controller: confirmCtl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final problem = VaultSession.validateNewPassword(next.text, confirmCtl.text);
                      if (problem != null) {
                        setDialogState(() => error = problem);
                        return;
                      }
                      setDialogState(() => busy = true);
                      final messenger = ScaffoldMessenger.of(this.context);
                      try {
                        await _session.changePassword(current.text, next.text);
                        if (context.mounted) Navigator.pop(context);
                        messenger.showSnackBar(const SnackBar(content: Text('Password changed')));
                      } on WrongPasswordException {
                        setDialogState(() {
                          busy = false;
                          error = 'Current password is incorrect';
                        });
                      }
                    },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      current.dispose();
      next.dispose();
      confirmCtl.dispose();
    });
  }

  Future<void> _wipe() async {
    if (!await confirm(context,
        title: 'Delete locked gallery?',
        message: 'Every photo, video and album in the locked gallery will be permanently erased, '
            'and the password removed. This cannot be undone.',
        action: 'Delete everything',
        destructive: true)) {
      return;
    }
    if (!mounted) return;
    final count = _session.store.items.length;
    final messenger = ScaffoldMessenger.of(context);
    await _session.resetVault(); // also closes all vault screens
    messenger.showSnackBar(SnackBar(content: Text('Locked gallery deleted ($count items)')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_session, _session.store, AppSettings.instance]),
      builder: (context, _) {
        final items = _session.store.items;
        final totalSize = items.fold<int>(0, (sum, i) => sum + i.size);
        return Scaffold(
          appBar: AppBar(title: const Text('Locked Gallery Settings')),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.storage),
                title: Text('${items.length} items · ${formatBytes(totalSize)}'),
                subtitle: const Text('Encrypted with AES-256-GCM; key protected by your password'),
              ),
              const Divider(),
              const VaultAutoLockSetting(),
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Change password'),
                onTap: _changePassword,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Unlock with biometrics'),
                subtitle: Text(_biometricAvailable
                    ? 'Stores the vault key in Android Keystore-backed storage, released after a biometric check'
                    : 'No biometrics enrolled on this device'),
                value: _session.biometricEnabled,
                onChanged: _biometricAvailable || _session.biometricEnabled
                    ? (v) async {
                        final ok = await _session.setBiometricEnabled(v);
                        if (!ok && context.mounted) showSnack(context, 'Biometric confirmation failed', error: true);
                      }
                    : null,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Restore everything to gallery'),
                subtitle: const Text('Decrypts all items back into the public gallery'),
                enabled: items.isNotEmpty,
                onTap: () async {
                  final remove = AppSettings.instance.deleteAfterExport;
                  final ok = await confirm(
                    context,
                    title: 'Restore all ${items.length} items?',
                    message: 'Every locked photo and video will be decrypted back into the public gallery'
                        '${remove ? ' and removed from the locked gallery' : ''}.',
                    action: 'Restore all',
                    destructive: remove,
                  );
                  if (ok && context.mounted) await restoreToGallery(context, List.of(items));
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.auto_delete_outlined),
                title: const Text('Remove after restoring'),
                subtitle: const Text('Delete items from the locked gallery once restored to the gallery'),
                value: AppSettings.instance.deleteAfterExport,
                onChanged: AppSettings.instance.setDeleteAfterExport,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text('Delete locked gallery', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Erase all locked media and the password'),
                onTap: _wipe,
              ),
            ],
          ),
        );
      },
    );
  }
}
