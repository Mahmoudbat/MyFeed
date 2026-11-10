import 'dart:async';

/// Checks the deadline on resume too, in case the OS suspended Dart timers.
class VaultAutoLock {
  VaultAutoLock(this.onExpired, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final void Function() onExpired;
  final DateTime Function() _now;
  Timer? _timer;
  DateTime? _deadline;

  /// Null disables background locking; zero locks synchronously.
  void start(Duration? delay) {
    if (delay == null) {
      cancel();
      return;
    }
    if (delay <= Duration.zero) {
      _expire();
      return;
    }
    if (_deadline != null) return;
    _deadline = _now().add(delay);
    _timer = Timer(delay, _expire);
  }

  void resume() {
    final deadline = _deadline;
    if (deadline != null && !_now().isBefore(deadline)) {
      _expire();
    } else {
      cancel();
    }
  }

  void _expire() {
    cancel();
    onExpired();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _deadline = null;
  }
}
