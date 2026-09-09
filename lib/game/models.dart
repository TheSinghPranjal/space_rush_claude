import 'dart:math' as math;
import 'dart:ui';

enum GamePhase { home, countdown, playing, paused, gameOver }

enum PowerId {
  magnet,
  gun,
  invisibility,
  slowTime,
  shield,
  doubleScore,
  coinMultiplier,
  emp,
  turboCollect,
  phaseDash,
}

enum PowerRarity { common, uncommon, rare, veryRare }

enum ObstacleType {
  wall,
  laserGate,
  asteroidCluster,
  mineField,
  piston,
  rotatingBar,
  electricField,
  splitWall,
  zigzag,
  breakableWall,
}

enum ObstacleMaterial { metal, energy, crystal, asteroid, laser, electric }

class PowerDefinition {
  const PowerDefinition({
    required this.id,
    required this.label,
    required this.symbol,
    required this.color,
    required this.duration,
    required this.rarity,
  });

  final PowerId id;
  final String label;
  final String symbol;
  final Color color;
  final double duration;
  final PowerRarity rarity;
}

const Map<PowerId, PowerDefinition> powerDefinitions = {
  PowerId.magnet: PowerDefinition(
    id: PowerId.magnet,
    label: 'MAGNET',
    symbol: '⌁',
    color: Color(0xff2de3ff),
    duration: 6,
    rarity: PowerRarity.common,
  ),
  PowerId.gun: PowerDefinition(
    id: PowerId.gun,
    label: 'PLASMA GUN',
    symbol: '✦',
    color: Color(0xffff7d45),
    duration: 6,
    rarity: PowerRarity.uncommon,
  ),
  PowerId.invisibility: PowerDefinition(
    id: PowerId.invisibility,
    label: 'CLOAK',
    symbol: '◌',
    color: Color(0xff6dff9c),
    duration: 6,
    rarity: PowerRarity.uncommon,
  ),
  PowerId.slowTime: PowerDefinition(
    id: PowerId.slowTime,
    label: 'SLOW TIME',
    symbol: '◷',
    color: Color(0xff8d8cff),
    duration: 6,
    rarity: PowerRarity.uncommon,
  ),
  PowerId.shield: PowerDefinition(
    id: PowerId.shield,
    label: 'SHIELD ACTIVE',
    symbol: '⬡',
    color: Color(0xff39efd1),
    duration: 6,
    rarity: PowerRarity.common,
  ),
  PowerId.doubleScore: PowerDefinition(
    id: PowerId.doubleScore,
    label: 'DOUBLE SCORE',
    symbol: '×2',
    color: Color(0xffffc94a),
    duration: 6,
    rarity: PowerRarity.rare,
  ),
  PowerId.coinMultiplier: PowerDefinition(
    id: PowerId.coinMultiplier,
    label: 'COIN MULTI ×3',
    symbol: '×3',
    color: Color(0xffffdd54),
    duration: 6,
    rarity: PowerRarity.rare,
  ),
  PowerId.emp: PowerDefinition(
    id: PowerId.emp,
    label: 'EMP FREEZE',
    symbol: 'ϟ',
    color: Color(0xffb678ff),
    duration: 3,
    rarity: PowerRarity.rare,
  ),
  PowerId.turboCollect: PowerDefinition(
    id: PowerId.turboCollect,
    label: 'TURBO COLLECT',
    symbol: '◎',
    color: Color(0xfff7f8ff),
    duration: 6,
    rarity: PowerRarity.veryRare,
  ),
  PowerId.phaseDash: PowerDefinition(
    id: PowerId.phaseDash,
    label: 'PHASE DASH',
    symbol: '◇',
    color: Color(0xffc5f8ff),
    duration: 2.5,
    rarity: PowerRarity.veryRare,
  ),
};

class ActivePower {
  ActivePower(this.id, this.remaining);
  final PowerId id;
  double remaining;
}

/// Gameplay objects that scroll with the world store coordinates in world space.
/// Screen position is derived as `worldPosition - cameraOffset`.
class RectEntity {
  RectEntity(Rect rect, {Offset? velocity})
    : worldRect = rect,
      velocity = velocity ?? Offset.zero;

  Rect worldRect;
  Offset velocity;
  bool alive = true;

  Rect get rect => worldRect;
  set rect(Rect value) => worldRect = value;

  Offset get worldPosition => worldRect.center;
  set worldPosition(Offset value) {
    worldRect = Rect.fromCenter(
      center: value,
      width: worldRect.width,
      height: worldRect.height,
    );
  }

  void translateWorld(Offset delta) {
    worldRect = worldRect.shift(delta);
  }

  void advance(double deltaTime) {
    worldRect = worldRect.translate(
      velocity.dx * deltaTime,
      velocity.dy * deltaTime,
    );
  }
}

/// Converts between fixed screen coordinates (player, HUD) and scrolling world space.
class WorldCamera {
  const WorldCamera({required this.offset});

  final Offset offset;

  Offset worldToScreen(Offset worldPosition) {
    return worldPosition - offset;
  }

  Rect worldRectToScreen(Rect worldRect) {
    return worldRect.shift(-offset);
  }

  Offset screenToWorld(Offset screenPosition) {
    return screenPosition + offset;
  }
}

class Coin extends RectEntity {
  Coin(Rect rect, {this.attracting = false, Offset? velocity})
    : super(rect, velocity: velocity);
  bool attracting;
  double pulse = 0;
}

class Bullet extends RectEntity {
  Bullet(super.rect);
  double trail = 0;
}

class PowerPickup extends RectEntity {
  PowerPickup(super.rect, this.id);
  final PowerId id;
  double age = 0;
}

class ObstacleSegment extends RectEntity {
  ObstacleSegment(
    super.rect, {
    required this.material,
    required this.health,
    this.dangerous = true,
  });
  final ObstacleMaterial material;
  int health;
  bool dangerous;
  double damageFlash = 0;
}

class ObstacleGroup {
  ObstacleGroup({
    required this.type,
    required this.segments,
    required this.gapCenter,
    required this.spawnY,
    this.rotation = 0,
  });
  final ObstacleType type;
  final List<ObstacleSegment> segments;
  final double gapCenter;
  final double spawnY;
  double rotation;
  double age = 0;
  bool nearMissReported = false;
}

class Particle {
  Particle(
    this.position,
    this.velocity,
    this.color,
    this.life, {
    this.size = 3,
  });
  Offset position;
  final Offset velocity;
  final Color color;
  double life;
  final double size;
}

class FloatingText {
  FloatingText(this.text, this.position, this.color);
  final String text;
  Offset position;
  final Color color;
  double life = .75;
}

class GameSnapshot {
  const GameSnapshot({
    required this.phase,
    required this.score,
    required this.coins,
    required this.elapsed,
    required this.bestScore,
    required this.speed,
    required this.activePowers,
    required this.powersUsed,
    required this.destroyed,
    required this.newBest,
    this.countdown = '',
    this.banner = '',
  });
  final GamePhase phase;
  final int score;
  final int coins;
  final double elapsed;
  final int bestScore;
  final double speed;
  final List<ActivePower> activePowers;
  final int powersUsed;
  final int destroyed;
  final bool newBest;
  final String countdown;
  final String banner;
}

class DifficultyManager {
  DifficultyManager({this.baseSpeed = 220, this.transitionSeconds = 1.5});
  final double baseSpeed;
  final double transitionSeconds;
  double currentDifficultySpeed = 220;
  double targetDifficultySpeed = 220;

  void reset() {
    currentDifficultySpeed = baseSpeed;
    targetDifficultySpeed = baseSpeed;
  }

  double update(double elapsed, double dt) {
    final level = elapsed ~/ 60;
    targetDifficultySpeed = baseSpeed * math.pow(1.1, level);
    final rate = math.min(1, dt / transitionSeconds);
    currentDifficultySpeed +=
        (targetDifficultySpeed - currentDifficultySpeed) * rate;
    return currentDifficultySpeed;
  }

  double multiplierAt(double seconds) =>
      math.pow(1.1, seconds ~/ 60).toDouble();
}

class PlayabilityValidator {
  const PlayabilityValidator();
  static const double shipWidth = 46;
  static const double safetyMargin = 28;
  static const double shipSpeed = 540;

  bool isReachable({
    required double fromX,
    required double gapCenter,
    required double gapWidth,
    required double distance,
    required double speed,
  }) {
    if (gapWidth < shipWidth + safetyMargin) return false;
    final reactionTime = distance / math.max(speed, 1);
    final maxTravel = shipSpeed * reactionTime * .84;
    return (gapCenter - fromX).abs() <=
        maxTravel + gapWidth / 2 - shipWidth / 2;
  }
}

enum CoinPattern { single, diagonal, arc, zigzag, horizontal }

class CoinSpawnPlanner {
  const CoinSpawnPlanner();

  static const double radius = 9;
  static const double visualSpacing = 22;
  static const double minimumCenterDistance = radius * 2 + visualSpacing;
  static const double patternSpawnGap = minimumCenterDistance * 1.35;

  List<Offset> offsetsFor(CoinPattern pattern) {
    final step = minimumCenterDistance;
    return switch (pattern) {
      CoinPattern.single => const [Offset.zero],
      CoinPattern.diagonal => [
        Offset(-step * 1.4, 0),
        Offset(-step * .45, step * .95),
        Offset(step * .45, step * 1.9),
        Offset(step * 1.4, step * 2.85),
      ],
      CoinPattern.arc => [
        Offset(-step * 2, step * .85),
        Offset(-step, step * .28),
        Offset.zero,
        Offset(step, step * .28),
        Offset(step * 2, step * .85),
      ],
      CoinPattern.zigzag => [
        Offset(-step * .65, 0),
        Offset(step * .65, step),
        Offset(-step * .65, step * 2),
        Offset(step * .65, step * 3),
        Offset(-step * .65, step * 4),
      ],
      CoinPattern.horizontal => [
        Offset(-step * 1.5, 0),
        Offset(-step * .5, 0),
        Offset(step * .5, 0),
        Offset(step * 1.5, 0),
      ],
    };
  }

  double patternDepth(CoinPattern pattern) {
    final offsets = offsetsFor(pattern);
    if (offsets.isEmpty) return 0;
    final maxY = offsets.map((offset) => offset.dy).reduce(math.max);
    return maxY;
  }

  bool isSeparated(Offset candidate, Iterable<Offset> existing) =>
      existing.every(
        (position) => (candidate - position).distance >= minimumCenterDistance,
      );

  bool patternFits({
    required Offset anchor,
    required CoinPattern pattern,
    required Rect spawnBounds,
    required Iterable<Offset> existing,
    required Iterable<Rect> blockedRects,
  }) {
    for (final offset in offsetsFor(pattern)) {
      final position = anchor + offset;
      if (!spawnBounds.contains(position)) return false;
      if (!isSeparated(position, existing)) return false;
      for (final blocked in blockedRects) {
        if (blocked.contains(position)) return false;
      }
    }
    return true;
  }
}
