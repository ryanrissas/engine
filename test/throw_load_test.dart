// Throwing load and its acute:chronic ratio (compute/throw_load.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/throw_load.dart';

String _d(int i) =>
    DateTime.utc(2026, 8, 1 + i).toIso8601String().substring(0, 10);

void main() {
  test('keys round-trip and unknown kinds are refused', () {
    expect(throwTypeOf(throwKey('bullpen')), 'bullpen');
    expect(throwTypeOf('throw_nonsense'), isNull);
    expect(throwTypeOf('bench_press'), isNull);
    expect(isThrowKey('throw_game'), isTrue);
  });

  test('session load weighs kind and intent', () {
    expect(sessionThrowLoad(const [ThrowEntry('game', 80, 10)]), 80);
    expect(sessionThrowLoad(const [ThrowEntry('catch_play', 40, 5)]),
        closeTo(40 * 0.3 * 0.5, 1e-9));
    expect(sessionThrowLoad(const []), isNull);
    expect(sessionThrowLoad(const [ThrowEntry('game', 0, 8)]), isNull);
  });

  test('no ratio before three weeks of history', () {
    final days = [for (var i = 0; i < 10; i++) ThrowDay(_d(i), 30)];
    final r = throwAcwr(days);
    expect(r.ratio, isNull);
    expect(r.why, startsWith('need_history'));
    expect(throwAcwr([ThrowDay(_d(0), 0)]).why, 'no_throws_logged');
  });

  test('a steady routine reads about 1; a spike reads above the line', () {
    final steady = [
      for (var i = 0; i < 42; i++) ThrowDay(_d(i), i % 2 == 0 ? 40 : 0),
    ];
    final s = throwAcwr(steady).ratio!;
    expect(s.ratio, closeTo(1.0, 0.25));
    final spike = [
      for (var i = 0; i < 35; i++) ThrowDay(_d(i), i % 2 == 0 ? 40 : 0),
      for (var i = 35; i < 42; i++) ThrowDay(_d(i), 90),
    ];
    final p = throwAcwr(spike).ratio!;
    expect(p.ratio, greaterThan(kThrowAcwrCaution));
    expect(p.aboveCaution, isTrue);
  });

  test('an unlogged Baseball day is unknown, never zero', () {
    final days = [
      for (var i = 0; i < 30; i++) ThrowDay(_d(i), 40),
    ];
    days[25] = ThrowDay(_d(25), null);
    final r = throwAcwr(days);
    expect(r.ratio, isNull);
    expect(r.why, 'unlogged_sessions:n=1');
    // Three clean weeks after it and the ratio comes back.
    final later = [...days, for (var i = 30; i < 50; i++) ThrowDay(_d(i), 40)];
    expect(throwAcwr(later).ratio, isNotNull);
  });
}
