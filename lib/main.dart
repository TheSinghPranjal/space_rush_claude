import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/models.dart';
import 'game/space_survival_game.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SpaceSurvivalApp());
}

class SpaceSurvivalApp extends StatefulWidget {
  const SpaceSurvivalApp({super.key});
  @override
  State<SpaceSurvivalApp> createState() => _SpaceSurvivalAppState();
}

class _SpaceSurvivalAppState extends State<SpaceSurvivalApp>
    with WidgetsBindingObserver {
  late final ValueNotifier<GameSnapshot> _snapshot;
  late final SpaceSurvivalGame _game;
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapshot = ValueNotifier(_emptySnapshot());
    _game = SpaceSurvivalGame(onSnapshot: (state) => _snapshot.value = state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _game.onAppInactive();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Space Survival',
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    home: Scaffold(
      body: Stack(
        children: [
          GameWidget<SpaceSurvivalGame>(game: _game),
          Positioned.fill(
            child: GameInterface(
              game: _game,
              snapshot: _snapshot,
              onTutorial: () => setState(() => _showTutorial = true),
            ),
          ),
          if (_showTutorial)
            TutorialSheet(onClose: () => setState(() => _showTutorial = false)),
        ],
      ),
    ),
  );
}

GameSnapshot _emptySnapshot() => const GameSnapshot(
  phase: GamePhase.home,
  score: 0,
  coins: 0,
  elapsed: 0,
  bestScore: 0,
  speed: 220,
  activePowers: [],
  powersUsed: 0,
  destroyed: 0,
  newBest: false,
);

class GameInterface extends StatelessWidget {
  const GameInterface({
    super.key,
    required this.game,
    required this.snapshot,
    required this.onTutorial,
  });
  final SpaceSurvivalGame game;
  final ValueListenable<GameSnapshot> snapshot;
  final VoidCallback onTutorial;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameSnapshot>(
    valueListenable: snapshot,
    builder: (context, state, _) {
      final media = MediaQuery.sizeOf(context);
      final width = math.min(media.width, math.max(320.0, media.height * 9 / 20));
      return ColoredBox(
        color: Colors.transparent,
        child: switch (state.phase) {
          GamePhase.paused => PauseOverlay(game: game, snapshot: state),
          GamePhase.gameOver => GameOverOverlay(game: game, snapshot: state),
          _ => Align(
            child: SizedBox(
              width: width,
              height: media.height,
              child: SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey(
                      state.phase == GamePhase.home ? 'home' : 'play',
                    ),
                    child: state.phase == GamePhase.home
                        ? HomeOverlay(
                            game: game,
                            snapshot: state,
                            onTutorial: onTutorial,
                          )
                        : PlayOverlay(game: game, snapshot: state),
                  ),
                ),
              ),
            ),
          ),
        },
      );
    },
  );
}

class HomeOverlay extends StatelessWidget {
  const HomeOverlay({
    super.key,
    required this.game,
    required this.snapshot,
    required this.onTutorial,
  });
  final SpaceSurvivalGame game;
  final GameSnapshot snapshot;
  final VoidCallback onTutorial;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
    child: Column(
      children: [
        const Spacer(flex: 2),
        const Icon(
          Icons.rocket_launch_rounded,
          color: Color(0xff78e9ff),
          size: 66,
        ),
        const SizedBox(height: 22),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xffffffff), Color(0xff65e9ff)],
          ).createShader(bounds),
          child: const Text(
            'SPACE\nSURVIVAL',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 43,
              height: .88,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'ENDLESS ARCADE FLIGHT',
          style: TextStyle(
            color: Color(0xff88a6c5),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.3,
          ),
        ),
        const Spacer(),
        if (snapshot.bestScore > 0)
          _StatChip(
            icon: Icons.workspace_premium_rounded,
            label: 'BEST',
            value: snapshot.bestScore.toString(),
          ),
        const SizedBox(height: 18),
        PulseNeonButton(
          label: 'PLAY',
          icon: Icons.play_arrow_rounded,
          onPressed: game.start,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onTutorial,
          icon: const Icon(Icons.help_outline_rounded, size: 18),
          label: const Text('HOW TO PLAY'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xffb8d2ea),
            side: const BorderSide(color: Color(0xff31516e)),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: game.toggleHaptics,
          icon: Icon(
            snapshot.hapticsEnabled
                ? Icons.vibration_rounded
                : Icons.vibration_outlined,
            size: 16,
          ),
          label: Text(snapshot.hapticsEnabled ? 'HAPTICS ON' : 'HAPTICS OFF'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xff6d91ae)),
        ),
      ],
    ),
  );
}

class PlayOverlay extends StatelessWidget {
  const PlayOverlay({super.key, required this.game, required this.snapshot});
  final SpaceSurvivalGame game;
  final GameSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final countdown =
        snapshot.phase == GamePhase.countdown ||
        snapshot.phase == GamePhase.resuming;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScoreBlock(
                score: snapshot.score,
                time: snapshot.elapsed,
                coins: snapshot.coins,
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: game.requestPause,
                icon: const Icon(Icons.pause_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(
                    0xff142239,
                  ).withValues(alpha: .88),
                  foregroundColor: const Color(0xffddf5ff),
                ),
              ),
            ],
          ),
        ),
        if (snapshot.activePowers.isNotEmpty)
          Positioned(
            top: 76,
            left: 15,
            right: 15,
            child: PowerHud(active: snapshot.activePowers),
          ),
        if (countdown)
          Center(
            child: Text(
              snapshot.countdown,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 78,
                shadows: [Shadow(color: Color(0xff39e9ff), blurRadius: 26)],
              ),
            ),
          ),
        if (game.debugView)
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: DebugHud(game: game),
          ),
      ],
    );
  }
}

class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.game, required this.snapshot});
  final SpaceSurvivalGame game;
  final GameSnapshot snapshot;
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xff02050c).withValues(alpha: .7),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.pause_circle_outline_rounded,
              color: Color(0xff79e8ff),
              size: 55,
            ),
            const SizedBox(height: 14),
            const Text(
              'PAUSED',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Your run is safely frozen.',
              style: TextStyle(color: Color(0xff9db6ca)),
            ),
            const SizedBox(height: 28),
            NeonButton(
              label: 'RESUME',
              icon: Icons.play_arrow_rounded,
              onPressed: game.resume,
            ),
            const SizedBox(height: 12),
            _SecondaryAction(
              label: 'RESTART',
              icon: Icons.refresh_rounded,
              onPressed: game.restart,
            ),
            _SecondaryAction(
              label: 'HOME',
              icon: Icons.home_outlined,
              onPressed: game.returnHome,
            ),
            _SecondaryAction(
              label: snapshot.hapticsEnabled ? 'HAPTICS ON' : 'HAPTICS OFF',
              icon: Icons.tune_rounded,
              onPressed: game.toggleHaptics,
            ),
          ],
        ),
      ),
    ),
  );
}

class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.game,
    required this.snapshot,
  });
  final SpaceSurvivalGame game;
  final GameSnapshot snapshot;
  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> {
  bool _locked = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _locked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final game = widget.game;
    return AbsorbPointer(
      absorbing: _locked,
      child: Container(
        color: const Color(0xff050811).withValues(alpha: .62),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Column(
              children: [
                Text(
                  snapshot.newBest ? 'NEW BEST!' : 'MISSION OVER',
                  style: TextStyle(
                    color: snapshot.newBest
                        ? const Color(0xffffd252)
                        : const Color(0xffff8b7a),
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.score}',
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const Text(
                  'FINAL SCORE',
                  style: TextStyle(
                    color: Color(0xff9fb8cc),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 22),
                _ResultsCard(snapshot: snapshot),
                const SizedBox(height: 22),
                NeonButton(
                  label: 'FLY AGAIN',
                  icon: Icons.refresh_rounded,
                  onPressed: game.restart,
                ),
                const SizedBox(height: 10),
                _SecondaryAction(
                  label: 'HOME',
                  icon: Icons.home_outlined,
                  onPressed: game.returnHome,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.snapshot});
  final GameSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final rows = [
      ('SURVIVAL TIME', '${snapshot.elapsed.toStringAsFixed(1)} s'),
      ('COINS', '${snapshot.coins}'),
      ('BEST SCORE', '${snapshot.bestScore}'),
      ('MAX SPEED', snapshot.speed.toStringAsFixed(0)),
      ('POWERS USED', '${snapshot.powersUsed}'),
      ('SEGMENTS DESTROYED', '${snapshot.destroyed}'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff101a2b).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xff375a79)),
      ),
      child: Column(
        children: rows
            .map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      row.$1,
                      style: const TextStyle(
                        color: Color(0xff98b1c6),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: .7,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      row.$2,
                      style: const TextStyle(
                        color: Color(0xffeff8ff),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class PowerHud extends StatelessWidget {
  const PowerHud({super.key, required this.active});
  final List<ActivePower> active;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: active.map((power) {
      final definition = powerDefinitions[power.id]!;
      final urgent = power.remaining <= 2;
      return AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: urgent ? 1.08 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Color(urgent ? 0xff3a1c14 : 0xff0d1a2c).withValues(alpha: .91),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: definition.color.withValues(alpha: urgent ? 1 : .55),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                definition.symbol,
                style: TextStyle(
                  color: definition.color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                urgent
                    ? '${definition.label} ${power.remaining.toStringAsFixed(1)}s'
                    : '${power.remaining.toStringAsFixed(1)}s',
                style: TextStyle(
                  color: urgent ? const Color(0xffffe1c4) : const Color(0xffdbeeff),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({
    required this.score,
    required this.time,
    required this.coins,
  });
  final int score;
  final double time;
  final int coins;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xff101b2d).withValues(alpha: .84),
      border: Border.all(color: const Color(0xff2d526f)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$score',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            height: .9,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${time.toStringAsFixed(1)} s  •  ◉ $coins',
          style: const TextStyle(
            color: Color(0xff9cb9d0),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xff142239).withValues(alpha: .8),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xff304e6c)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xffffd356)),
        const SizedBox(width: 6),
        Text(
          '$label  $value',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xffd8e8f5),
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      ],
    ),
  );
}

class PulseNeonButton extends StatefulWidget {
  const PulseNeonButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  State<PulseNeonButton> createState() => _PulseNeonButtonState();
}

class _PulseNeonButtonState extends State<PulseNeonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final glow = 16 + _controller.value * 10;
      return Transform.scale(
        scale: .985 + _controller.value * .03,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0x8837dffb),
                blurRadius: glow,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
      );
    },
    child: NeonButton(
      label: widget.label,
      icon: widget.icon,
      onPressed: widget.onPressed,
      glow: false,
    ),
  );
}

class DebugHud extends StatelessWidget {
  const DebugHud({super.key, required this.game});
  final SpaceSurvivalGame game;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: const Color(0xcc071018),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xff2d536d)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          game.debugLine,
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: Color(0xff9be7ff),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final id in PowerId.values)
              GestureDetector(
                onTap: () => game.debugSpawn(id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff132235),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    powerDefinitions[id]!.symbol,
                    style: TextStyle(
                      color: powerDefinitions[id]!.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.glow = true,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool glow;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (glow)
            const BoxShadow(
              color: Color(0x6637dffb),
              blurRadius: 20,
              spreadRadius: 1,
            ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(
            letterSpacing: 1.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xff37cdec),
          foregroundColor: const Color(0xff04101d),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
  );
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(
        label,
        style: const TextStyle(letterSpacing: 1.1, fontWeight: FontWeight.bold),
      ),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xffb5cee2),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
    ),
  );
}

class TutorialSheet extends StatelessWidget {
  const TutorialSheet({super.key, required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff070c16).withValues(alpha: .96),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'FLIGHT BRIEFING',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Icon(Icons.swipe_rounded, color: Color(0xff62e4ff), size: 46),
            const SizedBox(height: 10),
            const Text(
              'DRAG TO STEER',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
            const Text(
              'Drag left and right only. The ship stays on a fixed flight line.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xffa5bbcd)),
            ),
            const SizedBox(height: 26),
            const _TutorialLine(
              icon: '◉',
              color: Color(0xffffd84a),
              title: 'COLLECT COINS',
              detail: 'Coins add to your run score.',
            ),
            const _TutorialLine(
              icon: '⌁',
              color: Color(0xff39e7ff),
              title: 'USE POWERS',
              detail:
                  'Magnet, gun, shield, time control and rare tactical powers stack.',
            ),
            const _TutorialLine(
              icon: '⬡',
              color: Color(0xff48eed3),
              title: 'SHIELD',
              detail: 'Absorbs one collision, then breaks.',
            ),
            const _TutorialLine(
              icon: 'ϟ',
              color: Color(0xffbd82ff),
              title: 'EMP',
              detail: 'Freezes obstacles briefly. They remain dangerous.',
            ),
            const _TutorialLine(
              icon: '✦',
              color: Color(0xffff855c),
              title: 'PLASMA GUN',
              detail: 'Breaks destructible segments to open a route.',
            ),
            const Spacer(),
            NeonButton(
              label: 'UNDERSTOOD',
              icon: Icons.check_rounded,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    ),
  );
}

class _TutorialLine extends StatelessWidget {
  const _TutorialLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });
  final String icon;
  final Color color;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 35,
          height: 35,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: .13),
            border: Border.all(color: color.withValues(alpha: .7)),
          ),
          child: Text(
            icon,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  color: Color(0xffa5bbcd),
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
