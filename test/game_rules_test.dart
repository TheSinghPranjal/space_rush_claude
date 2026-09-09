import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:space_rush_claude/game/config.dart';
import 'package:space_rush_claude/game/models.dart';
import 'package:space_rush_claude/game/systems.dart';

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

    test('validateReachability matches isReachable', () {
      const validator = PlayabilityValidator();
      expect(
        validator.validateReachability(
          fromX: 180,
          gapCenter: 200,
          gapWidth: 90,
          distance: 500,
          speed: 220,
        ),
        validator.isReachable(
          fromX: 180,
          gapCenter: 200,
          gapWidth: 90,
          distance: 500,
          speed: 220,
        ),
      );
    });

    test('narrow window at the minimum legal gap stays reachable nearby', () {
      const validator = PlayabilityValidator();
      final gap =
          PlayabilityValidator.shipWidth + PlayabilityValidator.safetyMargin;
      expect(
        validator.validateReachability(
          fromX: 180,
          gapCenter: 190,
          gapWidth: gap,
          distance: 520,
          speed: 220,
        ),
        isTrue,
      );
    });
  });

  group('speed director', () {
    test('EMP freezes obstacles while coins keep world speed', () {
      final director = SpeedDirector();
      director.setEmp(true);
      for (var i = 0; i < 40; i++) {
        director.update(10, .05);
      }
      expect(director.worldScrollSpeed, greaterThan(100));
      expect(director.obstacleScrollSpeed, closeTo(0, 8));
      expect(director.obstacleHoldSpeed, greaterThan(100));
    });

    test('Slow Time remains after EMP recovery', () {
      final director = SpeedDirector();
      director.setEmp(true);
      director.setSlowTime(true);
      for (var i = 0; i < 40; i++) {
        director.update(8, .05);
      }
      expect(director.obstacleScrollSpeed, lessThan(20));
      director.setEmp(false);
      for (var i = 0; i < 80; i++) {
        director.update(8, .05);
      }
      expect(
        director.obstacleScrollSpeed,
        closeTo(director.difficultySpeed * .5, 8),
      );
      expect(director.worldScrollSpeed, closeTo(director.difficultySpeed * .5, 8));
    });

    test('power easing does not snap Slow Time', () {
      final director = SpeedDirector();
      director.setSlowTime(true);
      director.update(0, .05);
      expect(director.slowFactor, lessThan(1));
      expect(director.slowFactor, greaterThan(.5));
    });
  });

  group('score rules', () {
    test('composes coinBase x coinMulti x scoreMulti', () {
      const balance = GameBalance();
      expect(
        balance.coinValue(coinMultiplier: 3, scoreMultiplier: 2),
        6,
      );
      expect(
        balance.coinValue(coinMultiplier: 1, scoreMultiplier: 1),
        1,
      );
    });

    test('Double Score only boosts survival while active', () {
      final score = ScoreAccumulator();
      score.tickSurvival(8, 1);
      score.tickSurvival(2, 2);
      expect(score.total, 12);
    });

    test('frozen scoreboard ignores later ticks and coins', () {
      final score = ScoreAccumulator();
      score.tickSurvival(5, 1);
      score.frozen = true;
      score.tickSurvival(10, 2);
      expect(score.collectCoin(coinMultiplier: 3, scoreMultiplier: 2), 0);
      expect(score.total, 5);
    });
  });

  group('power matrix', () {
    test('independent timers expire separately', () {
      final powers = PowerController();
      powers.activate(PowerId.shield);
      powers.activate(PowerId.doubleScore);
      powers.update(6.1, timersFrozen: false);
      expect(powers.has(PowerId.shield), isFalse);
      expect(powers.has(PowerId.doubleScore), isFalse);
    });

    test('timers freeze while paused', () {
      final powers = PowerController();
      powers.activate(PowerId.magnet);
      powers.update(3, timersFrozen: true);
      expect(powers.active[PowerId.magnet]!.remaining, 6);
    });

    test('cloak prevents shield consumption', () {
      final powers = PowerController();
      powers.activate(PowerId.shield);
      powers.activate(PowerId.invisibility);
      expect(powers.resolveHazardHit(), CollisionResult.ignored);
      expect(powers.hasShield, isTrue);
    });

    test('phase dash is invulnerable without stacking cloak', () {
      final powers = PowerController();
      powers.activate(PowerId.phaseDash);
      expect(powers.invulnerable, isTrue);
      expect(powers.cloaked, isFalse);
      expect(powers.resolveHazardHit(), CollisionResult.ignored);
    });

    test('shield absorbs one hit then breaks', () {
      final powers = PowerController();
      powers.activate(PowerId.shield);
      expect(powers.resolveHazardHit(), CollisionResult.shieldBreak);
      expect(powers.hasShield, isFalse);
      expect(powers.resolveHazardHit(), CollisionResult.death);
    });

    test('multipliers compose for coins and survival', () {
      final powers = PowerController();
      powers.activate(PowerId.doubleScore);
      powers.activate(PowerId.coinMultiplier);
      expect(powers.scoreMultiplier, 2);
      expect(powers.coinMultiplier, 3);
      final score = ScoreAccumulator();
      expect(
        score.collectCoin(
          coinMultiplier: powers.coinMultiplier,
          scoreMultiplier: powers.scoreMultiplier,
        ),
        6,
      );
    });
  });

  group('pause matrix', () {
    test('resume from pause enters resuming, never playing', () {
      final flow = SessionFlow();
      flow.enterPlaying();
      expect(flow.requestPause(), isTrue);
      expect(flow.phase, GamePhase.paused);
      flow.resumeFromPause();
      expect(flow.phase, GamePhase.resuming);
      expect(flow.simulationRunning, isFalse);
      expect(flow.timersFrozen, isTrue);
    });

    test('countdown and resuming auto-pause', () {
      final flow = SessionFlow();
      flow.startCountdown();
      expect(flow.onAppInactive(), isTrue);
      expect(flow.phase, GamePhase.paused);
      flow.resumeFromPause();
      expect(flow.onAppInactive(), isTrue);
      expect(flow.phase, GamePhase.paused);
    });

    test('frame clock drops the resume delta then clamps spikes', () {
      final clock = FrameClock();
      clock.armResume();
      expect(clock.clamp(8), 0);
      expect(clock.clamp(1.4), 0.05);
    });
  });

  group('player control', () {
    test('keeps collision Y fixed while approaching target X', () {
      final player = PlayerController(x: 100, baseY: 640);
      player.setDragX(240);
      player.update(0.05, maxSpeed: 540, minX: 40, maxX: 360);
      expect(player.baseY, 640);
      expect(player.x, greaterThan(100));
      expect(player.x, lessThanOrEqualTo(240));
    });

    test('phase dash only scales horizontal speed', () {
      final powers = PowerController();
      powers.activate(PowerId.phaseDash);
      expect(powers.moveScale, closeTo(1.3, .0001));
    });
  });

  group('rarity table', () {
    test('does not spawn powers equally', () {
      final table = PowerRarityTable();
      final rng = math.Random(7);
      final counts = <PowerRarity, int>{};
      for (var i = 0; i < 4000; i++) {
        final id = table.pick(rng, 0);
        final rarity = powerDefinitions[id]!.rarity;
        counts[rarity] = (counts[rarity] ?? 0) + 1;
      }
      expect(counts[PowerRarity.common]!, greaterThan(counts[PowerRarity.rare]!));
      expect(
        counts[PowerRarity.uncommon]!,
        greaterThan(counts[PowerRarity.veryRare]!),
      );
    });

    test('rare weights tick up with survival time', () {
      const table = PowerRarityTable();
      expect(table.weightFor(PowerRarity.rare, 0), 15);
      expect(table.weightFor(PowerRarity.rare, 180), 17);
      expect(table.weightFor(PowerRarity.common, 180), 50);
    });
  });

  group('object pool', () {
    test('reuses instances and stays bounded', () {
      final pool = ObjectPool<int>(capacity: 3);
      pool.release(1);
      pool.release(2);
      pool.release(3);
      pool.release(4);
      expect(pool.available, 3);
      expect(pool.acquire(() => -1), 3);
      expect(pool.available, 2);
    });
  });

  group('turbo collect path', () {
    test('curves toward the ship instead of a straight line', () {
      final a = turboCollectVelocity(
        from: const Offset(0, 0),
        to: const Offset(0, 100),
        pulse: 0.4,
        radius: 120,
      );
      final b = turboCollectVelocity(
        from: const Offset(0, 0),
        to: const Offset(0, 100),
        pulse: 1.1,
        radius: 120,
      );
      expect(a.dx, isNot(closeTo(b.dx, .01)));
      expect(a.dy, greaterThan(0));
    });
  });

  group('obstacle catalog', () {
    test('every obstacle type has a definition', () {
      for (final type in ObstacleType.values) {
        expect(obstacleDefinitions[type], isNotNull);
      }
    });

    test('difficulty book withholds late hazards during the intro', () {
      const book = DifficultyPhaseBook();
      expect(book.typesFor(0), [ObstacleType.wall]);
      expect(book.typesFor(3), contains(ObstacleType.narrowWindow));
      expect(book.typesFor(4), contains(ObstacleType.breakableWall));
    });
  });
}
