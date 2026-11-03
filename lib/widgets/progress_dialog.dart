import 'package:flutter/material.dart';

/// Progress reported by long-running vault operations.
class ProgressValue {
  const ProgressValue(this.done, this.total, [this.detail]);
  final int done;
  final int total;
  final double? detail; // progress within the current item, 0..1
  double? get fraction => total == 0 ? null : ((done + (detail ?? 0)) / total).clamp(0.0, 1.0);
}

/// Shows a non-dismissible progress dialog while [task] runs and returns its
/// result. The dialog is always closed, even if [task] throws.
Future<T> runWithProgress<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(void Function(ProgressValue) report) task,
}) async {
  final progress = ValueNotifier(const ProgressValue(0, 0));
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<ProgressValue>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: value.fraction),
              const SizedBox(height: 12),
              Text(value.total == 0 ? 'Preparing…' : '${value.done} of ${value.total}'),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(() => open = false);
  try {
    return await task((value) => progress.value = value);
  } finally {
    if (open && navigator.mounted) navigator.pop();
    progress.dispose();
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action, style: destructive ? const TextStyle(color: Colors.redAccent) : null),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String action = 'OK',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(action)),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return (result == null || result.isEmpty) ? null : result;
}
