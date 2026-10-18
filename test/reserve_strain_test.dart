// The 0–21 strain on WHOOP's published structure (compute/reserve_strain.dart)
// and the max heart rate it is priced on (compute/hr_max.dart).
//
// The anchors are WHOOP's own published values: 1 h walk ≈ 6.5 and 1 h run ≈
// 12.0 (WHOOP Strain Coach, 2019), a 45-min run 12–15 (WHOOP, 2026), 24 h at
// max = 21 (WHOOP's definition of the top of the scale). The reserve each
// effort sits at (walk 35 %, run 72 %, hard run 82 %) is our assumption.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/hr_max.dart';
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/reserve_strain.dart';

const _rhr = 50.0, _max = 190.0;

/// A per-minute series of [minutes] at reserve fraction [hrr].
List<double> _at(int minutes, double hrr) =>
    List.filled(minutes, _rhr + hrr * (_max - _rhr));

double _s(List<double> hr) => reserveStrain(hr, restingHr: _rhr, maxHr: _max)!;

void main() {
  group('reserve strain lands on WHOOP\'s published anchors', () {
    test('1 h walk ≈ 6.5', () => expect(_s(_at(60, 0.35)), closeTo(6.5, 0.5)));
    test('1 h run ≈ 12', () => expect(_s(_at(60, 0.72)), closeTo(12.0, 0.5)));
    test('45-min hard run inside 12–15',
        () => expect(_s(_at(45, 0.82)), inInclusiveRange(12.0, 15.0)));
    test('24 h at max is 21', () => expect(_s(_at(1440, 1.0)), closeTo(21, 1e-9)));
    test('a quiet day stays light (under 10)', () {
      expect(_s([..._at(480, 0.03), ..._at(960, 0.15)]), lessThan(10));
    });
  });

  test('harder and longer always score higher', () {
    expect(_s(_at(60, 0.80)), greaterThan(_s(_at(60, 0.70))));
    expect(_s(_at(90, 0.70)), greaterThan(_s(_at(60, 0.70))));
    expect(strainMinuteWeight(0), 0);
    expect(strainMinuteWeight(1), closeTo(1, 1e-12));
  });

  test('the curve only builds, and its last point is the headline', () {
    final hr = [..._at(30, 0.75), ..._at(120, 0.05), ..._at(20, 0.6)];
    final curve = reserveStrainCurve(hr, restingHr: _rhr, maxHr: _max)!;
    for (var i = 1; i < curve.length; i++) {
      expect(curve[i], greaterThanOrEqualTo(curve[i - 1]));
    }
    expect(curve.last, closeTo(_s(hr), 1e-9));
  });

  test('absent — never 0 — without a resting HR or a valid minute', () {
    expect(reserveStrain(_at(60, 0.7), restingHr: null, maxHr: _max), isNull);
    expect(reserveStrain(_at(60, 0.7), restingHr: _rhr, maxHr: null), isNull);
    expect(reserveStrain(const [0, 0, 0], restingHr: _rhr, maxHr: _max),
        isNull);
  });

  test('workout strain and day strain are one method', () {
    final hr = _at(45, 0.7);
    expect(
      strainFromPerMinuteHr(hr,
          profile: const Profile(), restingHr: _rhr, hrMax: _max),
      closeTo(_s(hr), 1e-9),
    );
  });

  group('max heart rate, in WHOOP\'s order', () {
    test('starts from Gellish: 192 − 0.007·age²', () {
      expect(estimatedMaxHr(23, null), closeTo(188.297, 1e-3));
      expect(estimatedMaxHr(null, null), isNull);
    });
    test('raised — never lowered — by the held ceiling', () {
      expect(trainingMaxHr(age: 23, observedCeilingBpm: 196), 196);
      expect(trainingMaxHr(age: 23, observedCeilingBpm: 160),
          closeTo(188.297, 1e-3));
    });
    test('a tested max wins outright', () {
      expect(
          trainingMaxHr(age: 23, observedCeilingBpm: 196, manualMaxHr: 201),
          201);
      expect(manualMaxHrFromProfile({'max_hr': 201}), 201);
      expect(manualMaxHrFromProfile({'max_hr': 1900}), isNull);
      expect(Profile.fromMap({'max_hr': 201}).maxHrManual, 201);
    });
    test('zones band on the tested max', () {
      final z = trainingZones(age: 23, manualMaxHr: 201)!;
      expect(z.source, 'manual_max');
      expect(z.maxHr, 201);
    });
  });
}
