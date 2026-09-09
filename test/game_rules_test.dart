import 'package:flutter_test/flutter_test.dart';
import 'package:space_rush_claude/game/models.dart';

void main() {
  group('difficulty progression', () {
    test('keeps the specified cumulative 10% milestones', () {
      final difficulty = DifficultyManager();
      expect(difficulty.multiplierAt(0), 1);
      expect(difficulty.multiplierAt(60), closeTo(1.1, .00001));
      expect(difficulty.multiplierAt(120), closeTo(1.21, .00001));
      expect(difficulty.multiplierAt(180), closeTo(1.331, .00001));
      expect(difficulty.multiplierAt(240), closeTo(1.4641, .00001));
    });

    test('approaches speed changes smoothly instead of snapping', () {
      final difficulty = DifficultyManager();
      difficulty.update(60, .1);
      expect(difficulty.currentDifficultySpeed, greaterThan(220));
      expect(difficulty.currentDifficultySpeed, lessThan(242));
      expect(difficulty.targetDifficultySpeed, closeTo(242, .00001));
    });
  });

  group('fairness validator', () {
    test('accepts a wide reachable route', () {
      const validator = PlayabilityValidator();
      expect(
        validator.isReachable(
          fromX: 180,
          gapCenter: 260,
          gapWidth: 150,
          distance: 500,
          speed: 220,
        ),
        isTrue,
      );
    });

    test('rejects gaps below the ship safety width', () {
      const validator = PlayabilityValidator();
      expect(
        validator.isReachable(
          fromX: 180,
          gapCenter: 180,
          gapWidth: 60,
          distance: 500,
          speed: 220,
        ),
        isFalse,
      );
    });
  });
}
