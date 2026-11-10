import 'package:flutter/material.dart';

import '../services/app_settings.dart';

class VaultAutoLockSetting extends StatelessWidget {
  const VaultAutoLockSetting({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: const Text('Auto-lock delay'),
        subtitle: Text(settings.vaultAutoLockDescription),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final seconds = await showDialog<int>(
            context: context,
            builder: (context) =>
                _AutoLockDialog(initialSeconds: settings.vaultAutoLockSeconds),
          );
          if (seconds != null) await settings.setVaultAutoLockSeconds(seconds);
        },
      ),
    );
  }
}

class _AutoLockDialog extends StatefulWidget {
  const _AutoLockDialog({required this.initialSeconds});

  final int initialSeconds;

  @override
  State<_AutoLockDialog> createState() => _AutoLockDialogState();
}

class _AutoLockDialogState extends State<_AutoLockDialog> {
  // 1 represents the Delay mode; actual delays are always multiples of five.
  late int _mode = widget.initialSeconds > 0 ? 1 : widget.initialSeconds;
  late int _seconds = widget.initialSeconds > 0
      ? widget.initialSeconds
      : AppSettings.defaultVaultAutoLockSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Auto-lock delay'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: theme.textTheme.labelMedium,
                ),
                segments: const [
                  ButtonSegment(
                      value: AppSettings.vaultAutoLockImmediate,
                      label: Text('Immediately')),
                  ButtonSegment(value: 1, label: Text('Delay')),
                  ButtonSegment(
                      value: AppSettings.vaultAutoLockOff, label: Text('Off')),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.single),
              ),
              const SizedBox(height: 20),
              if (_mode == 1) ...[
                Center(
                    child: Text('$_seconds seconds',
                        style: theme.textTheme.headlineSmall)),
                Slider(
                  value: _seconds.toDouble(),
                  min: 5,
                  max: 55,
                  divisions: 10,
                  label: '$_seconds seconds',
                  semanticFormatterCallback: (value) =>
                      '${value.round()} seconds',
                  onChanged: (value) =>
                      setState(() => _seconds = (value / 5).round() * 5),
                ),
                const Text('After leaving the app.'),
              ] else
                Text(_mode == AppSettings.vaultAutoLockImmediate
                    ? 'Lock as soon as the app enters the background.'
                    : 'Keep the gallery unlocked when switching apps. You can still lock it manually.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _mode == 1 ? _seconds : _mode),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
