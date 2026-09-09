import 'models.dart';

/// Tunable balance for the endless survival mode. Future modes can supply
/// a different [GameBalance] without rewriting entity code.
class GameBalance {
  const GameBalance();

  static const GameBalance survival = GameBalance();

  final double baseSpeed = 220;
  final double difficultyStep = 1.1;
  final double difficultyInterval = 60;
  final double difficultyBlendSeconds = 1.5;
  final double slowTimeFactor = .5;
  final double empObstacleFactor = 0;
  final double powerEaseSeconds = .45;
  final double empRecoverySeconds = 1.2;
  final double coinBase = 1;
  final double doubleScoreMultiplier = 2;
  final double coinPowerMultiplier = 3;
  final double normalPickupRadius = 38;
  final double turboPickupRadius = 120;
  final double magnetRadius = 190;
  final double phaseDashMoveScale = 1.3;
  final double maxSimulationDt = .05;
  final double pauseSlowdownSeconds = .22;
  final double startCountdown = 3.4;
  final double resumeCountdown = 2.2;
  final double powerMinInterval = 8.5;
  final int maxPickups = 3;
  final int maxObstacles = 24;
  final int maxCoins = 70;
  final int maxBullets = 18;
  final int maxParticles = 120;
  final int maxFloatingTexts = 9;
  final int poolCapacity = 96;
  final double powerWarnSeconds = 2;
  final double edgeMarginFactor = .12;

  static const Map<PowerRarity, int> rarityWeights = {
    PowerRarity.common: 50,
    PowerRarity.uncommon: 30,
    PowerRarity.rare: 15,
    PowerRarity.veryRare: 5,
  };

  double coinValue({
    required double coinMultiplier,
    required double scoreMultiplier,
  }) =>
      coinBase * coinMultiplier * scoreMultiplier;
}

enum GameMode { survival }

enum GameSfx {
  coin,
  power,
  shieldBreak,
  death,
  nearMiss,
  pause,
  resume,
  countdown,
  highScore,
  button,
  emp,
  gun,
}

enum GameAnalyticsEvent {
  runStart,
  runEnd,
  powerPickup,
  death,
  pause,
  resume,
  restart,
}
