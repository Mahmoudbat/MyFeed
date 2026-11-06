import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfeed/util/format.dart';
import 'package:myfeed/widgets/media_tile.dart';

void main() {
  test('formatDuration keeps hours', () {
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 12, seconds: 3)), '12:03');
    expect(formatDuration(const Duration(hours: 1, minutes: 5)), '1:05:00');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
  });

  testWidgets('MediaTile shows video badge and selection state', (tester) async {
    var taps = 0, longPresses = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 120,
          height: 120,
          child: MediaTile(
            image: const SizedBox(),
            isVideo: true,
            durationSeconds: 75,
            selectionMode: true,
            selected: true,
            onTap: () => taps++,
            onLongPress: () => longPresses++,
          ),
        ),
      ),
    ));
    expect(find.text('1:15'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.byType(MediaTile));
    await tester.longPress(find.byType(MediaTile));
    expect(taps, 1);
    expect(longPresses, 1);
  });
}
