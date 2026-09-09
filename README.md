# Space Survival

A portrait-first Flame and Flutter endless survival game. Drag the ship horizontally, collect coins and stack powers while a fairness validator keeps each generated route reachable.

## Run

```sh
flutter pub get
flutter run
```

## Included systems

- Flame delta-time game loop with home, countdown, play, pause, and game-over states.
- Smooth cumulative 10% speed steps every 60 seconds, with Slow Time and EMP as composable speed modifiers.
- Ten configurable powers: Magnet, Plasma Gun, Cloak, Slow Time, Shield, Double Score, Coin Multiplier, EMP, Turbo Collect, and Phase Dash.
- Procedural walls, lasers, asteroids, mines, pistons, rotating bars, electric fields, split walls, zigzags, and breakable segments.
- Shared preferences for best score and haptics, lifecycle-safe auto-pause, deterministic power timers, and a debug overlay hook.
- Vector-rendered visuals with bounded active entity counts and no external art dependency.

The playability rules and speed milestones are covered by focused unit tests in `test/game_rules_test.dart`.
