import 'package:flutter_test/flutter_test.dart';
import 'package:space_rush_claude/game/models.dart';

void main() {
  test('app game models load', () {
    expect(GamePhase.home, isNotNull);
  });
}
