import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:space_rush_claude/game/models.dart';

void main() {
  group('coin spawn planner', () {
    const planner = CoinSpawnPlanner();

    test('patterns keep minimum center distance', () {
      for (final pattern in CoinPattern.values) {
        final offsets = planner.offsetsFor(pattern);
        for (var i = 0; i < offsets.length; i++) {
          for (var j = i + 1; j < offsets.length; j++) {
            expect(
              (offsets[i] - offsets[j]).distance,
              greaterThanOrEqualTo(CoinSpawnPlanner.minimumCenterDistance - .001),
              reason: '$pattern overlap between $i and $j',
            );
          }
        }
      }
    });

    test('patternFits rejects overlapping anchors', () {
      const anchor = Offset(180, 120);
      const pattern = CoinPattern.horizontal;
      final existing = planner.offsetsFor(pattern).map((offset) => anchor + offset);
      expect(
        planner.patternFits(
          anchor: anchor,
          pattern: pattern,
          spawnBounds: const Rect.fromLTWH(40, 80, 320, 640),
          existing: existing,
          blockedRects: const [],
        ),
        isFalse,
      );
    });
  });

  group('world camera', () {
    test('world distance moves objects without moving player space', () {
      const camera = WorldCamera(offset: Offset(0, 220));
      const worldCoin = Offset(140, 360);
      final screenCoin = camera.worldToScreen(worldCoin);
      expect(screenCoin, const Offset(140, 140));

      const player = Offset(140, 620);
      expect(camera.screenToWorld(player), const Offset(140, 840));
      expect(camera.worldToScreen(camera.screenToWorld(player)), player);
    });
  });
}
