import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfeed/services/app_settings.dart';
import 'package:myfeed/vault/vault_auto_lock.dart';
import 'package:myfeed/widgets/vault_auto_lock_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('immediate locks synchronously and cancels an existing countdown',
      (tester) async {
    var locks = 0;
    final timer = VaultAutoLock(() => locks++);
    timer.start(const Duration(seconds: 15));
    timer.start(Duration.zero);
    expect(locks, 1);
    await tester.pump(const Duration(minutes: 1));
    timer.resume();
    expect(locks, 1);
  });

  testWidgets(
      'off cancels pending locking and stays unlocked across departures',
      (tester) async {
    var locks = 0;
    var now = DateTime(2026);
    final timer = VaultAutoLock(() => locks++, now: () => now);
    timer.start(const Duration(seconds: 5));
    for (var departure = 0; departure < 3; departure++) {
      timer.start(null);
      now = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      timer.resume();
      expect(locks, 0);
    }
    timer.start(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(locks, 1);
  });

  testWidgets('locks at the deadline without extending repeated pauses',
      (tester) async {
    var locks = 0;
    final timer = VaultAutoLock(() => locks++);
    timer.start(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 10));
    timer.start(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 4));
    expect(locks, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(locks, 1);
  });

  testWidgets('returning early cancels and next departure gets a fresh delay',
      (tester) async {
    var locks = 0;
    var now = DateTime(2026);
    final timer = VaultAutoLock(() => locks++, now: () => now);
    timer.start(const Duration(seconds: 5));
    now = now.add(const Duration(seconds: 4));
    timer.resume();
    await tester.pump(const Duration(seconds: 10));
    expect(locks, 0);
    timer.start(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(locks, 1);
  });

  testWidgets('resume enforces expiry even if background timer never ran',
      (tester) async {
    var locks = 0;
    var now = DateTime(2026);
    final timer = VaultAutoLock(() => locks++, now: () => now);
    timer.start(const Duration(seconds: 55));
    now = now.add(const Duration(seconds: 55));
    timer.resume();
    expect(locks, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(locks, 1);
  });

  testWidgets('manual cancellation removes a stale deadline', (tester) async {
    var locks = 0;
    final timer = VaultAutoLock(() => locks++);
    timer.start(const Duration(seconds: 5));
    timer.cancel();
    await tester.pump(const Duration(seconds: 10));
    timer.resume();
    expect(locks, 0);
  });

  test('delay persists and rejects values outside five-second steps', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;
    await settings.load();
    expect(settings.vaultAutoLockSeconds, 15);
    for (final seconds in [-1, for (var s = 0; s < 60; s += 5) s]) {
      await settings.setVaultAutoLockSeconds(seconds);
      await settings.load();
      expect(settings.vaultAutoLockSeconds, seconds);
      expect(settings.vaultAutoLockDelay,
          seconds == -1 ? null : Duration(seconds: seconds));
    }
    for (final seconds in [-5, -2, 1, 7, 59, 60, 65]) {
      await expectLater(
          settings.setVaultAutoLockSeconds(seconds), throwsArgumentError);
      expect(settings.vaultAutoLockSeconds, 55);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vault_auto_lock_seconds', 60);
    await settings.load();
    expect(settings.vaultAutoLockSeconds, 15);
  });

  testWidgets('compact picker snaps to valid delays and saves only on Save',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;
    await settings.load();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VaultAutoLockSetting()),
    ));
    await tester.tap(find.text('Auto-lock delay'));
    await tester.pumpAndSettle();
    expect(find.text('Immediately'), findsOneWidget);
    expect(find.text('Delay'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('55 seconds'), findsOneWidget);
    expect(settings.vaultAutoLockSeconds, 15);
    await tester.drag(slider, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('5 seconds'), findsOneWidget);
    // Switching modes keeps the draft delay.
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text('Delay'));
    await tester.pumpAndSettle();
    expect(find.text('5 seconds'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Lock 5 seconds after leaving the app'), findsOneWidget);
    await settings.load();
    expect(settings.vaultAutoLockSeconds, 5);
  });

  testWidgets('cancel discards draft and dialog fits a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;
    await settings.load();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: VaultAutoLockSetting()),
    ));
    await tester.tap(find.text('Auto-lock delay'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final surface = find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(Material))
        .first;
    expect(tester.getSize(surface).height, lessThan(400));
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.vaultAutoLockSeconds, 15);
  });

  for (final choice in {'Immediately': 0, 'Off': -1}.entries) {
    testWidgets('${choice.key} can be selected, saved and reopened',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings.instance;
      await settings.load();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: VaultAutoLockSetting()),
      ));
      await tester.tap(find.text('Auto-lock delay'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(choice.key));
      await tester.tap(find.text(choice.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await settings.load();
      await tester.pumpAndSettle();
      expect(settings.vaultAutoLockSeconds, choice.value);
      expect(find.text(settings.vaultAutoLockDescription), findsOneWidget);
      await tester.tap(find.text('Auto-lock delay'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          {choice.value});
      expect(find.byType(Slider), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
