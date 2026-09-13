import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/widgets/mapping/walk_track_button.dart';

void main() {
  group('WalkTrackButton Widget Tests', () {
    testWidgets('renders round knob and idle guidance text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalkTrackButton(
              isRecording: false,
              isLocked: false,
              onRecordingChanged: (_) {},
              onLockChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Hold to Walk • Flick ↑ to Lock'), findsOneWidget);
      expect(find.byIcon(Icons.directions_walk), findsOneWidget);
    });

    testWidgets('press-and-hold immediately starts recording and release finishes walk', (tester) async {
      bool recording = false;
      bool walkFinished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WalkTrackButton(
                  isRecording: recording,
                  isLocked: false,
                  distanceTraversedMeters: 3.2,
                  onRecordingChanged: (val) => setState(() => recording = val),
                  onLockChanged: (_) {},
                  onWalkFinished: () => setState(() => walkFinished = true),
                );
              },
            ),
          ),
        ),
      );

      final knob = find.byIcon(Icons.directions_walk);
      expect(knob, findsOneWidget);

      // Press and hold knob down
      final gesture = await tester.startGesture(tester.getCenter(knob));
      await tester.pump();

      // Recording should start immediately on touch down
      expect(recording, isTrue);
      expect(find.textContaining('WALKING +3.2m'), findsOneWidget);

      // Release finger
      await gesture.up();
      await tester.pumpAndSettle();

      expect(recording, isFalse);
      expect(walkFinished, isTrue);
    });

    testWidgets('flicking knob upwards triggers onLockChanged(true)', (tester) async {
      bool recording = false;
      bool locked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WalkTrackButton(
                  isRecording: recording,
                  isLocked: locked,
                  distanceTraversedMeters: 4.5,
                  onRecordingChanged: (val) => setState(() => recording = val),
                  onLockChanged: (val) => setState(() => locked = val),
                );
              },
            ),
          ),
        ),
      );

      final knob = find.byIcon(Icons.directions_walk);
      expect(knob, findsOneWidget);

      // Drag/flick knob upwards by 50 pixels
      await tester.drag(knob, const Offset(0, -50));
      await tester.pumpAndSettle();

      expect(locked, isTrue);
      expect(find.textContaining('LOCKED +4.5m'), findsOneWidget);
    });

    testWidgets('tapping locked knob unlocks and triggers onLockChanged(false)', (tester) async {
      bool locked = true;
      bool walkFinished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return WalkTrackButton(
                  isRecording: false,
                  isLocked: locked,
                  distanceTraversedMeters: 8.2,
                  onRecordingChanged: (_) {},
                  onLockChanged: (val) => setState(() => locked = val),
                  onWalkFinished: () => setState(() => walkFinished = true),
                );
              },
            ),
          ),
        ),
      );

      expect(find.textContaining('LOCKED +8.2m'), findsOneWidget);

      // Tap locked knob to unlock
      final lockedKnob = find.byIcon(CupertinoIcons.lock_fill).last;
      await tester.tap(lockedKnob);
      await tester.pumpAndSettle();

      expect(locked, isFalse);
      expect(walkFinished, isTrue);
    });
  });
}
