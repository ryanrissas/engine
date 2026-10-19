// STRAP TEMPERATURE on a WHOOP 4.0 (v118).
//
// The 1 Hz record's "skin temperature" u16 (inner[68]) is NOT a temperature:
// it moves 5–15 counts a second while the heart rate in the same records
// moves under 1 bpm/s (protocol/lib/src/records.dart, `skinTempRaw`). Until
// v118 it still fed readiness's temperature driver and the illness check on
// gen4 bands. It no longer does.
//
// What the band DOES carry: EXTENDED_BATTERY_INFORMATION (event 63, body
// revision 1, gen4) has, beside the millivolts at body[5] and the charge
// counter at body[11], a u16 LE at body[7] that behaves like a temperature in
// 0.1 °C on the wearer's own data (research_notes/gaps/temp_spo2.md §2c):
//   * 22.6–45.3 °C overall; median 39.8 on the charger vs 29.3 off it;
//   * uncorrelated with battery voltage (r = 0.06);
//   * higher asleep than awake (31.1 vs 28.4), rising 25 → 34 within three
//     hours of sleep onset — the warming of a strap against skin under covers.
// That is a temperature INSIDE THE STRAP (most likely the battery fuel
// gauge's): it sees skin, ambient and bedding, and charging swamps it. So it
// is shown as "strap temperature vs your normal", never as skin temperature,
// and only ever read RELATIVE to the wearer's own nights. The 0.1 °C scale is
// inferred (no reference thermometer); a deviation in it is still a
// deviation in the same unit night to night.
//
// Nightly value (ours, from the note's recipe): the MEDIAN of the samples
// from sleep onset + 60 min to wake, none during charging or in the hour
// after it, at least [kStrapTempMinSamples] of them.
//
// Pure and isolate-safe.

import 'dart:typed_data';

/// Event id of EXTENDED_BATTERY_INFORMATION.
const int kStrapTempEventId = 63;

/// Samples needed for a nightly value (~every 3 min → 90 min of sleep).
const int kStrapTempMinSamples = 30;

/// Settle time after sleep onset and after charging (s).
const int kStrapTempSettleSec = 3600;

/// Plausible range for the field (°C); anything else is not a reading.
const double kStrapTempMinC = 15, kStrapTempMaxC = 45;

/// Strap temperature (°C) out of an event-63 INNER record (starting at the
/// 0x30 packet type), or null when it is not a gen4 revision-1 body.
///
/// Envelope: `[0x30][seq][u16 id][u32 unix][u16 subsec][u16 bodyLen][body]`,
/// so the body starts at inner[12].
double? strapTempFromEventInner(Uint8List inner) {
  if (inner.length < 21 || inner[0] != 0x30) return null;
  final id = inner[2] | (inner[3] << 8);
  if (id != kStrapTempEventId) return null;
  final bodyLen = inner[10] | (inner[11] << 8);
  if (bodyLen < 9 || inner.length < 12 + 9) return null;
  if (inner[12] != 1) return null; // body revision 1 = gen4 only
  final raw = inner[19] | (inner[20] << 8);
  final c = raw / 10.0;
  if (c < kStrapTempMinC || c > kStrapTempMaxC) return null;
  return c;
}

/// [hex] form of [strapTempFromEventInner].
double? strapTempFromEventHex(String hex) {
  if (hex.length < 42 || hex.length.isOdd) return null;
  final b = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < b.length; i++) {
    final v = int.tryParse(hex.substring(2 * i, 2 * i + 2), radix: 16);
    if (v == null) return null;
    b[i] = v;
  }
  return strapTempFromEventInner(b);
}

class NightStrapTemp {
  final double medianC;
  final int samples;

  /// Share of the kept samples within 1 °C of the night's own median —
  /// readiness's settledness gate reads it.
  final double settledFraction;
  const NightStrapTemp(this.medianC, this.samples, this.settledFraction);
}

/// The night's strap temperature from samples ([tsSec] ascending, [tempC]
/// parallel) over the sleep window, excluding the first hour of sleep and
/// every [chargingSpans] span ([start, end] epoch s) plus the hour after it.
NightStrapTemp? nightlyStrapTemp({
  required List<int> tsSec,
  required List<double> tempC,
  required int onsetSec,
  required int offsetSec,
  List<List<int>> chargingSpans = const [],
}) {
  if (tsSec.length != tempC.length || offsetSec <= onsetSec) return null;
  final kept = <double>[];
  for (var i = 0; i < tsSec.length; i++) {
    final t = tsSec[i];
    if (t < onsetSec + kStrapTempSettleSec || t > offsetSec) continue;
    var charging = false;
    for (final s in chargingSpans) {
      if (s.length < 2) continue;
      if (t >= s[0] && t <= s[1] + kStrapTempSettleSec) {
        charging = true;
        break;
      }
    }
    if (charging) continue;
    final c = tempC[i];
    if (c < kStrapTempMinC || c > kStrapTempMaxC) continue;
    kept.add(c);
  }
  if (kept.length < kStrapTempMinSamples) return null;
  final s = [...kept]..sort();
  final m = s.length.isOdd
      ? s[s.length ~/ 2]
      : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
  final settled = kept.where((c) => (c - m).abs() <= 1.0).length;
  return NightStrapTemp(m, kept.length, settled / kept.length);
}
