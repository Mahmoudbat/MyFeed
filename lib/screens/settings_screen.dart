import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../vault/vault_session.dart';
import '../widgets/vault_auto_lock_setting.dart';
import 'locked/auth_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final session = VaultSession.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, session]),
        builder: (context, _) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.lock, color: Colors.amber),
              title: const Text('Locked Gallery'),
              subtitle: Text(session.state == VaultState.notSetUp
                  ? 'Set up a private encrypted gallery'
                  : 'Private encrypted gallery'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                settings: const RouteSettings(name: '/auth'),
                builder: (_) => const AuthScreen(),
              )),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('Remove originals after locking'),
              subtitle: const Text(
                  'After moving items to the locked gallery, delete them from the public gallery (Android asks to confirm). '
                  'Without this, locked items stay visible in your gallery.'),
              value: settings.removeOriginalsAfterLocking,
              onChanged: settings.setRemoveOriginalsAfterLocking,
            ),
            const VaultAutoLockSetting(),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.swap_vert),
              title: const Text('Vertical media scrolling'),
              subtitle: Text(settings.verticalScrolling
                  ? 'Swipe up/down between photos and videos'
                  : 'Swipe left/right between photos and videos'),
              value: settings.verticalScrolling,
              onChanged: settings.setVerticalScrolling,
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('About the locked gallery'),
              subtitle: Text(
                'Locked files are encrypted with AES-256-GCM. The key is protected by your password '
                '(PBKDF2, 600k iterations) and is never stored in the clear, so a forgotten password '
                'cannot be recovered. Auto-lock follows your setting when you leave the app, and '
                'screenshots are blocked while it is open.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
