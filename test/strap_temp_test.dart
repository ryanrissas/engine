// The WHOOP 4.0 strap temperature (compute/strap_temp.dart) and its use in
// place of the 1 Hz "skin temp" u16, which is not a temperature.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';
import 'package:openstrap_edge/compute/strap_temp.dart';

// A real event-63 inner record from a WHOOP 4.0 (body rev 1, 28 bytes):
// millivolts 0x0f2f = 3887 at body[5], temperature 0x0120 = 288 → 28.8 °C.
const _ev63 =
    '304d3f0091c6ce6a50451c000140fd9efd2f0f200108004904be03130802000d0100001a00000000';

void main() {
  test('decodes the strap temperature from event 63', () {
    expect(strapTempFromEventHex(_ev63), closeTo(28.8, 1e-9));
  });

  test('refuses other events, other body revisions and implausible values', () {
    // Event id 64.
    expect(strapTempFromEventHex(_ev63.replaceRange(4, 6, '40')), isNull);
    // Body revision 3 (gen5): no temperature known there.
    expect(strapTempFromEventHex(_ev63.replaceRange(24, 26, '03')), isNull);
    // 0x0000 → 0 °C: not a reading.
    expect(strapTempFromEventHex(_ev63.replaceRange(38, 42, '0000')), isNull);
    expect(strapTempFromEventHex('30'), isNull);
  });

  group('nightlyStrapTemp', () {
    const on = 1786700000;
    final ts = [for (var i = 0; i < 160; i++) on + i * 180]; // 8 h
    final c = [for (var i = 0; i < 160; i++) 33.0 + (i % 3) * 0.1];

    test('median of the settled night, first hour excluded', () {
      final r = nightlyStrapTemp(
          tsSec: ts, tempC: c, onsetSec: on, offsetSec: on + 8 * 3600)!;
      expect(r.medianC, closeTo(33.1, 1e-9));
      expect(r.samples, lessThan(160 - 19));
      expect(r.settledFraction, 1.0);
    });

    test('charging and the hour after it are excluded', () {
      final hot = [...c];
      for (var i = 60; i < 80; i++) {
        hot[i] = 40.0;
      }
      final r = nightlyStrapTemp(
        tsSec: ts,
        tempC: hot,
        onsetSec: on,
        offsetSec: on + 8 * 3600,
        chargingSpans: [
          [ts[60], ts[79]],
        ],
      )!;
      expect(r.medianC, lessThan(34));
    });

    test('too few samples → null, never a guess', () {
      expect(
          nightlyStrapTemp(
              tsSec: ts.sublist(0, 40),
              tempC: c.sublist(0, 40),
              onsetSec: on,
              offsetSec: on + 2 * 3600),
          isNull);
    });
  });

  group('in the day bundle (gen4)', () {
    const t0 = 1786700000;
    Map<String, dynamic> bundle({List<double> history = const []}) {
      const n = 8 * 3600;
      final ts = <int>[for (var i = 0; i < n; i++) t0 + i];
      return deriveDayBundle(DayBundleInput(
        date: '2026-08-15',
        dayTsSec: ts,
        dayHr: List<int>.filled(ts.length, 55),
        sleepTsSec: ts,
        sleepHr: List<int>.filled(ts.length, 55),
        sleepRrTsMs: const [],
        sleepRrMs: const [],
        // The 1 Hz u16 is present — and must not be read on gen4.
        sleepSkinTemp: List<int>.filled(ts.length, 3000),
        sleepJson: const {
          'tst_sec': n,
          'in_bed_sec': n,
          'window': {
            'onset_ms': t0 * 1000,
            'offset_ms': (t0 + n) * 1000,
          },
        },
        hypnoStages: List<String>.filled(n, 'light'),
        sleepOnsetSec: t0,
        sleepOffsetSec: t0 + n,
        profile: const {'age': 23, 'sex': 'm'},
        deviceFamily: 'gen4',
        strapTempTs: [for (var i = 0; i < 160; i++) t0 + i * 180],
        strapTempC: [for (var i = 0; i < 160; i++) 33.0 + (i % 3) * 0.1],
        strapTempHistory: history,
      ).toJson());
    }

    test('publishes the strap temperature, never the 1 Hz u16', () {
      final sc = (bundle()['scalars'] as Map).cast<String, dynamic>();
      expect(sc['skin_temp_adc'], isNull);
      expect(sc['strap_temp_c'], closeTo(33.1, 1e-9));
      expect(sc['skin_temp_z'], isNull); // no baseline yet
    });

    test('scores a deviation against its own nights', () {
      final b = bundle(history: [32.5, 32.7, 32.6, 32.4]);
      final sc = (b['scalars'] as Map).cast<String, dynamic>();
      expect(sc['skin_temp_z'], greaterThan(2));
      final w = ((b['wellness'] as Map)['skin_temp'] as Map);
      expect(w['delta_c'], closeTo(0.55, 1e-9));
    });
  });
}
