import 'dart:async';

import 'package:flutter/material.dart';

import '../../vault/vault_keys.dart';
import '../../vault/vault_session.dart';
import '../../widgets/progress_dialog.dart';
import 'locked_gallery_screen.dart';

/// Sets up, upgrades or unlocks the vault.
///
/// With [returnResult] the screen pops `true` once unlocked (used when an
/// action such as "move to locked gallery" needs the key); otherwise it opens
/// the locked gallery.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.returnResult = false});

  final bool returnResult;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _session = VaultSession.instance;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _biometricAvailable = false;
  bool _enableBiometric = false;
  String? _error;
  Timer? _ticker;

  bool get _settingUp => _session.state == VaultState.notSetUp;

  @override
  void initState() {
    super.initState();
    _init();
    var wasLockedOut = _session.lockoutRemaining != null;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final lockedOut = _session.lockoutRemaining != null;
      // Rebuild while counting down AND once more when the lockout ends,
      // otherwise the field stays disabled showing "1s".
      if (mounted && (lockedOut || wasLockedOut)) {
        setState(() {
          if (!lockedOut) _error = null;
        });
      }
      wasLockedOut = lockedOut;
    });
  }

  Future<void> _init() async {
    if (_session.isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onUnlocked());
      return;
    }
    final available = await _session.isBiometricAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (_session.state == VaultState.locked && _session.biometricEnabled && available) {
      _unlockBiometric();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onUnlocked() {
    if (!mounted) return;
    if (widget.returnResult) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        settings: const RouteSettings(name: '/vault'),
        builder: (_) => const LockedGalleryScreen(),
      ));
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _password.text;
    setState(() => _error = null);
    if (_settingUp) {
      final problem = VaultSession.validateNewPassword(password, _confirm.text);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    } else if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }

    setState(() => _busy = true);
    try {
      if (_settingUp) {
        await _session.setUp(password, enableBiometric: _enableBiometric);
      } else {
        await _session.unlockWithPassword(password);
      }
      _password.clear();
      _confirm.clear();
      _onUnlocked();
    } on WrongPasswordException {
      _password.clear();
      final wait = _session.lockoutRemaining;
      setState(() => _error = wait == null ? 'Incorrect password' : 'Too many attempts');
    } on VaultThrottledException {
      setState(() => _error = 'Too many attempts');
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _session.unlockWithBiometric();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _onUnlocked();
    } else {
      setState(() => _error = 'Biometric unlock failed — use your password');
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset locked gallery?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your password is the only key to the encrypted files, so it cannot be recovered. '
              'Resetting permanently deletes everything in the locked gallery.\n\nType DELETE to confirm.',
            ),
            TextField(controller: controller, autofocus: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TextButton(
              onPressed: controller.text == 'DELETE' ? () => Navigator.pop(context, true) : null,
              child: const Text('Delete everything', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (confirmed != true) return;
    await _session.resetVault();
    if (!mounted) return;
    setState(() => _error = null);
    showSnack(context, 'Locked gallery deleted. Create a new password.');
  }

  @override
  Widget build(BuildContext context) {
    final lockout = _session.lockoutRemaining;
    final title = _settingUp ? 'Set Up Locked Gallery' : 'Locked Gallery';
    final message = _settingUp
        ? 'Create a password to protect your private gallery.\nIt cannot be recovered if you forget it.'
        : 'Enter your password';

    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.lock_outline, size: 72),
              const SizedBox(height: 24),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              TextField(
                key: const Key('password'),
                controller: _password,
                obscureText: _obscure,
                enabled: !_busy && lockout == null,
                autofocus: !_session.biometricEnabled,
                textInputAction: _settingUp ? TextInputAction.next : TextInputAction.done,
                onSubmitted: _settingUp ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_settingUp) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const Key('confirm'),
                  controller: _confirm,
                  obscureText: _obscure,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder()),
                ),
              ],
              if (_settingUp && _biometricAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Unlock with biometrics'),
                  subtitle: const Text('Fingerprint or face unlock, in addition to the password'),
                  value: _enableBiometric,
                  onChanged: _busy ? null : (v) => setState(() => _enableBiometric = v),
                ),
              if (_error != null || lockout != null) ...[
                const SizedBox(height: 12),
                Text(
                  lockout != null ? 'Too many attempts. Try again in ${lockout.inSeconds + 1}s.' : _error!,
                  key: const Key('auth-error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('submit'),
                onPressed: _busy || lockout != null ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_settingUp ? 'Create password' : 'Unlock'),
              ),
              if (_session.state == VaultState.locked && _session.biometricEnabled && _biometricAvailable)
                TextButton.icon(
                  onPressed: _busy ? null : _unlockBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use biometrics'),
                ),
              if (!_settingUp)
                TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
