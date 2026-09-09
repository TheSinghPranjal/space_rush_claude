import 'dart:async';
import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class SpaceSurvivalGame extends FlameGame with PanDetector {
  SpaceSurvivalGame({required this.onSnapshot}) : super();

  final ValueChanged<GameSnapshot> onSnapshot;
  final DifficultyManager difficulty = DifficultyManager();
  final PlayabilityValidator validator = const PlayabilityValidator();
  final math.Random _random = math.Random();
  final List<ObstacleGroup> obstacles = [];
  final List<Coin> coins = [];
  final List<PowerPickup> pickups = [];
  final List<Bullet> bullets = [];
  final List<Particle> particles = [];
  final List<FloatingText> floatingTexts = [];
  final List<Offset> _stars = [];
  final Map<PowerId, ActivePower> _powers = {};
  final CoinSpawnPlanner _coinPlanner = const CoinSpawnPlanner();

  GamePhase phase = GamePhase.home;
  Offset playerPosition = Offset.zero;
  Offset playerTargetPosition = Offset.zero;
  double _worldDistance = 0;
  double _worldSpeed = 220;
  double _nextCoinSpawnScrollY = 0;
  double _elapsed = 0;
  double _spawnClock = 0;
  double _coinClock = 0;
  double _powerClock = 0;
  double _gunClock = 0;
  double _countdown = 0;
  double _starOffset = 0;
  double _effectSpeed = 220;
  double _lastRouteX = 0;
  double _impact = 0;
  double _bannerLife = 0;
  String _banner = '';
  int score = 0;
  int collectedCoins = 0;
  int bestScore = 0;
  int powersUsed = 0;
  int destroyed = 0;
  bool hapticsEnabled = true;
  bool _newBest = false;
  bool _loadedStorage = false;

  static const int maxObstacles = 24;
  static const int maxCoins = 70;
  static const int maxPickups = 5;
  static const int maxBullets = 18;
  static const int maxParticles = 120;
  static const double coinRadius = 9;
  static const double coinSpacing = 22;

  bool get isPlaying => phase == GamePhase.playing;
  Offset get ship => playerPosition;
  set ship(Offset value) => playerPosition = value;
  double get targetShipX => playerTargetPosition.dx;
  set targetShipX(double value) =>
      playerTargetPosition = Offset(value, playerTargetPosition.dy);
  Rect get playableArea {
    final horizontalInset = math.max(20.0, size.x * .045);
    final hudClearance = math.max(132.0, size.y * .17);
    final bottomInset = math.max(24.0, size.y * .04);
    return Rect.fromLTRB(
      horizontalInset,
      hudClearance,
      size.x - horizontalInset,
      size.y - bottomInset,
    );
  }
  bool get hasShield => _powers.containsKey(PowerId.shield);
  bool get invulnerable =>
      _powers.containsKey(PowerId.invisibility) ||
      _powers.containsKey(PowerId.phaseDash);
  double get scoreMultiplier =>
      _powers.containsKey(PowerId.doubleScore) ? 2 : 1;
  double get coinMultiplier =>
      _powers.containsKey(PowerId.coinMultiplier) ? 3 : 1;
  double get pickupRadius =>
      _powers.containsKey(PowerId.turboCollect) ? 120 : 38;
  double get playerSpeed =>
      PlayabilityValidator.shipSpeed *
      (_powers.containsKey(PowerId.phaseDash) ? 1.3 : 1);
  double get obstacleTargetSpeed {
    if (_powers.containsKey(PowerId.emp)) return 0;
    return difficulty.currentDifficultySpeed *
        (_powers.containsKey(PowerId.slowTime) ? .5 : 1);
  }

  double get minimumCoinDistance => coinRadius * 2 + coinSpacing;

  int get displayedScore {
    final survivalScore = (_elapsed * scoreMultiplier).floor();
    return score + (phase == GamePhase.playing ? survivalScore : 0);
  }

  WorldCamera get _camera => WorldCamera(
    offset: Offset(0, _worldDistance),
  );

  Offset _worldToScreen(Offset position) {
    return _camera.worldToScreen(position);
  }

  Rect _worldRectToScreen(Rect worldRect) {
    return _camera.worldRectToScreen(worldRect);
  }

  double _worldYForSpawn(double screenY) {
    return _camera.screenToWorld(Offset(0, screenY)).dy;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final prefs = await SharedPreferences.getInstance();
    bestScore = prefs.getInt('space_survival_best') ?? 0;
    hapticsEnabled = prefs.getBool('space_survival_haptics') ?? true;
    _loadedStorage = true;
    _emit();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    if (ship == Offset.zero) {
      ship = Offset(playableArea.center.dx, playableArea.bottom - playableArea.height * .18);
      playerTargetPosition = ship;
      _lastRouteX = ship.dx;
    } else {
      ship = _clampPlayerPosition(ship);
      playerTargetPosition = _clampPlayerPosition(playerTargetPosition);
    }
    if (_stars.isEmpty) {
      for (var index = 0; index < 95; index++) {
        _stars.add(
          Offset(_random.nextDouble() * size.x, _random.nextDouble() * size.y),
        );
      }
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (!isPlaying) return;
    playerTargetPosition = _clampPlayerPosition(info.eventPosition.widget.toOffset());
  }

  void start() {
    resetRun();
    phase = GamePhase.countdown;
    _countdown = 3.4;
    _banner = 'SYSTEMS READY';
    _bannerLife = 1.2;
    _emit();
  }

  void restart() => start();

  void returnHome() {
    phase = GamePhase.home;
    _emit();
  }

  void requestPause() {
    if (!isPlaying) return;
    phase = GamePhase.paused;
    _emit();
  }

  void resume() {
    if (phase != GamePhase.paused) return;
    phase = GamePhase.countdown;
    _countdown = 2.2;
    _banner = 'READY';
    _bannerLife = 1.0;
    _emit();
  }

  void onAppInactive() {
    if (isPlaying || phase == GamePhase.countdown) requestPause();
  }

  Future<void> toggleHaptics() async {
    hapticsEnabled = !hapticsEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('space_survival_haptics', hapticsEnabled);
    _emit();
  }

  void debugSpawn(PowerId id) {
    if (!isPlaying) return;
    activatePower(id);
  }

  void resetRun() {
    difficulty.reset();
    obstacles.clear();
    coins.clear();
    pickups.clear();
    bullets.clear();
    particles.clear();
    floatingTexts.clear();
    _powers.clear();
    _elapsed = 0;
    _spawnClock = 0;
    _coinClock = 0;
    _powerClock = 0;
    _gunClock = 0;
    _effectSpeed = difficulty.baseSpeed;
    _impact = 0;
    _banner = '';
    _bannerLife = 0;
    score = 0;
    collectedCoins = 0;
    powersUsed = 0;
    destroyed = 0;
    _newBest = false;
    _worldDistance = 0;
    _worldSpeed = 220;
    _nextCoinSpawnScrollY = 0;
    ship = Offset(playableArea.center.dx, playableArea.bottom - playableArea.height * .18);
    playerTargetPosition = ship;
    _lastRouteX = ship.dx;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final safeDt = dt.clamp(0.0, .05);
    if (phase == GamePhase.home) {
      _starOffset += safeDt * 8;
      return;
    }
    if (phase == GamePhase.countdown) {
      _starOffset += safeDt * 12;
      _countdown -= safeDt;
      if (_countdown <= 0) {
        phase = GamePhase.playing;
        _banner = 'GO';
        _bannerLife = .65;
        _haptic(HapticFeedback.mediumImpact);
      }
      _emit();
      return;
    }
    if (!isPlaying) return;

    _elapsed += safeDt;
    difficulty.update(_elapsed, safeDt);
    _effectSpeed +=
        (obstacleTargetSpeed - _effectSpeed) * math.min(1, safeDt * 4.4);
    _starOffset += safeDt * (18 + _effectSpeed * .08);
    _updatePowers(safeDt);
    _updateShip(safeDt);
    _updateWorldScroll(safeDt);
    _updateWorld(safeDt);
    _checkCollisions();
    _cleanup();
    _bannerLife = math.max(0, _bannerLife - safeDt);
    _impact = math.max(0, _impact - safeDt * 2.8);
    _emit();
  }

  void _updatePowers(double dt) {
    final expired = <PowerId>[];
    for (final active in _powers.values) {
      active.remaining -= dt;
      if (active.remaining <= 0) expired.add(active.id);
    }
    for (final id in expired) {
      _powers.remove(id);
      _banner = '${powerDefinitions[id]!.label} ENDED';
      _bannerLife = .55;
      _burst(ship, powerDefinitions[id]!.color, 8, .5);
    }
    if (_powers.containsKey(PowerId.gun)) {
      _gunClock += dt;
      if (_gunClock > .25) {
        _gunClock = 0;
        _fireBullet();
      }
    }
  }

  void _updateShip(double dt) {
    final smoothing = math.min(1.0, dt * 11);
    final maxMove = playerSpeed * dt;
    final delta = playerTargetPosition - playerPosition;
    final xMove = delta.dx.clamp(-maxMove, maxMove) * smoothing * 1.8;
    final yMove = delta.dy.clamp(-maxMove, maxMove) * smoothing * 1.8;
    playerPosition = _clampPlayerPosition(
      playerPosition.translate(xMove, yMove),
    );
  }

  Offset _clampPlayerPosition(Offset position) {
    final bounds = playableArea;
    const horizontalRadius = 25.0;
    const verticalRadius = 31.0;
    return Offset(
      position.dx.clamp(bounds.left + horizontalRadius, bounds.right - horizontalRadius).toDouble(),
      position.dy.clamp(bounds.top + verticalRadius, bounds.bottom - verticalRadius).toDouble(),
    );
  }

  void _updateWorldScroll(double dt) {
    final scrollMultiplier = _powers.containsKey(PowerId.slowTime) ? .5 : 1.0;

    _worldSpeed = _powers.containsKey(PowerId.emp)
        ? 0
        : difficulty.currentDifficultySpeed * scrollMultiplier;

    _worldDistance += _worldSpeed * dt;
  }

  void _updateWorld(double dt) {
    _spawnClock += dt;
    _coinClock += dt;
    _powerClock += dt;
    final spawnInterval =
        (_elapsed < 20
                ? 2.4
                : _elapsed < 60
                ? 1.95
                : 1.65)
            .clamp(1.25, 2.4);
    if (_spawnClock >= spawnInterval) {
      _spawnClock = 0;
      _spawnObstacle();
    }
    if (_coinClock >= .75 && _worldDistance >= _nextCoinSpawnScrollY) {
      _coinClock = 0;
      _spawnCoinTrail();
    }
    if (_powerClock >= 8.5 && pickups.length < maxPickups) {
      _powerClock = 0;
      _spawnPickup();
    }
    for (final group in obstacles) {
      group.age += dt;
      final lateral = switch (group.type) {
        ObstacleType.piston => math.sin(group.age * 2.3) * 20 * dt,
        ObstacleType.splitWall => math.sin(group.age * 1.8) * 9 * dt,
        _ => 0.0,
      };
      if (group.type == ObstacleType.rotatingBar) group.rotation += dt * .9;
      for (final segment in group.segments) {
        if (lateral != 0) {
          segment.translateWorld(Offset(lateral, 0));
        }
        segment.damageFlash = math.max(0, segment.damageFlash - dt * 2);
      }
    }
    for (final coin in coins) {
      coin.pulse += dt * 5;
      final coinScreen = _worldToScreen(coin.worldPosition);
      final distance = (coinScreen - playerPosition).distance;
      if (_powers.containsKey(PowerId.magnet) && distance < 190) {
        final direction = (playerPosition - coinScreen) / math.max(distance, 1);
        coin.translateWorld(direction * 480 * dt);
        coin.attracting = true;
      } else {
        coin.attracting = false;
      }
    }
    for (final pickup in pickups) {
      pickup.age += dt;
    }
    for (final bullet in bullets) {
      bullet.trail += dt;
      bullet.velocity = const Offset(0, -820);
      bullet.advance(dt);
    }
    for (final particle in particles) {
      particle.position += particle.velocity * dt;
      particle.life -= dt;
    }
    for (final text in floatingTexts) {
      text.position = text.position.translate(0, -35 * dt);
      text.life -= dt;
    }
    _checkBulletImpacts();
  }

  void _spawnObstacle() {
    if (obstacles.length >= maxObstacles || size.x <= 0) return;
    final phaseIndex = _elapsed < 20
        ? 0
        : _elapsed < 60
        ? 1
        : _elapsed < 120
        ? 2
        : _elapsed < 240
        ? 3
        : 4;
    final candidates = <ObstacleType>[
      ObstacleType.wall,
      if (phaseIndex >= 1) ObstacleType.laserGate,
      if (phaseIndex >= 1) ObstacleType.asteroidCluster,
      if (phaseIndex >= 2) ObstacleType.mineField,
      if (phaseIndex >= 2) ObstacleType.piston,
      if (phaseIndex >= 3) ObstacleType.rotatingBar,
      if (phaseIndex >= 3) ObstacleType.electricField,
      if (phaseIndex >= 3) ObstacleType.splitWall,
      if (phaseIndex >= 4) ObstacleType.zigzag,
      if (phaseIndex >= 4) ObstacleType.breakableWall,
    ];
    final type = candidates[_random.nextInt(candidates.length)];
    const safeMargin =
        PlayabilityValidator.shipWidth + PlayabilityValidator.safetyMargin;
    final bounds = playableArea;
    final gapWidth = math.max(
      safeMargin,
      bounds.width * (_elapsed < 60 ? .31 : .25),
    );
    final maxRouteShift = math.min(bounds.width * .24, 155 + _elapsed * .12);
    final proposed =
        (_lastRouteX + (_random.nextDouble() * 2 - 1) * maxRouteShift).clamp(
          bounds.left + gapWidth / 2 + 18,
          bounds.right - gapWidth / 2 - 18,
        ).toDouble();
    final spawnScreenY = bounds.top - 90;
    final worldY = _worldYForSpawn(spawnScreenY);
    final distance = playerPosition.dy - spawnScreenY;
    final gapCenter =
        validator.isReachable(
          fromX: _lastRouteX,
          gapCenter: proposed,
          gapWidth: gapWidth,
          distance: distance,
          speed: math.max(_effectSpeed, 100),
        )
        ? proposed
        : _lastRouteX;
    _lastRouteX = gapCenter;
    const maxWallWidth = 78.0;
    const wallHeight = 40.0;
    final segments = <ObstacleSegment>[];
    final material = switch (type) {
      ObstacleType.laserGate => ObstacleMaterial.laser,
      ObstacleType.asteroidCluster ||
      ObstacleType.mineField => ObstacleMaterial.asteroid,
      ObstacleType.electricField => ObstacleMaterial.electric,
      ObstacleType.breakableWall => ObstacleMaterial.crystal,
      _ => ObstacleMaterial.metal,
    };
    final health = type == ObstacleType.breakableWall ? 2 : 1;
    final left = gapCenter - gapWidth / 2;
    final right = gapCenter + gapWidth / 2;
    if (type == ObstacleType.asteroidCluster ||
        type == ObstacleType.mineField) {
      for (final x in [
        bounds.left + bounds.width * .13,
        bounds.left + bounds.width * .33,
        bounds.left + bounds.width * .67,
        bounds.left + bounds.width * .87,
      ]) {
        if ((x - gapCenter).abs() > gapWidth * .35) {
          final radius = type == ObstacleType.mineField
              ? 17.0
              : 22 + _random.nextDouble() * 11;
          segments.add(
            ObstacleSegment(
              Rect.fromCenter(
                center: Offset(x, worldY + _random.nextDouble() * 38),
                width: radius * 2,
                height: radius * 2,
              ),
              material: material,
              health: 1,
            ),
          );
        }
      }
    } else if (type == ObstacleType.rotatingBar) {
      segments.add(
        ObstacleSegment(
          Rect.fromCenter(
            center: Offset(gapCenter, worldY),
            width: bounds.width * .38,
            height: 22,
          ),
          material: ObstacleMaterial.energy,
          health: 1,
        ),
      );
    } else {
      final leftWidth = math.min(maxWallWidth, left - bounds.left - 12);
      if (leftWidth > 14) {
        segments.add(
          ObstacleSegment(
            Rect.fromLTWH(left - leftWidth, worldY, leftWidth, wallHeight),
            material: material,
            health: health,
          ),
        );
      }
      final rightWidth = math.min(maxWallWidth, bounds.right - right - 12);
      if (rightWidth > 14) {
        segments.add(
          ObstacleSegment(
            Rect.fromLTWH(right, worldY, rightWidth, wallHeight),
            material: material,
            health: health,
          ),
        );
      }
      if (type == ObstacleType.electricField) {
        segments.add(
          ObstacleSegment(
            Rect.fromLTWH(left - 7, worldY - 14, gapWidth + 14, 10),
            material: ObstacleMaterial.electric,
            health: 1,
          ),
        );
      }
    }
    obstacles.add(
      ObstacleGroup(
        type: type,
        segments: segments,
        gapCenter: gapCenter,
        spawnY: worldY,
      ),
    );
  }

  bool _coinPositionIsValid(
    Offset candidate,
    Iterable<Offset> existing,
    Iterable<Rect> blockedRects,
  ) {
    for (final position in existing) {
      if ((candidate - position).distance < minimumCoinDistance) {
        return false;
      }
    }

    final candidateRect = Rect.fromCircle(
      center: candidate,
      radius: coinRadius + 5,
    );

    for (final blocked in blockedRects) {
      if (candidateRect.overlaps(blocked)) {
        return false;
      }
    }

    return true;
  }

  void _spawnCoinTrail() {
    if (coins.length >= maxCoins || size.x <= 0) return;

    final pattern = _nextCoinPattern();
    final offsets = _coinPlanner.offsetsFor(pattern);
    final bounds = playableArea.deflate(coinRadius + 10);

    final minX = offsets.map((offset) => offset.dx).reduce(math.min);
    final maxX = offsets.map((offset) => offset.dx).reduce(math.max);
    final patternDepth = _coinPlanner.patternDepth(pattern);

    final spawnScreenY = bounds.top - patternDepth - 50;
    final anchorWorldY = _worldYForSpawn(spawnScreenY);

    final existing = coins
        .where((coin) => coin.alive)
        .map((coin) => coin.worldPosition)
        .toList(growable: false);

    final blockedRects = _blockedCoinRects();

    for (var attempt = 0; attempt < 12; attempt++) {
      final routeVariation =
          (_random.nextDouble() * 2 - 1) * math.min(100, 35 + _elapsed * .2);

      final anchorX = (_lastRouteX + routeVariation)
          .clamp(
            bounds.left - minX,
            bounds.right - maxX,
          )
          .toDouble();

      final anchor = Offset(anchorX, anchorWorldY);
      final positions = offsets.map((offset) => anchor + offset).toList();

      final valid = positions.every(
        (position) => _coinPositionIsValid(
          position,
          existing,
          blockedRects,
        ),
      );

      if (!valid) continue;

      for (final position in positions) {
        if (coins.length >= maxCoins) break;

        coins.add(
          Coin(
            Rect.fromCircle(
              center: position,
              radius: coinRadius,
            ),
          ),
        );
      }

      _nextCoinSpawnScrollY =
          _worldDistance + patternDepth + minimumCoinDistance * 2;

      return;
    }
  }

  List<Rect> _blockedCoinRects() => [
    for (final group in obstacles)
      for (final segment in group.segments.where((item) => item.alive))
        segment.worldRect.inflate(coinRadius + 10),
  ];

  CoinPattern _nextCoinPattern() {
    final patterns = <CoinPattern>[
      CoinPattern.single,
      CoinPattern.diagonal,
      CoinPattern.horizontal,
      if (_elapsed >= 20) CoinPattern.arc,
      if (_elapsed >= 60) CoinPattern.zigzag,
    ];
    return patterns[_random.nextInt(patterns.length)];
  }

  void _spawnPickup() {
    final id = _pickPower();
    final bounds = playableArea.deflate(20);
    final x = _lastRouteX.clamp(bounds.left, bounds.right).toDouble();
    final spawnScreenY = bounds.top - 48;
    final worldY = _worldYForSpawn(spawnScreenY);
    final candidate = Rect.fromCenter(
      center: Offset(x, worldY),
      width: 34,
      height: 34,
    );
    final candidateScreen = _worldRectToScreen(candidate);
    if (obstacles.any(
      (group) => group.segments.any(
        (segment) =>
            segment.alive &&
            _worldRectToScreen(segment.worldRect).overlaps(candidateScreen),
      ),
    )) {
      return;
    }
    if (!validator.isReachable(
      fromX: playerPosition.dx,
      gapCenter: x,
      gapWidth: 90,
      distance: playerPosition.dy - spawnScreenY,
      speed: math.max(_effectSpeed, 100),
    )) {
      return;
    }
    pickups.add(PowerPickup(candidate, id));
  }

  PowerId _pickPower() {
    final seconds = _elapsed;
    final candidates = <(PowerId, int)>[
      (PowerId.magnet, 25),
      (PowerId.shield, 25),
      (PowerId.gun, 15),
      (PowerId.slowTime, 15),
      (PowerId.invisibility, 10),
      (PowerId.doubleScore, 7 + (seconds ~/ 90)),
      (PowerId.coinMultiplier, 7 + (seconds ~/ 90)),
      (PowerId.emp, 6 + (seconds ~/ 120)),
      (PowerId.phaseDash, 3 + (seconds ~/ 120)),
      (PowerId.turboCollect, 3 + (seconds ~/ 120)),
    ];
    final total = candidates.fold<int>(0, (sum, entry) => sum + entry.$2);
    var ticket = _random.nextInt(total);
    for (final item in candidates) {
      ticket -= item.$2;
      if (ticket < 0) return item.$1;
    }
    return PowerId.magnet;
  }

  void _fireBullet() {
    if (bullets.length >= maxBullets) return;
    bullets.add(
      Bullet(
        Rect.fromCenter(
          center: playerPosition.translate(0, -33),
          width: 6,
          height: 18,
        ),
      ),
    );
    _burst(playerPosition.translate(0, -30), const Color(0xffffa25f), 3, .28);
  }

  void _checkBulletImpacts() {
    for (final bullet in bullets.where((item) => item.alive).toList()) {
      for (final group in obstacles) {
        for (final segment in group.segments.where((item) => item.alive)) {
          final segmentScreen = _worldRectToScreen(segment.worldRect);
          if (bullet.rect.overlaps(segmentScreen)) {
            bullet.alive = false;
            segment.health--;
            segment.damageFlash = .35;
            _burst(
              Offset(segmentScreen.center.dx, segmentScreen.center.dy),
              materialColor(segment.material),
              8,
              .45,
            );
            if (segment.health <= 0) {
              segment.alive = false;
              destroyed++;
              _burst(
                Offset(segmentScreen.center.dx, segmentScreen.center.dy),
                materialColor(segment.material),
                15,
                .7,
              );
            }
            break;
          }
        }
      }
    }
  }

  void _checkCollisions() {
    final shipRect = Rect.fromCenter(center: playerPosition, width: 40, height: 48);
    for (final group in obstacles) {
      for (final segment in group.segments.where(
        (item) => item.alive && item.dangerous,
      )) {
        final segmentScreen = _worldRectToScreen(segment.worldRect);
        if (shipRect.overlaps(segmentScreen)) {
          if (invulnerable) continue;
          if (hasShield) {
            _powers.remove(PowerId.shield);
            _impact = 1;
            _banner = 'SHIELD BROKEN';
            _bannerLife = 1;
            _burst(playerPosition, const Color(0xff39efd1), 28, .8);
            _haptic(HapticFeedback.heavyImpact);
            segment.alive = false;
            return;
          }
          _gameOver();
          return;
        }
        final distance =
            (Offset(segmentScreen.center.dx, segmentScreen.center.dy) -
                    playerPosition)
                .distance;
        if (!group.nearMissReported &&
            distance < 72 &&
            !shipRect.overlaps(segmentScreen)) {
          group.nearMissReported = true;
          _banner = 'NEAR MISS';
          _bannerLife = .45;
          _impact = .25;
        }
      }
    }
    for (final coin in coins.where((item) => item.alive).toList()) {
      final coinScreen = _worldToScreen(coin.worldPosition);
      final distance = (coinScreen - playerPosition).distance;
      if (distance <= pickupRadius + coinRadius) {
        _collectCoin(coin, coinScreen);
      }
    }
    for (final pickup in pickups.where((item) => item.alive).toList()) {
      final pickupScreen = _worldRectToScreen(pickup.worldRect);
      if (shipRect.inflate(5).overlaps(pickupScreen)) {
        pickup.alive = false;
        activatePower(pickup.id);
      }
    }
  }

  void _collectCoin(Coin coin, Offset coinScreen) {
    if (!coin.alive) return;
    coin.alive = false;
    collectedCoins++;
    final gained = (coinMultiplier * scoreMultiplier).round();
    score += gained;
    if (floatingTexts.length < 9) {
      floatingTexts.add(
        FloatingText(
          '+$gained',
          coinScreen,
          const Color(0xffffdc52),
        ),
      );
    }
    _burst(coinScreen, const Color(0xffffd74d), 5, .35);
    _haptic(HapticFeedback.selectionClick);
  }

  void activatePower(PowerId id) {
    final definition = powerDefinitions[id]!;
    _powers[id] = ActivePower(id, definition.duration);
    powersUsed++;
    _banner = definition.label;
    _bannerLife = 1.2;
    _burst(ship, definition.color, 18, .65);
    _haptic(HapticFeedback.mediumImpact);
  }

  void _gameOver() {
    phase = GamePhase.gameOver;
    score += (_elapsed * scoreMultiplier).floor();
    _newBest = score > bestScore;
    if (_newBest) {
      bestScore = score;
      if (_loadedStorage) unawaited(_saveBest());
    }
    _impact = 1;
    _banner = _newBest ? 'NEW BEST!' : 'RUN COMPLETE';
    _bannerLife = 1.8;
    _burst(ship, const Color(0xffff735a), 38, 1.1);
    _haptic(HapticFeedback.heavyImpact);
    _emit();
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('space_survival_best', bestScore);
  }

  void _cleanup() {
    final bottomLimit = playableArea.bottom + 60;

    obstacles.removeWhere(
      (group) => group.segments.every(
        (segment) =>
            !segment.alive ||
            _worldRectToScreen(segment.worldRect).top > bottomLimit,
      ),
    );

    coins.removeWhere(
      (coin) =>
          !coin.alive ||
          _worldToScreen(coin.worldPosition).dy > bottomLimit,
    );

    pickups.removeWhere(
      (pickup) =>
          !pickup.alive ||
          _worldRectToScreen(pickup.worldRect).top > bottomLimit,
    );

    bullets.removeWhere(
      (bullet) => !bullet.alive || bullet.rect.bottom < -30,
    );

    particles.removeWhere((particle) => particle.life <= 0);
    floatingTexts.removeWhere((text) => text.life <= 0);
  }

  void _burst(Offset origin, Color color, int count, double life) {
    for (
      var index = 0;
      index < count && particles.length < maxParticles;
      index++
    ) {
      final angle = _random.nextDouble() * math.pi * 2;
      final velocity = 55 + _random.nextDouble() * 145;
      particles.add(
        Particle(
          origin,
          Offset(math.cos(angle) * velocity, math.sin(angle) * velocity),
          color,
          life,
          size: 2 + _random.nextDouble() * 3,
        ),
      );
    }
  }

  void _haptic(Future<void> Function() feedback) {
    if (hapticsEnabled) unawaited(feedback());
  }

  void _emit() {
    onSnapshot(
      GameSnapshot(
        phase: phase,
        score: displayedScore,
        coins: collectedCoins,
        elapsed: _elapsed,
        bestScore: bestScore,
        speed: _effectSpeed,
        activePowers: _powers.values
            .map((power) => ActivePower(power.id, power.remaining))
            .toList(growable: false),
        powersUsed: powersUsed,
        destroyed: destroyed,
        newBest: _newBest,
        countdown: phase == GamePhase.countdown
            ? (_countdown > .35 ? _countdown.ceil().toString() : 'GO')
            : '',
        banner: _bannerLife > 0 ? _banner : '',
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final screen = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(screen, Paint()..color = const Color(0xff050914));
    _drawStars(canvas);
    _drawAtmosphere(canvas);
    for (final group in obstacles) {
      _drawObstacle(canvas, group);
    }
    for (final coin in coins) {
      _drawCoin(canvas, coin);
    }
    for (final pickup in pickups) {
      _drawPickup(canvas, pickup);
    }
    for (final bullet in bullets) {
      _drawBullet(canvas, bullet);
    }
    for (final particle in particles) {
      _drawParticle(canvas, particle);
    }
    _drawShip(canvas);
    for (final text in floatingTexts) {
      _drawText(
        canvas,
        text.text,
        text.position,
        text.color,
        14,
        opacity: text.life.clamp(0, 1),
      );
    }
    if (_bannerLife > 0 && phase != GamePhase.home) {
      _drawText(
        canvas,
        _banner,
        Offset(size.x / 2, size.y * .29),
        _newBest ? const Color(0xffffd452) : const Color(0xffeff7ff),
        17,
        center: true,
        opacity: math.min(1, _bannerLife * 2),
      );
    }
  }

  void _drawStars(Canvas canvas) {
    for (var index = 0; index < _stars.length; index++) {
      final seed = _stars[index];
      final layer = index % 3;
      final y = (seed.dy + _starOffset * (layer + 1) * .15) % size.y;
      final opacity = .2 + layer * .13;
      canvas.drawCircle(
        Offset(seed.dx, y),
        layer == 2 ? 1.2 : .7,
        Paint()..color = const Color(0xffb8dfff).withValues(alpha: opacity),
      );
    }
  }

  void _drawAtmosphere(Canvas canvas) {
    final area = playableArea;

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xff0b1630),
          Color(0x000b1630),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(area);

    canvas.drawRect(area, paint);

    final linePaint = Paint()
      ..color = const Color(0xff2d76a9).withValues(alpha: .08)
      ..strokeWidth = 1;

    for (var y = area.top; y < area.bottom; y += 110) {
      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        linePaint,
      );
    }
  }

  void _drawObstacle(Canvas canvas, ObstacleGroup group) {
    for (final segment in group.segments.where((item) => item.alive)) {
      final screenRect = _worldRectToScreen(segment.worldRect);
      final color = materialColor(segment.material);
      canvas.save();
      if (group.type == ObstacleType.rotatingBar) {
        canvas.translate(screenRect.center.dx, screenRect.center.dy);
        canvas.rotate(group.rotation);
        canvas.translate(-screenRect.center.dx, -screenRect.center.dy);
      }
      final glow = Paint()
        ..color = color.withValues(alpha: .16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          screenRect.inflate(3),
          const Radius.circular(6),
        ),
        glow,
      );
      final paint = Paint()
        ..color = color.withValues(alpha: segment.damageFlash > 0 ? 1 : .82);
      if (group.type == ObstacleType.asteroidCluster ||
          group.type == ObstacleType.mineField) {
        canvas.drawCircle(
          screenRect.center,
          screenRect.width / 2,
          paint,
        );
        canvas.drawCircle(
          screenRect.center,
          screenRect.width / 2 + 5 + math.sin(group.age * 5) * 2,
          Paint()
            ..color = color.withValues(alpha: .24)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(screenRect, const Radius.circular(5)),
          paint,
        );
        canvas.drawLine(
          screenRect.topLeft + const Offset(5, 6),
          screenRect.topRight - const Offset(5, -6),
          Paint()
            ..color = const Color(0xffe5f7ff).withValues(alpha: .3)
            ..strokeWidth = 1,
        );
        if (segment.health > 1) {
          canvas.drawLine(
            screenRect.centerLeft + const Offset(7, 0),
            screenRect.centerRight - const Offset(7, 0),
            Paint()
              ..color = const Color(0xff09111e).withValues(alpha: .42)
              ..strokeWidth = 2,
          );
        }
      }
      canvas.restore();
    }
  }

  void _drawCoin(Canvas canvas, Coin coin) {
    final center = _worldToScreen(coin.worldPosition);
    final radius = coin.rect.width / 2 * (1 + math.sin(coin.pulse) * .06);
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..color = const Color(0xffffd54e).withValues(alpha: .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xffffcb3d));
    canvas.drawCircle(
      center,
      radius * .56,
      Paint()..color = const Color(0xfffff0a3),
    );
  }

  void _drawPickup(Canvas canvas, PowerPickup pickup) {
    final definition = powerDefinitions[pickup.id]!;
    final center = _worldRectToScreen(pickup.worldRect).center.translate(
      0,
      math.sin(pickup.age * 3) * 3,
    );
    final scale = math.min(1, pickup.age * 4).toDouble();
    canvas.drawCircle(
      center,
      24 * scale,
      Paint()
        ..color = definition.color.withValues(alpha: .14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      center,
      17 * scale,
      Paint()..color = const Color(0xff111b2e),
    );
    canvas.drawCircle(
      center,
      17 * scale,
      Paint()
        ..color = definition.color.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _drawText(
      canvas,
      definition.symbol,
      center,
      definition.color,
      pickup.id == PowerId.doubleScore || pickup.id == PowerId.coinMultiplier
          ? 11
          : 19,
      center: true,
    );
  }

  void _drawBullet(Canvas canvas, Bullet bullet) {
    final center = bullet.rect.center;
    canvas.drawLine(
      center.translate(0, 11),
      center.translate(0, 28),
      Paint()
        ..color = const Color(0xffff8d58).withValues(alpha: .4)
        ..strokeWidth = 3,
    );
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xffffd8b6));
  }

  void _drawParticle(Canvas canvas, Particle particle) {
    canvas.drawCircle(
      particle.position,
      particle.size * particle.life.clamp(0, 1),
      Paint()
        ..color = particle.color.withValues(alpha: particle.life.clamp(0, 1)),
    );
  }

  void _drawShip(Canvas canvas) {
    if (playerPosition == Offset.zero) return;
    final opacity = invulnerable ? .48 : 1.0;
    final shift =
        (playerTargetPosition.dx - playerPosition.dx).clamp(-45, 45) / 45;
    canvas.save();
    canvas.translate(
      playerPosition.dx,
      playerPosition.dy + math.sin(_elapsed * 3.2) * 2,
    );
    canvas.rotate(shift * .16);
    final flameLength = 20 + difficulty.currentDifficultySpeed / 55;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, 30), width: 13, height: flameLength),
      Paint()..color = const Color(0xff2de3ff).withValues(alpha: .3),
    );
    final shipPath = Path()
      ..moveTo(0, -31)
      ..lineTo(24, 24)
      ..lineTo(7, 18)
      ..lineTo(0, 27)
      ..lineTo(-7, 18)
      ..lineTo(-24, 24)
      ..close();
    canvas.drawPath(
      shipPath,
      Paint()..color = const Color(0xffd8efff).withValues(alpha: opacity),
    );
    canvas.drawPath(
      shipPath,
      Paint()
        ..color = const Color(0xff4aaeea).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -2), width: 12, height: 18),
      Paint()..color = const Color(0xff66efff).withValues(alpha: opacity),
    );
    if (hasShield) {
      final ring = 39 + math.sin(_elapsed * 7) * 3;
      canvas.drawCircle(
        Offset.zero,
        ring,
        Paint()
          ..color = const Color(0xff35f0d1).withValues(alpha: .7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        Offset.zero,
        ring + 5,
        Paint()
          ..color = const Color(0xff35f0d1).withValues(alpha: .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
    if (_powers.containsKey(PowerId.magnet)) {
      canvas.drawCircle(
        Offset.zero,
        58 + math.sin(_elapsed * 5) * 4,
        Paint()
          ..color = const Color(0xff2de3ff).withValues(alpha: .14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    if (_impact > 0) {
      canvas.drawCircle(
        Offset.zero,
        55 * (1 - _impact),
        Paint()
          ..color = const Color(0xffffffff).withValues(alpha: _impact * .7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    canvas.restore();
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    Color color,
    double fontSize, {
    bool center = false,
    double opacity = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: opacity),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: center ? TextAlign.center : TextAlign.left,
    )..layout(maxWidth: size.x - 20);
    painter.paint(
      canvas,
      center
          ? Offset(
              position.dx - painter.width / 2,
              position.dy - painter.height / 2,
            )
          : position,
    );
  }
}

Color materialColor(ObstacleMaterial material) => switch (material) {
  ObstacleMaterial.metal => const Color(0xff557b9f),
  ObstacleMaterial.energy => const Color(0xff60d3ff),
  ObstacleMaterial.crystal => const Color(0xffff766b),
  ObstacleMaterial.asteroid => const Color(0xffb08b75),
  ObstacleMaterial.laser => const Color(0xffff4d78),
  ObstacleMaterial.electric => const Color(0xffb67cff),
};
