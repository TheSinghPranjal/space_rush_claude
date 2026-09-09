import 'dart:async';
import 'dart:math' as math;

import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'models.dart';
import 'systems.dart';

class SpaceSurvivalGame extends FlameGame with PanDetector {
  SpaceSurvivalGame({
    required this.onSnapshot,
    this.mode = GameMode.survival,
    GameBalance? balance,
  }) : balance = balance ?? GameBalance.survival,
       super();

  final ValueChanged<GameSnapshot> onSnapshot;
  final GameMode mode;
  final GameBalance balance;
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
  final CoinSpawnPlanner _coinPlanner = const CoinSpawnPlanner();
  final DifficultyPhaseBook _phases = const DifficultyPhaseBook();
  final PowerRarityTable _rarity = const PowerRarityTable();

  late final SpeedDirector speed = SpeedDirector(difficulty: difficulty);
  final PowerController powers = PowerController();
  final ScoreAccumulator scoreboard = ScoreAccumulator();
  final PlayerController steering = PlayerController();
  final SessionFlow flow = SessionFlow();
  final FrameClock clock = FrameClock();
  final AudioBus audio = AudioBus();
  final AnalyticsBus analytics = AnalyticsBus();
  final ObjectPool<Coin> _coinPool = ObjectPool(capacity: 96);
  final ObjectPool<Bullet> _bulletPool = ObjectPool(capacity: 24);
  final ObjectPool<PowerPickup> _pickupPool = ObjectPool(capacity: 8);
  final ObjectPool<Particle> _particlePool = ObjectPool(capacity: 160);
  final ObjectPool<ObstacleSegment> _segmentPool = ObjectPool(capacity: 64);

  GamePhase get phase => flow.phase;
  set phase(GamePhase value) => flow.phase = value;

  Offset playerPosition = Offset.zero;
  Offset playerTargetPosition = Offset.zero;
  double _worldDistance = 0;
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
  double _lastGapWidth = 120;
  double _impact = 0;
  double _bannerLife = 0;
  double _transition = 0;
  double _exhaustClock = 0;
  String _banner = '';
  int bestScore = 0;
  int destroyed = 0;
  bool hapticsEnabled = true;
  bool debugView = kDebugMode;
  bool _newBest = false;
  bool _loadedStorage = false;
  bool _lastFair = true;
  PowerId? _assistPower;
  GameSnapshot? _lastHud;

  static const double coinRadius = 9;
  static const double coinSpacing = 22;

  bool get isPlaying => flow.isPlaying;
  Offset get ship => playerPosition;
  set ship(Offset value) {
    playerPosition = value;
    steering.place(value.dx, value.dy);
  }

  double get targetShipX => steering.targetX;
  set targetShipX(double value) => steering.setDragX(value);

  Rect get viewRect {
    if (size.x <= 0 || size.y <= 0) return Rect.zero;
    final portraitWidth = size.y * 9 / 20;
    final width = math.min(size.x, math.max(320.0, portraitWidth));
    final left = (size.x - width) / 2;
    return Rect.fromLTWH(left, 0, width, size.y);
  }

  Rect get playableArea {
    final view = viewRect;
    final horizontalInset = math.max(20.0, view.width * .045);
    final hudClearance = math.max(132.0, view.height * .17);
    final bottomInset = math.max(24.0, view.height * .04);
    return Rect.fromLTRB(
      view.left + horizontalInset,
      hudClearance,
      view.right - horizontalInset,
      view.bottom - bottomInset,
    );
  }

  bool get hasShield => powers.hasShield;
  bool get invulnerable => powers.invulnerable;
  double get scoreMultiplier => powers.scoreMultiplier;
  double get coinMultiplier => powers.coinMultiplier;
  double get pickupRadius => powers.pickupRadius;
  double get playerSpeed => PlayabilityValidator.shipSpeed * powers.moveScale;
  double get obstacleTargetSpeed => speed.obstacleScrollSpeed;
  double get minimumCoinDistance => coinRadius * 2 + coinSpacing;
  int get displayedScore => scoreboard.total;
  int get collectedCoins => scoreboard.coinsCollected;
  int get score => scoreboard.total;
  int get powersUsed => powers.activations;
  bool get lastSpawnFair => _lastFair;

  String get _countdownLabel {
    if (_countdown > 2) return '3';
    if (_countdown > 1) return '2';
    if (_countdown > .4) return '1';
    return 'GO';
  }

  String get debugLine =>
      't=${_elapsed.toStringAsFixed(1)} '
      'world=${speed.worldScrollSpeed.toStringAsFixed(0)} '
      'obs=${speed.obstacleScrollSpeed.toStringAsFixed(0)} '
      'emp=${speed.empFactor.toStringAsFixed(2)} '
      'slow=${speed.slowFactor.toStringAsFixed(2)} '
      'gap=${_lastGapWidth.toStringAsFixed(0)} '
      'route=${_lastRouteX.toStringAsFixed(0)} '
      'fair=${_lastFair ? 'Y' : 'N'}';

  WorldCamera get _camera => WorldCamera(offset: Offset(0, _worldDistance));

  Offset _worldToScreen(Offset position) => _camera.worldToScreen(position);

  Rect _worldRectToScreen(Rect worldRect) =>
      _camera.worldRectToScreen(worldRect);

  double _worldYForSpawn(double screenY) =>
      _camera.screenToWorld(Offset(0, screenY)).dy;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final prefs = await SharedPreferences.getInstance();
    bestScore = prefs.getInt('space_survival_best') ?? 0;
    hapticsEnabled = prefs.getBool('space_survival_haptics') ?? true;
    _loadedStorage = true;
    _emit(force: true);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    final y = playableArea.bottom - playableArea.height * .18;
    if (ship == Offset.zero) {
      steering.place(playableArea.center.dx, y);
    } else {
      steering.baseY = y;
      steering.x = steering.x
          .clamp(_minShipX, _maxShipX)
          .toDouble();
      steering.targetX = steering.targetX.clamp(_minShipX, _maxShipX).toDouble();
    }
    playerPosition = steering.position;
    playerTargetPosition = Offset(steering.targetX, steering.baseY);
    _lastRouteX = steering.x;
    if (_stars.isEmpty) {
      for (var index = 0; index < 95; index++) {
        _stars.add(
          Offset(_random.nextDouble() * size.x, _random.nextDouble() * size.y),
        );
      }
    }
  }

  double get _minShipX => playableArea.left + 25;
  double get _maxShipX => playableArea.right - 25;

  @override
  void onPanStart(DragStartInfo info) {
    if (!flow.acceptSteer) return;
    steering.setDragX(info.eventPosition.widget.x);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (!flow.acceptSteer) return;
    steering.setDragX(info.eventPosition.widget.x);
  }

  void start() {
    resetRun();
    flow.startCountdown();
    _countdown = 3;
    _banner = 'SYSTEMS READY';
    _bannerLife = 1.2;
    _transition = 1;
    audio.play(GameSfx.countdown);
    analytics.emit(GameAnalyticsEvent.runStart);
    _emit(force: true);
  }

  void restart() {
    analytics.emit(GameAnalyticsEvent.restart);
    start();
  }

  void returnHome() {
    flow.enterHome();
    _emit(force: true);
  }

  void requestPause() {
    if (!flow.requestPause()) return;
    audio.play(GameSfx.pause);
    analytics.emit(GameAnalyticsEvent.pause);
    _emit(force: true);
  }

  void resume() {
    if (phase != GamePhase.paused) return;
    flow.resumeFromPause();
    _countdown = 2.2;
    _banner = 'READY';
    _bannerLife = 1.0;
    clock.armResume();
    audio.play(GameSfx.resume);
    analytics.emit(GameAnalyticsEvent.resume);
    _emit(force: true);
  }

  void onAppInactive() {
    if (!flow.onAppInactive()) return;
    audio.play(GameSfx.pause);
    _emit(force: true);
  }

  Future<void> toggleHaptics() async {
    hapticsEnabled = !hapticsEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('space_survival_haptics', hapticsEnabled);
    _emit(force: true);
  }

  void toggleDebug() {
    debugView = !debugView;
    _emit(force: true);
  }

  void debugSpawn(PowerId id) {
    if (!isPlaying) return;
    activatePower(id);
  }

  void resetRun() {
    difficulty.reset();
    speed.reset();
    powers.reset();
    scoreboard.reset();
    audio.reset();
    obstacles.clear();
    coins.clear();
    pickups.clear();
    bullets.clear();
    particles.clear();
    floatingTexts.clear();
    _elapsed = 0;
    _spawnClock = 0;
    _coinClock = 0;
    _powerClock = 0;
    _gunClock = 0;
    _effectSpeed = difficulty.baseSpeed;
    _impact = 0;
    _banner = '';
    _bannerLife = 0;
    destroyed = 0;
    _newBest = false;
    _worldDistance = 0;
    _nextCoinSpawnScrollY = 0;
    _assistPower = null;
    _lastFair = true;
    _lastHud = null;
    final y = size.y > 0
        ? playableArea.bottom - playableArea.height * .18
        : 0.0;
    final x = size.x > 0 ? playableArea.center.dx : 0.0;
    steering.place(x, y);
    playerPosition = steering.position;
    playerTargetPosition = steering.position;
    _lastRouteX = steering.x;
    _lastGapWidth = playableArea.width * .31;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final safeDt = clock.clamp(dt);
    _transition = math.max(0, _transition - safeDt * 2.4);
    if (phase == GamePhase.home) {
      _starOffset += safeDt * 8;
      return;
    }
    if (phase == GamePhase.countdown || phase == GamePhase.resuming) {
      _starOffset += safeDt * 12;
      _countdown -= safeDt;
      if (_countdown <= 0) {
        flow.enterPlaying();
        _banner = 'GO';
        _bannerLife = .65;
        clock.armResume();
        audio.play(GameSfx.countdown);
        _haptic(HapticFeedback.mediumImpact);
      }
      _emit(force: true);
      return;
    }
    if (phase == GamePhase.paused || phase == GamePhase.gameOver) return;
    if (!isPlaying) return;

    _elapsed += safeDt;
    speed.setSlowTime(powers.has(PowerId.slowTime));
    speed.setEmp(powers.has(PowerId.emp));
    speed.update(_elapsed, safeDt);
    _effectSpeed +=
        (speed.worldScrollSpeed - _effectSpeed) * math.min(1, safeDt * 4.4);
    _starOffset += safeDt * (18 + _effectSpeed * .08);
    scoreboard.tickSurvival(safeDt, powers.scoreMultiplier);
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
    final expired = powers.update(dt, timersFrozen: flow.timersFrozen);
    for (final id in expired) {
      _banner = '${powerDefinitions[id]!.label} ENDED';
      _bannerLife = .55;
      _burst(ship, powerDefinitions[id]!.color, 8, .5);
    }
    if (powers.has(PowerId.gun)) {
      _gunClock += dt;
      if (_gunClock > .25) {
        _gunClock = 0;
        _fireBullet();
      }
    } else {
      _gunClock = 0;
    }
  }

  void _updateShip(double dt) {
    steering.update(
      dt,
      maxSpeed: playerSpeed,
      minX: _minShipX,
      maxX: _maxShipX,
    );
    playerPosition = steering.position;
    playerTargetPosition = Offset(steering.targetX, steering.baseY);
  }

  void _updateWorldScroll(double dt) {
    _worldDistance += speed.worldScrollSpeed * dt;
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
    if (_powerClock >= balance.powerMinInterval &&
        pickups.length < balance.maxPickups) {
      _powerClock = 0;
      _spawnPickup();
    }
    final empMotion = speed.empFactor;
    for (final group in obstacles) {
      if (empMotion > .04) group.age += dt;
      final lateral = switch (group.type) {
        ObstacleType.piston => math.sin(group.age * 2.3) * 20 * dt * empMotion,
        ObstacleType.splitWall => math.sin(group.age * 1.8) * 9 * dt * empMotion,
        _ => 0.0,
      };
      if (group.type == ObstacleType.rotatingBar) {
        group.rotation += dt * .9 * empMotion;
      }
      for (final segment in group.segments) {
        if (lateral != 0) segment.translateWorld(Offset(lateral, 0));
        if (speed.obstacleHoldSpeed != 0) {
          segment.translateWorld(Offset(0, speed.obstacleHoldSpeed * dt));
        }
        segment.damageFlash = math.max(0, segment.damageFlash - dt * 2);
      }
    }
    for (final coin in coins) {
      coin.pulse += dt * 5;
      coin.spawnAge += dt;
      final coinScreen = _worldToScreen(coin.worldPosition);
      final distance = (coinScreen - playerPosition).distance;
      if (powers.has(PowerId.turboCollect) &&
          distance < balance.turboPickupRadius) {
        final pull = turboCollectVelocity(
          from: coinScreen,
          to: playerPosition,
          pulse: coin.pulse,
          radius: balance.turboPickupRadius,
        );
        coin.translateWorld(pull * dt);
        coin.turboPull = true;
        coin.attracting = false;
      } else if (powers.has(PowerId.magnet) && distance < balance.magnetRadius) {
        final direction = (playerPosition - coinScreen) / math.max(distance, 1);
        coin.translateWorld(direction * 480 * dt);
        coin.attracting = true;
        coin.turboPull = false;
      } else {
        coin.attracting = false;
        coin.turboPull = false;
      }
    }
    for (final pickup in pickups) {
      pickup.age += dt;
      if (pickup.age > 10.5) pickup.alive = false;
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
    _updateExhaust(dt);
    _checkBulletImpacts();
  }

  void _updateExhaust(double dt) {
    if (speed.difficultySpeed < 300) return;
    _exhaustClock += dt;
    if (_exhaustClock < .05) return;
    _exhaustClock = 0;
    _burst(
      playerPosition.translate(0, 28),
      const Color(0xff4ce7ff),
      2,
      .28,
    );
  }

  void _spawnObstacle() {
    if (obstacles.length >= balance.maxObstacles || size.x <= 0) return;
    final phaseIndex = _phases.phaseIndex(_elapsed);
    final candidates = _phases.typesFor(phaseIndex);
    final type = candidates[_random.nextInt(candidates.length)];
    final definition = obstacleDefinitions[type]!;
    const safeMargin =
        PlayabilityValidator.shipWidth + PlayabilityValidator.safetyMargin;
    final bounds = playableArea;
    var gapWidth = type == ObstacleType.narrowWindow
        ? safeMargin + 8
        : math.max(safeMargin, bounds.width * (_elapsed < 60 ? .31 : .25));
    gapWidth = math.max(gapWidth, safeMargin);
    final maxRouteShift = math.min(bounds.width * .24, 155 + _elapsed * .12);
    final proposed =
        (_lastRouteX + (_random.nextDouble() * 2 - 1) * maxRouteShift)
            .clamp(
              bounds.left + gapWidth / 2 + 18,
              bounds.right - gapWidth / 2 - 18,
            )
            .toDouble();
    final spawnScreenY = bounds.top - 90;
    final worldY = _worldYForSpawn(spawnScreenY);
    final distance = playerPosition.dy - spawnScreenY;
    final lookSpeed = math.max(speed.worldScrollSpeed, 100.0);
    final fromLast = validator.validateReachability(
      fromX: _lastRouteX,
      gapCenter: proposed,
      gapWidth: gapWidth,
      distance: distance,
      speed: lookSpeed,
    );
    final fromShip = validator.validateReachability(
      fromX: steering.x,
      gapCenter: proposed,
      gapWidth: gapWidth,
      distance: distance,
      speed: lookSpeed,
    );
    final gapCenter = fromLast && fromShip ? proposed : _lastRouteX;
    _lastFair = validator.validateReachability(
      fromX: _lastRouteX,
      gapCenter: gapCenter,
      gapWidth: gapWidth,
      distance: distance,
      speed: lookSpeed,
    );
    _lastRouteX = gapCenter;
    _lastGapWidth = gapWidth;
    final health = definition.minHealth +
        (definition.maxHealth > definition.minHealth && _random.nextBool()
            ? 1
            : 0);
    final segments = _buildSegments(
      type: type,
      definition: definition,
      bounds: bounds,
      gapCenter: gapCenter,
      gapWidth: gapWidth,
      worldY: worldY,
      health: health.clamp(definition.minHealth, definition.maxHealth),
    );
    obstacles.add(
      ObstacleGroup(
        type: type,
        segments: segments,
        gapCenter: gapCenter,
        spawnY: worldY,
      ),
    );
    if (type == ObstacleType.breakableWall) {
      _assistPower = PowerId.gun;
    } else if (type == ObstacleType.asteroidCluster && _random.nextBool()) {
      _assistPower = PowerId.magnet;
    }
  }

  List<ObstacleSegment> _buildSegments({
    required ObstacleType type,
    required ObstacleDefinition definition,
    required Rect bounds,
    required double gapCenter,
    required double gapWidth,
    required double worldY,
    required int health,
  }) {
    final segments = <ObstacleSegment>[];
    const maxWallWidth = 78.0;
    final wallHeight = type == ObstacleType.laserGate ? 64.0 : 40.0;
    final left = gapCenter - gapWidth / 2;
    final right = gapCenter + gapWidth / 2;

    ObstacleSegment make(Rect rect, {ObstacleMaterial? material, int? hp}) {
      final segment = _segmentPool.acquire(
        () => ObstacleSegment(
          rect,
          material: material ?? definition.material,
          health: hp ?? health,
        ),
      );
      segment.recycle(
        rect,
        material: material ?? definition.material,
        health: hp ?? health,
        maxHealth: definition.maxHealth,
      );
      return segment;
    }

    if (type == ObstacleType.asteroidCluster || type == ObstacleType.mineField) {
      for (final x in [
        bounds.left + bounds.width * .13,
        bounds.left + bounds.width * .33,
        bounds.left + bounds.width * .67,
        bounds.left + bounds.width * .87,
      ]) {
        if ((x - gapCenter).abs() > gapWidth * .38) {
          final radius = type == ObstacleType.mineField
              ? 17.0
              : 22 + _random.nextDouble() * 11;
          segments.add(
            make(
              Rect.fromCenter(
                center: Offset(x, worldY + _random.nextDouble() * 38),
                width: radius * 2,
                height: radius * 2,
              ),
              hp: 1,
            ),
          );
        }
      }
      return segments;
    }

    if (type == ObstacleType.rotatingBar) {
      final wallLeftWidth = math.max(20.0, left - bounds.left);
      final onLeft = wallLeftWidth >= (bounds.right - right);
      final pivotX = onLeft ? left - math.min(40, wallLeftWidth / 2) : right + 36;
      segments.add(
        make(
          Rect.fromCenter(
            center: Offset(pivotX, worldY),
            width: math.min(bounds.width * .28, 92),
            height: 18,
          ),
          hp: 1,
        ),
      );
      return segments;
    }

    if (type == ObstacleType.zigzag) {
      for (var row = 0; row < 2; row++) {
        final y = worldY + row * 58;
        final leftBias = row == 0 ? 18.0 : 0.0;
        final rightBias = row == 0 ? 0.0 : 18.0;
        final leftWidth = math.min(
          maxWallWidth + leftBias,
          left - bounds.left - 12,
        );
        if (leftWidth > 14) {
          segments.add(make(Rect.fromLTWH(left - leftWidth, y, leftWidth, 28)));
        }
        final rightWidth = math.min(
          maxWallWidth + rightBias,
          bounds.right - right - 12,
        );
        if (rightWidth > 14) {
          segments.add(make(Rect.fromLTWH(right, y, rightWidth, 28)));
        }
      }
      return segments;
    }

    if (type == ObstacleType.splitWall) {
      final extraGap = math.max(
        PlayabilityValidator.shipWidth + PlayabilityValidator.safetyMargin,
        gapWidth * .72,
      );
      final leftGap = gapCenter - extraGap * .7;
      final rightGap = gapCenter + extraGap * .7;
      final splitterWidth = 28.0;
      final leftInner = leftGap - extraGap / 2;
      final rightInner = rightGap + extraGap / 2;
      final leftWidth = math.min(maxWallWidth, leftInner - bounds.left - 8);
      if (leftWidth > 14) {
        segments.add(
          make(Rect.fromLTWH(leftInner - leftWidth, worldY, leftWidth, wallHeight)),
        );
      }
      segments.add(
        make(
          Rect.fromCenter(
            center: Offset(gapCenter, worldY + wallHeight / 2),
            width: splitterWidth,
            height: wallHeight,
          ),
        ),
      );
      final rightWidth = math.min(maxWallWidth, bounds.right - rightInner - 8);
      if (rightWidth > 14) {
        segments.add(
          make(Rect.fromLTWH(rightInner, worldY, rightWidth, wallHeight)),
        );
      }
      return segments;
    }

    final leftWidth = math.min(maxWallWidth, left - bounds.left - 12);
    if (leftWidth > 14) {
      segments.add(
        make(
          Rect.fromLTWH(
            left - leftWidth,
            worldY,
            type == ObstacleType.laserGate ? math.min(18, leftWidth) : leftWidth,
            wallHeight,
          ),
        ),
      );
    }
    final rightWidth = math.min(maxWallWidth, bounds.right - right - 12);
    if (rightWidth > 14) {
      segments.add(
        make(
          Rect.fromLTWH(
            right,
            worldY,
            type == ObstacleType.laserGate ? math.min(18, rightWidth) : rightWidth,
            wallHeight,
          ),
        ),
      );
    }
    return segments;
  }

  bool _coinPositionIsValid(
    Offset candidate,
    Iterable<Offset> existing,
    Iterable<Rect> blockedRects,
  ) {
    for (final position in existing) {
      if ((candidate - position).distance < minimumCoinDistance) return false;
    }
    final candidateRect = Rect.fromCircle(
      center: candidate,
      radius: coinRadius + 5,
    );
    for (final blocked in blockedRects) {
      if (candidateRect.overlaps(blocked)) return false;
    }
    return true;
  }

  void _spawnCoinTrail() {
    if (coins.length >= balance.maxCoins || size.x <= 0) return;
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
          .clamp(bounds.left - minX, bounds.right - maxX)
          .toDouble();
      final anchor = Offset(anchorX, anchorWorldY);
      final positions = offsets.map((offset) => anchor + offset).toList();
      final valid = positions.every(
        (position) => _coinPositionIsValid(position, existing, blockedRects),
      );
      if (!valid) continue;
      for (final position in positions) {
        if (coins.length >= balance.maxCoins) break;
        final rect = Rect.fromCircle(center: position, radius: coinRadius);
        final coin = _coinPool.acquire(() => Coin(rect));
        coin.recycle(rect);
        coins.add(coin);
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

  void _spawnPickup({PowerId? forced}) {
    if (pickups.length >= balance.maxPickups || size.x <= 0) return;
    final id = forced ?? _assistPower ?? _rarity.pick(_random, _elapsed);
    _assistPower = null;
    final bounds = playableArea.deflate(
      playableArea.width * balance.edgeMarginFactor,
    );
    final spawnScreenY = bounds.top - 48;
    final worldY = _worldYForSpawn(spawnScreenY);
    final blocked = _blockedCoinRects();
    for (var attempt = 0; attempt < 10; attempt++) {
      final jitter = (_random.nextDouble() * 2 - 1) * 42;
      final x = (_lastRouteX + jitter).clamp(bounds.left, bounds.right).toDouble();
      final candidate = Rect.fromCenter(
        center: Offset(x, worldY),
        width: 34,
        height: 34,
      );
      if (blocked.any((rect) => rect.inflate(12).overlaps(candidate))) continue;
      if (!validator.validateReachability(
        fromX: steering.x,
        gapCenter: x,
        gapWidth: 90,
        distance: playerPosition.dy - spawnScreenY,
        speed: math.max(speed.worldScrollSpeed, 100.0),
      )) {
        continue;
      }
      final pickup = _pickupPool.acquire(() => PowerPickup(candidate, id));
      pickup.recycle(candidate, id);
      pickups.add(pickup);
      return;
    }
  }

  void _fireBullet() {
    if (bullets.length >= balance.maxBullets) return;
    final rect = Rect.fromCenter(
      center: playerPosition.translate(0, -33),
      width: 6,
      height: 18,
    );
    final bullet = _bulletPool.acquire(() => Bullet(rect));
    bullet.recycle(rect);
    bullets.add(bullet);
    audio.play(GameSfx.gun);
    _burst(playerPosition.translate(0, -30), const Color(0xffffa25f), 3, .28);
  }

  void _checkBulletImpacts() {
    for (final bullet in bullets.where((item) => item.alive).toList()) {
      for (final group in obstacles) {
        for (final segment in group.segments.where((item) => item.alive)) {
          final definition = obstacleDefinitions[group.type];
          if (definition?.destructible == false) continue;
          final segmentScreen = _worldRectToScreen(segment.worldRect);
          final hit = group.type == ObstacleType.rotatingBar
              ? rotatedRectOverlaps(segmentScreen, group.rotation, bullet.rect)
              : bullet.rect.overlaps(segmentScreen);
          if (hit) {
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
                16,
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
    final shipRect = Rect.fromCenter(
      center: playerPosition,
      width: 40,
      height: 48,
    );
    for (final group in obstacles) {
      for (final segment in group.segments.where(
        (item) => item.alive && item.dangerous,
      )) {
        final segmentScreen = _worldRectToScreen(segment.worldRect);
        final hit = group.type == ObstacleType.rotatingBar
            ? rotatedRectOverlaps(segmentScreen, group.rotation, shipRect)
            : shipRect.overlaps(segmentScreen);
        if (hit) {
          final result = powers.resolveHazardHit();
          if (result == CollisionResult.ignored) continue;
          if (result == CollisionResult.shieldBreak) {
            _impact = 1;
            _banner = 'SHIELD BROKEN';
            _bannerLife = 1;
            _burst(playerPosition, const Color(0xff39efd1), 28, .8);
            audio.play(GameSfx.shieldBreak);
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
            !hit) {
          group.nearMissReported = true;
          _banner = 'NEAR MISS';
          _bannerLife = .45;
          _impact = .25;
          audio.play(GameSfx.nearMiss);
          _burst(playerPosition, const Color(0xff9be7ff), 6, .3);
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
    final gained = scoreboard.collectCoin(
      coinMultiplier: powers.coinMultiplier,
      scoreMultiplier: powers.scoreMultiplier,
    );
    if (floatingTexts.length < balance.maxFloatingTexts) {
      floatingTexts.add(
        FloatingText('+$gained', coinScreen, const Color(0xffffdc52)),
      );
    }
    _burst(coinScreen, const Color(0xffffd74d), 5, .35);
    audio.play(GameSfx.coin);
    _haptic(HapticFeedback.selectionClick);
  }

  void activatePower(PowerId id) {
    powers.activate(id);
    final definition = powerDefinitions[id]!;
    _banner = definition.label;
    _bannerLife = 1.2;
    _burst(ship, definition.color, 18, .65);
    audio.play(id == PowerId.emp ? GameSfx.emp : GameSfx.power);
    analytics.emit(GameAnalyticsEvent.powerPickup, {'id': id.name});
    _haptic(HapticFeedback.mediumImpact);
    speed.setSlowTime(powers.has(PowerId.slowTime));
    speed.setEmp(powers.has(PowerId.emp));
  }

  void _gameOver() {
    flow.enterGameOver();
    scoreboard.frozen = true;
    _newBest = scoreboard.total > bestScore;
    if (_newBest) {
      bestScore = scoreboard.total;
      if (_loadedStorage) unawaited(_saveBest());
      audio.play(GameSfx.highScore);
    } else {
      audio.play(GameSfx.death);
    }
    _impact = 1;
    _banner = _newBest ? 'NEW BEST!' : 'RUN COMPLETE';
    _bannerLife = 1.8;
    _burst(ship, const Color(0xffff735a), 38, 1.1);
    analytics.emit(GameAnalyticsEvent.death, {
      'score': scoreboard.total,
      'elapsed': _elapsed,
    });
    analytics.emit(GameAnalyticsEvent.runEnd, {'score': scoreboard.total});
    _haptic(HapticFeedback.heavyImpact);
    _emit(force: true);
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('space_survival_best', bestScore);
  }

  void _cleanup() {
    final bottomLimit = playableArea.bottom + 60;
    obstacles.removeWhere((group) {
      final gone = group.segments.every(
        (segment) =>
            !segment.alive ||
            _worldRectToScreen(segment.worldRect).top > bottomLimit,
      );
      if (gone) {
        for (final segment in group.segments) {
          _segmentPool.release(segment);
        }
      }
      return gone;
    });
    coins.removeWhere((coin) {
      final gone =
          !coin.alive || _worldToScreen(coin.worldPosition).dy > bottomLimit;
      if (gone) _coinPool.release(coin);
      return gone;
    });
    pickups.removeWhere((pickup) {
      final gone =
          !pickup.alive ||
          _worldRectToScreen(pickup.worldRect).top > bottomLimit;
      if (gone) _pickupPool.release(pickup);
      return gone;
    });
    bullets.removeWhere((bullet) {
      final gone = !bullet.alive || bullet.rect.bottom < -30;
      if (gone) _bulletPool.release(bullet);
      return gone;
    });
    particles.removeWhere((particle) {
      final gone = particle.life <= 0;
      if (gone) _particlePool.release(particle);
      return gone;
    });
    floatingTexts.removeWhere((text) => text.life <= 0);
  }

  void _burst(Offset origin, Color color, int count, double life) {
    for (
      var index = 0;
      index < count && particles.length < balance.maxParticles;
      index++
    ) {
      final angle = _random.nextDouble() * math.pi * 2;
      final velocity = 55 + _random.nextDouble() * 145;
      final particle = _particlePool.acquire(
        () => Particle(origin, Offset.zero, color, life),
      );
      particle.recycle(
        origin,
        Offset(math.cos(angle) * velocity, math.sin(angle) * velocity),
        color,
        life,
        nextSize: 2 + _random.nextDouble() * 3,
      );
      particles.add(particle);
    }
  }

  void _haptic(Future<void> Function() feedback) {
    if (hapticsEnabled) unawaited(feedback());
  }

  void _emit({bool force = false}) {
    final next = GameSnapshot(
      phase: phase,
      score: displayedScore,
      coins: collectedCoins,
      elapsed: _elapsed,
      bestScore: bestScore,
      speed: _effectSpeed,
      activePowers: powers.snapshot(),
      powersUsed: powersUsed,
      destroyed: destroyed,
      newBest: _newBest,
      countdown: phase == GamePhase.countdown || phase == GamePhase.resuming
          ? _countdownLabel
          : '',
      banner: _bannerLife > 0 ? _banner : '',
      hapticsEnabled: hapticsEnabled,
    );
    if (!force && _lastHud != null && next.sameHud(_lastHud!)) return;
    _lastHud = next;
    onSnapshot(next);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final screen = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(screen, Paint()..color = const Color(0xff050914));
    _drawStars(canvas);
    _drawAtmosphere(canvas);
    for (final particle in particles) {
      _drawParticle(canvas, particle);
    }
    for (final coin in coins) {
      _drawCoin(canvas, coin);
    }
    for (final bullet in bullets) {
      _drawBullet(canvas, bullet);
    }
    for (final pickup in pickups) {
      _drawPickup(canvas, pickup);
    }
    _drawShip(canvas);
    for (final group in obstacles) {
      _drawObstacle(canvas, group);
    }
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
    if (debugView && isPlaying) _drawFairnessOverlay(canvas);
    _drawLetterbox(canvas);
    if (_transition > 0) {
      canvas.drawRect(
        screen,
        Paint()..color = Color.fromRGBO(5, 9, 20, _transition),
      );
    }
  }

  void _drawLetterbox(Canvas canvas) {
    final view = viewRect;
    if (view.left <= 1) return;
    final paint = Paint()..color = const Color(0xff02050c);
    canvas.drawRect(Rect.fromLTWH(0, 0, view.left, size.y), paint);
    canvas.drawRect(
      Rect.fromLTWH(view.right, 0, size.x - view.right, size.y),
      paint,
    );
  }

  void _drawFairnessOverlay(Canvas canvas) {
    final y0 = playableArea.top;
    final y1 = playableArea.bottom;
    canvas.drawLine(
      Offset(_lastRouteX, y0),
      Offset(_lastRouteX, y1),
      Paint()
        ..color = const Color(0x6639efd1)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(_lastRouteX - _lastGapWidth / 2, y0 + 40),
      Offset(_lastRouteX + _lastGapWidth / 2, y0 + 40),
      Paint()
        ..color = const Color(0x99ffe27a)
        ..strokeWidth = 2,
    );
  }

  void _drawStars(Canvas canvas) {
    for (var index = 0; index < _stars.length; index++) {
      final seed = _stars[index];
      final layer = index % 3;
      final parallax = (layer + 1) * (.12 + _effectSpeed / 2400);
      final y = (seed.dy + _starOffset * parallax) % size.y;
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
        colors: [Color(0xff0b1630), Color(0x000b1630)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(area);
    canvas.drawRect(area, paint);
    final linePaint = Paint()
      ..color = const Color(0xff2d76a9).withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var y = area.top; y < area.bottom; y += 110) {
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), linePaint);
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
        RRect.fromRectAndRadius(screenRect.inflate(3), const Radius.circular(6)),
        glow,
      );
      final paint = Paint()
        ..color = color.withValues(alpha: segment.damageFlash > 0 ? 1 : .82);
      if (group.type == ObstacleType.asteroidCluster ||
          group.type == ObstacleType.mineField) {
        canvas.drawCircle(screenRect.center, screenRect.width / 2, paint);
        canvas.drawCircle(
          screenRect.center,
          screenRect.width / 2 + 5 + math.sin(group.age * 5) * 2,
          Paint()
            ..color = color.withValues(alpha: .24)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      } else if (group.type == ObstacleType.laserGate) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(screenRect, const Radius.circular(8)),
          paint,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: screenRect.center,
            width: 4,
            height: screenRect.height + 10,
          ),
          Paint()..color = const Color(0xfffff1f6).withValues(alpha: .55),
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
        if (segment.crackStage >= 1) {
          final crack = Paint()
            ..color = const Color(0xff09111e).withValues(alpha: .55)
            ..strokeWidth = 1.4;
          canvas.drawLine(
            screenRect.topLeft + Offset(8, screenRect.height * .35),
            screenRect.bottomRight - Offset(10, screenRect.height * .2),
            crack,
          );
          if (segment.crackStage >= 2) {
            canvas.drawLine(
              screenRect.topCenter + const Offset(0, 4),
              screenRect.bottomLeft + const Offset(12, -4),
              crack,
            );
          }
        }
        if (group.type == ObstacleType.electricField) {
          final zap = Paint()
            ..color = const Color(0xffd7b8ff).withValues(alpha: .7)
            ..strokeWidth = 1.2;
          for (var i = 0; i < 3; i++) {
            final y = screenRect.top + 8 + i * 10;
            canvas.drawLine(
              Offset(screenRect.left + 4, y),
              Offset(screenRect.right - 4, y + math.sin(group.age * 12 + i) * 4),
              zap,
            );
          }
        }
      }
      canvas.restore();
    }
  }

  void _drawCoin(Canvas canvas, Coin coin) {
    final center = _worldToScreen(coin.worldPosition);
    final appear = math.min(1, coin.spawnAge * 6);
    final radius =
        coin.rect.width / 2 * (1 + math.sin(coin.pulse) * .06) * appear;
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
    final fade = pickup.age > 9 ? (10.5 - pickup.age).clamp(0.0, 1.0) : 1.0;
    canvas.drawCircle(
      center,
      24 * scale,
      Paint()
        ..color = definition.color.withValues(alpha: .14 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      center,
      17 * scale,
      Paint()..color = const Color(0xff111b2e).withValues(alpha: fade),
    );
    canvas.drawCircle(
      center,
      17 * scale,
      Paint()
        ..color = definition.color.withValues(alpha: .9 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _drawText(
      canvas,
      definition.symbol,
      center,
      definition.color.withValues(alpha: fade),
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
    if (playerPosition == Offset.zero && size.x <= 0) return;
    final opacity = powers.dashing
        ? .38
        : powers.cloaked
        ? .48
        : 1.0;
    final shift = (steering.targetX - steering.x).clamp(-45, 45) / 45;
    canvas.save();
    canvas.translate(
      playerPosition.dx,
      playerPosition.dy + math.sin(_elapsed * 3.2) * 2,
    );
    canvas.rotate(shift * .16);
    final flameLength = 20 + speed.difficultySpeed / 55;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 30), width: 13, height: flameLength),
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
    if (powers.has(PowerId.magnet)) {
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
    )..layout(maxWidth: math.max(20, size.x - 20));
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
