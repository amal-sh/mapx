import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapx/logic/physical_orientation_tracker.dart';

void main() {
  group('PhysicalOrientationTracker Tests', () {
    test('initializes with default heading and pitch', () {
      final tracker = PhysicalOrientationTracker(
        initialHeadingRadians: 0.0,
        initialPitchRadians: -0.38,
      );

      expect(tracker.headingRadians, 0.0);
      expect(tracker.headingDegrees, 0.0);
      expect(tracker.cardinalDirection, 'N');
      expect(tracker.pitchRadians, closeTo(-0.38, 0.001));
    });

    test('manual rotation and setting heading', () {
      final tracker = PhysicalOrientationTracker();

      // Rotate right by 90 degrees (pi/2)
      tracker.rotateHeading(math.pi / 2);
      expect(tracker.headingDegrees, closeTo(90.0, 0.1));
      expect(tracker.cardinalDirection, 'E');

      // Rotate right another 90 degrees -> 180 degrees (South)
      tracker.rotateHeading(math.pi / 2);
      expect(tracker.headingDegrees, closeTo(180.0, 0.1));
      expect(tracker.cardinalDirection, 'S');

      // Rotate right another 90 degrees -> 270 degrees (West)
      tracker.rotateHeading(math.pi / 2);
      expect(tracker.headingDegrees, closeTo(270.0, 0.1));
      expect(tracker.cardinalDirection, 'W');

      // Set directly to 45 degrees (NE)
      tracker.setHeading(math.pi / 4);
      expect(tracker.headingDegrees, closeTo(45.0, 0.1));
      expect(tracker.cardinalDirection, 'NE');
    });

    test('calibrateCurrentAsForward zeroes the relative heading', () {
      final tracker = PhysicalOrientationTracker(initialHeadingRadians: 1.25);

      expect(tracker.headingRadians, closeTo(1.25, 0.001));

      // Calibrate current orientation as forward (0 rad)
      tracker.calibrateCurrentAsForward();
      expect(tracker.headingRadians, closeTo(0.0, 0.001));
      expect(tracker.headingDegrees, closeTo(0.0, 0.001));

      // Reset calibration returns to raw heading
      tracker.resetCalibration();
      expect(tracker.headingRadians, closeTo(1.25, 0.001));
    });

    test('listeners receive notification on orientation change', () {
      final tracker = PhysicalOrientationTracker();
      int callCount = 0;
      void listener() => callCount++;

      tracker.addListener(listener);
      tracker.rotateHeading(0.1);
      expect(callCount, 1);

      tracker.setPitch(-0.5);
      expect(callCount, 2);

      tracker.removeListener(listener);
      tracker.rotateHeading(0.1);
      expect(callCount, 2);
    });

    test('computes correct tilt-compensated pitch and roll from accelerometer', () {
      final tracker = PhysicalOrientationTracker(filterSmoothing: 1.0); // 1.0 = instant response

      // 1. Upright phone: ay = 9.8, az = 0 -> pitch = 0, roll = 0
      tracker.updateSensorsForTesting(ax: 0.0, ay: 9.8, az: 0.0);
      expect(tracker.pitchDegrees, closeTo(0.0, 0.5));
      expect(tracker.rollDegrees, closeTo(0.0, 0.5));

      // 2. Tilted 30 degrees down at floor: az = 4.9, ay = 8.487 -> pitch = -30 deg
      tracker.updateSensorsForTesting(ax: 0.0, ay: 8.487, az: 4.9);
      expect(tracker.pitchDegrees, closeTo(-30.0, 0.5));
      expect(tracker.rollDegrees, closeTo(0.0, 0.5));

      // 3. Tilted 30 degrees up at ceiling: az = -4.9, ay = 8.487 -> pitch = +30 deg
      tracker.updateSensorsForTesting(ax: 0.0, ay: 8.487, az: -4.9);
      expect(tracker.pitchDegrees, closeTo(30.0, 0.5));

      // 4. Rolled 30 degrees right: ax = 4.9, ay = 8.487 -> roll = +30 deg
      tracker.updateSensorsForTesting(ax: 4.9, ay: 8.487, az: 0.0);
      expect(tracker.rollDegrees, closeTo(30.0, 0.5));

      // 5. Rolled 30 degrees left: ax = -4.9, ay = 8.487 -> roll = -30 deg
      tracker.updateSensorsForTesting(ax: -4.9, ay: 8.487, az: 0.0);
      expect(tracker.rollDegrees, closeTo(-30.0, 0.5));
    });

    test('computes correct azimuth from magnetometer and accelerometer', () {
      final tracker = PhysicalOrientationTracker(filterSmoothing: 1.0);

      // Facing North upright:
      // ay = 9.8, az = 0 (upright)
      // mx = 0, my = 0, mz = -35 (magnetic field enters back of camera)
      tracker.updateSensorsForTesting(
        ax: 0.0, ay: 9.8, az: 0.0,
        mx: 0.0, my: 0.0, mz: -35.0,
      );
      expect(tracker.headingDegrees, closeTo(0.0, 1.0));
      expect(tracker.cardinalDirection, 'N');

      // Facing East upright:
      // mx = -35, mz = 0 (magnetic north is to the left of phone)
      tracker.updateSensorsForTesting(
        ax: 0.0, ay: 9.8, az: 0.0,
        mx: -35.0, my: 0.0, mz: 0.0,
      );
      expect(tracker.headingDegrees, closeTo(90.0, 1.0));
      expect(tracker.cardinalDirection, 'E');

      // Facing South upright:
      // mx = 0, mz = 35
      tracker.updateSensorsForTesting(
        ax: 0.0, ay: 9.8, az: 0.0,
        mx: 0.0, my: 0.0, mz: 35.0,
      );
      expect(tracker.headingDegrees, closeTo(180.0, 1.0));
      expect(tracker.cardinalDirection, 'S');
    });
  });
}
