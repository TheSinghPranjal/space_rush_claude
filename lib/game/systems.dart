import 'dart:math' as math;
import 'dart:ui';

import 'config.dart';
import 'models.dart';

class FrameClock {
  FrameClock({this.maxDt = 0.05});

  final double maxDt;
  bool dropNext = false;

  double clamp(double dt) {
    if (dropNext) {
      dropNext = false;
      return 0;
    }
    if (dt.isNaN || dt.isNegative) return 0;
    return dt.clamp(0.0, maxDt);
  }

  void armResume() => dropNext = true;
}

class ScoreAccumulator {
  ScoreAccumulator({this.balance = GameBalance.survival});

  final GameBalance balance;
  double survivalPoints = 0;
  int coinPoints = 0;
  int coinsCollected = 0;
  bool frozen = false;

  void reset() {
    survivalPoints = 0;
    coinPoints = 0;
    coinsCollected = 0;
    frozen = false;
  }

  void tickSurvival(double dt, double scoreMultiplier) {
    if (frozen) return;
    survivalPoints += dt * scoreMultiplier;
  }

  int collectCoin({
    required double coinMultiplier,
    required double scoreMultiplier,
  }) {
    if (frozen) return 0;
    final value = balance
        .coinValue(
          coinMultiplier: coinMultiplier,
          scoreMultiplier: scoreMultiplier,
        )
        .round();
    coinPoints += value;
    coinsCollected++;
    return value;
  }

  int get total => coinPoints + survivalPoints.floor();
}

class SpeedDirector {
  SpeedDirector({
    DifficultyManager? difficulty,
    this.balance = GameBalance.survival,
  }) : difficulty = difficulty ?? DifficultyManager();

  final DifficultyManager difficulty;
  final GameBalance balance;

  double slowFactor = 1;
  double empFactor = 1;
  double _targetSlow = 1;
  double _targetEmp = 1;

  void reset() {
    difficulty.reset();
    slowFactor = 1;
    empFactor = 1;
    _targetSlow = 1;
    _targetEmp = 1;
  }

  void setSlowTime(bool active) {
    _targetSlow = active ? balance.slowTimeFactor : 1;
  }

  void setEmp(bool active) {
    _targetEmp = active ? balance.empObstacleFactor : 1;
  }

  void update(double elapsed, double dt) {
    difficulty.update(elapsed, dt);
    slowFactor = _ease(
      slowFactor,
      _targetSlow,
      dt,
      balance.powerEaseSeconds,
    );
    final empSeconds = _targetEmp >= empFactor
        ? balance.empRecoverySeconds
        : balance.powerEaseSeconds;
    empFactor = _ease(empFactor, _targetEmp, dt, empSeconds);
  }

  double get difficultySpeed => difficulty.currentDifficultySpeed;

  /// Coins, pickups, and parallax keep moving during EMP.
  double get worldScrollSpeed => difficultySpeed * slowFactor;

  /// Obstacles freeze while EMP is in effect; Slow Time applies after EMP.
  double get obstacleScrollSpeed => worldScrollSpeed * empFactor;

  /// Extra world-Y translation so frozen obstacles stay put on screen.
  double get obstacleHoldSpeed => worldScrollSpeed - obstacleScrollSpeed;

  static double _ease(double current, double target, double dt, double seconds) {
    if (seconds <= 0) return target;
    final t = math.min(1, dt / seconds * 3);
    return current + (target - current) * t;
  }
}

class PowerController {
  PowerController({this.balance = GameBalance.survival});

  final GameBalance balance;
  final Map<PowerId, ActivePower> active = {};
  int activations = 0;

  void reset() {
    active.clear();
    activations = 0;
  }

  bool has(PowerId id) => active.containsKey(id);

  bool get hasShield => has(PowerId.shield);
  bool get cloaked => has(PowerId.invisibility);
  bool get dashing => has(PowerId.phaseDash);
  bool get invulnerable => cloaked || dashing;

  double get scoreMultiplier =>
      has(PowerId.doubleScore) ? balance.doubleScoreMultiplier : 1;
  double get coinMultiplier =>
      has(PowerId.coinMultiplier) ? balance.coinPowerMultiplier : 1;
  double get pickupRadius =>
      has(PowerId.turboCollect)
          ? balance.turboPickupRadius
          : balance.normalPickupRadius;
  double get moveScale =>
      has(PowerId.phaseDash) ? balance.phaseDashMoveScale : 1;

  void activate(PowerId id) {
    final definition = powerDefinitions[id]!;
    active[id] = ActivePower(id, definition.duration);
    activations++;
  }

  List<PowerId> update(double dt, {required bool timersFrozen}) {
    if (timersFrozen) return const [];
    final expired = <PowerId>[];
    for (final power in active.values) {
      power.remaining -= dt;
      if (power.remaining <= 0) expired.add(power.id);
    }
    for (final id in expired) {
      active.remove(id);
    }
    return expired;
  }

  CollisionResult resolveHazardHit() {
    if (invulnerable) return CollisionResult.ignored;
    if (hasShield) {
      active.remove(PowerId.shield);
      return CollisionResult.shieldBreak;
    }
    return CollisionResult.death;
  }

  List<ActivePower> snapshot() => active.values
      .map((power) => ActivePower(power.id, power.remaining))
      .toList(growable: false);
}

enum CollisionResult { ignored, shieldBreak, death }

class PlayerController {
  PlayerController({this.baseY = 0, this.x = 0});

  double x;
  double baseY;
  double targetX = 0;

  Offset get position => Offset(x, baseY);

  void place(double nextX, double y) {
    x = nextX;
    targetX = nextX;
    baseY = y;
  }

  void setDragX(double nextX) => targetX = nextX;

  void update(
    double dt, {
    required double maxSpeed,
    required double minX,
    required double maxX,
  }) {
    final desired = targetX.clamp(minX, maxX).toDouble();
    final maxMove = maxSpeed * dt;
    final delta = (desired - x).clamp(-maxMove, maxMove);
    x = (x + delta).clamp(minX, maxX).toDouble();
    targetX = desired;
  }
}

class SessionFlow {
  GamePhase phase = GamePhase.home;

  bool get isPlaying => phase == GamePhase.playing;
  bool get acceptSteer => phase == GamePhase.playing;
  bool get simulationRunning => phase == GamePhase.playing;
  bool get timersFrozen => phase != GamePhase.playing;
  bool get canPause =>
      phase == GamePhase.playing ||
      phase == GamePhase.countdown ||
      phase == GamePhase.resuming;
  bool get showsPlayHud =>
      phase == GamePhase.playing ||
      phase == GamePhase.countdown ||
      phase == GamePhase.resuming;

  bool requestPause() {
    if (!canPause) return false;
    phase = GamePhase.paused;
    return true;
  }

  void startCountdown() => phase = GamePhase.countdown;

  void resumeFromPause() => phase = GamePhase.resuming;

  void enterPlaying() => phase = GamePhase.playing;

  void enterGameOver() => phase = GamePhase.gameOver;

  void enterHome() => phase = GamePhase.home;

  bool onAppInactive() => requestPause();
}

class PowerRarityTable {
  const PowerRarityTable({this.weights = GameBalance.rarityWeights});

  final Map<PowerRarity, int> weights;

  int weightFor(PowerRarity rarity, double elapsed) {
    var weight = weights[rarity] ?? 0;
    if (rarity == PowerRarity.rare || rarity == PowerRarity.veryRare) {
      weight += elapsed ~/ 90;
    }
    return math.max(0, weight);
  }

  PowerId pick(math.Random random, double elapsed) {
    final buckets = <(PowerRarity, int)>[];
    var total = 0;
    for (final rarity in PowerRarity.values) {
      final weight = weightFor(rarity, elapsed);
      buckets.add((rarity, weight));
      total += weight;
    }
    if (total <= 0) return PowerId.magnet;
    var ticket = random.nextInt(total);
    late PowerRarity chosen;
    for (final bucket in buckets) {
      ticket -= bucket.$2;
      if (ticket < 0) {
        chosen = bucket.$1;
        break;
      }
    }
    final options = powerDefinitions.values
        .where((definition) => definition.rarity == chosen)
        .map((definition) => definition.id)
        .toList(growable: false);
    if (options.isEmpty) return PowerId.magnet;
    return options[random.nextInt(options.length)];
  }
}

class AudioBus {
  final List<GameSfx> events = [];
  void Function(GameSfx event)? onPlay;

  void play(GameSfx event) {
    events.add(event);
    if (events.length > 64) events.removeRange(0, events.length - 64);
    onPlay?.call(event);
  }

  void reset() => events.clear();
}

class AnalyticsBus {
  final List<(GameAnalyticsEvent, Map<String, Object?>)> events = [];
  void Function(GameAnalyticsEvent event, Map<String, Object?> props)? onEvent;

  void emit(GameAnalyticsEvent event, [Map<String, Object?> props = const {}]) {
    events.add((event, props));
    onEvent?.call(event, props);
  }

  void reset() => events.clear();
}

class ObjectPool<T> {
  ObjectPool({this.capacity = 64});

  final int capacity;
  final List<T> _free = [];

  int get available => _free.length;

  T acquire(T Function() create) {
    if (_free.isEmpty) return create();
    return _free.removeLast();
  }

  void release(T item) {
    if (_free.length < capacity) _free.add(item);
  }

  void clear() => _free.clear();
}

class DifficultyPhaseBook {
  const DifficultyPhaseBook();

  int phaseIndex(double elapsed) {
    if (elapsed < 20) return 0;
    if (elapsed < 60) return 1;
    if (elapsed < 120) return 2;
    if (elapsed < 240) return 3;
    return 4;
  }

  List<ObstacleType> typesFor(int phase) => [
    ObstacleType.wall,
    if (phase >= 1) ObstacleType.laserGate,
    if (phase >= 1) ObstacleType.asteroidCluster,
    if (phase >= 2) ObstacleType.mineField,
    if (phase >= 2) ObstacleType.piston,
    if (phase >= 3) ObstacleType.rotatingBar,
    if (phase >= 3) ObstacleType.electricField,
    if (phase >= 3) ObstacleType.splitWall,
    if (phase >= 3) ObstacleType.narrowWindow,
    if (phase >= 4) ObstacleType.zigzag,
    if (phase >= 4) ObstacleType.breakableWall,
  ];
}

bool rotatedRectOverlaps(Rect bar, double rotation, Rect other) {
  bool sat(Rect a, double rotA, Rect b, double rotB) {
    final axes = <Offset>[
      _axis(rotA, 1, 0),
      _axis(rotA, 0, 1),
      _axis(rotB, 1, 0),
      _axis(rotB, 0, 1),
    ];
    final cornersA = _corners(a, rotA);
    final cornersB = _corners(b, rotB);
    for (final axis in axes) {
      final projA = _project(cornersA, axis);
      final projB = _project(cornersB, axis);
      if (projA.$2 < projB.$1 || projB.$2 < projA.$1) return false;
    }
    return true;
  }

  return sat(bar, rotation, other, 0);
}

Offset _axis(double rotation, double x, double y) {
  final c = math.cos(rotation);
  final s = math.sin(rotation);
  return Offset(x * c - y * s, x * s + y * c);
}

List<Offset> _corners(Rect rect, double rotation) {
  final c = math.cos(rotation);
  final s = math.sin(rotation);
  final cx = rect.center.dx;
  final cy = rect.center.dy;
  final locals = <Offset>[
    Offset(-rect.width / 2, -rect.height / 2),
    Offset(rect.width / 2, -rect.height / 2),
    Offset(rect.width / 2, rect.height / 2),
    Offset(-rect.width / 2, rect.height / 2),
  ];
  return [
    for (final local in locals)
      Offset(cx + local.dx * c - local.dy * s, cy + local.dx * s + local.dy * c),
  ];
}

(double, double) _project(List<Offset> corners, Offset axis) {
  var min = double.infinity;
  var max = -double.infinity;
  for (final corner in corners) {
    final d = corner.dx * axis.dx + corner.dy * axis.dy;
    if (d < min) min = d;
    if (d > max) max = d;
  }
  return (min, max);
}

Offset turboCollectVelocity({
  required Offset from,
  required Offset to,
  required double pulse,
  required double radius,
}) {
  final delta = to - from;
  final distance = delta.distance;
  if (distance < 1) return Offset.zero;
  final dir = delta / distance;
  final perp = Offset(-dir.dy, dir.dx);
  final curve = math.sin(pulse * 2.2) * .62;
  final rush = 340 + (1 - (distance / math.max(radius, 1)).clamp(0.0, 1.0)) * 520;
  return (dir + perp * curve) * rush;
}
