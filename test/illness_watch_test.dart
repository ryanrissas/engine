// Illness watch (compute/illness_watch.dart) and its finding.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/findings.dart';
import 'package:openstrap_edge/compute/illness_watch.dart';

String _d(int i) =>
    DateTime.utc(2026, 9, 1 + i).toIso8601String().substring(0, 10);

/// [n] ordinary nights with real spread, then the overrides.
({List<String> dates, List<double?> rhr, List<double?> resp, List<double?> hrv})
    _nights(int n) => (
          dates: [for (var i = 0; i < n; i++) _d(i)],
          rhr: [for (var i = 0; i < n; i++) 48.0 + (i % 3) - 1],
          resp: [for (var i = 0; i < n; i++) 14.0 + 0.3 * ((i % 5) - 2)],
          hrv: [for (var i = 0; i < n; i++) 100.0 + 6 * ((i % 4) - 1.5)],
        );

List<IllnessWatchNight?> _run(
        ({List<String> dates, List<double?> rhr, List<double?> resp, List<double?> hrv}) x,
        {List<bool>? unsettled}) =>
    illnessWatch(
      dates: x.dates,
      rhr: x.rhr,
      resp: x.resp,
      rmssd: x.hrv,
      unsettled: unsettled ?? List.filled(x.dates.length, false),
    );

void main() {
  test('ordinary nights are clear', () {
    final out = _run(_nights(30));
    expect(out.last!.level, IllnessWatchLevel.clear);
    expect(out.last!.judged, 3);
  });

  test('one signal alone is not yellow', () {
    final x = _nights(30);
    x.rhr[29] = 56;
    expect(_run(x).last!.level, IllnessWatchLevel.clear);
    expect(_run(x).last!.signals, ['rhr']);
  });

  test('two signals make yellow; a second yellow night makes red', () {
    final x = _nights(31);
    for (final i in [29, 30]) {
      x.rhr[i] = 56;
      x.resp[i] = 17.5;
    }
    final out = _run(x);
    expect(out[29]!.level, IllnessWatchLevel.yellow);
    expect(out[30]!.level, IllnessWatchLevel.red);
    expect(out[30]!.signals, containsAll(['rhr', 'resp']));
  });

  test('a calendar gap breaks the run', () {
    final x = _nights(31);
    for (final i in [29, 30]) {
      x.rhr[i] = 56;
      x.hrv[i] = 40;
    }
    x.dates[30] = _d(32); // a missing day between them
    expect(_run(x)[30]!.level, IllnessWatchLevel.yellow);
  });

  test('unsettled nights are not judged and do not feed baselines', () {
    final x = _nights(31);
    for (final i in [29, 30]) {
      x.rhr[i] = 56;
      x.resp[i] = 17.5;
    }
    final u = List.filled(31, false)..[30] = true;
    final out = _run(x, unsettled: u);
    expect(out[30], isNull);
    expect(out[29]!.level, IllnessWatchLevel.yellow);
  });

  test('too little history → no verdict, not a green one', () {
    final out = _run(_nights(5));
    expect(out.every((v) => v == null), isTrue);
  });

  test('a red night is a medical finding; yellow is not', () {
    final red = crossDayAlertFindings({
      'illness_watch': {'date': '2026-10-01', 'level': 'red'},
    });
    expect(red.single.kind, FindingKind.illnessWatch);
    expect(red.single.medical, isTrue);
    expect(red.single.detail, contains('not a diagnosis'));
    expect(
        crossDayAlertFindings({
          'illness_watch': {'date': '2026-10-01', 'level': 'yellow'},
        }),
        isEmpty);
  });

  test('history log carries red nights from recent rows', () {
    final f = findingsHistory({
      'recent': [
        {'date': '2026-10-01', 'illness_watch': 'yellow'},
        {'date': '2026-10-02', 'illness_watch': 'red'},
      ],
    });
    expect(f.map((e) => e.kind), [FindingKind.illnessWatch]);
    expect(f.single.date, '2026-10-02');
  });
}
