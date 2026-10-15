// The parts the Sleep / Recovery / Strain sub-tabs are built from, and the
// Overview's hero: one big score, the words under it, the day's numbers
// against your own month, and the last seven days. Data in, widgets out —
// nothing here reads the database (hub.dart does that).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../charts.dart';
import '../grammar.dart';
import '../theme.dart';

/// The score ring with its number inside: "RECOVERY / 90 %" the size the
/// screen is about. [value] null draws the track alone and [word] in place of
/// a number — a ring that is still learning says so rather than reading 0.
class ScoreHero extends StatelessWidget {
  final String label;
  final String? value;
  final String unit;
  final double? frac;
  final Color color;

  /// Shown inside the ring when there is no [value] ("Learning", "Not yet").
  final String word;

  /// A smaller line under the number, inside the ring ("3 of 7 nights").
  final String sub;

  const ScoreHero({
    super.key,
    required this.label,
    required this.color,
    this.value,
    this.unit = '',
    this.frac,
    this.word = 'Not yet',
    this.sub = '',
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final measured = value != null;
    return Center(
      child: SizedBox(
        width: 232,
        height: 232,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
            size: Size.infinite,
            painter: Ring(
              frac?.clamp(0, 1) ?? 0,
              p.on(color),
              p.track,
              stroke: 14,
              solid: measured,
              glow: p.dark && measured,
              t: animate(c, 1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(S.x8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label.toUpperCase(),
                  style: F.over.copyWith(
                      color: p.ink, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              const SizedBox(height: S.x1),
              if (measured)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(value!,
                            style: F.n48.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5)),
                        if (unit.isNotEmpty) ...[
                          const SizedBox(width: S.x1),
                          Text(unit,
                              style: F.n24.copyWith(
                                  color: p.ink, fontWeight: FontWeight.w700)),
                        ],
                      ]),
                )
              else
                Text(word,
                    textAlign: TextAlign.center,
                    style: F.head.copyWith(color: p.ink3)),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: S.x1),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(color: p.ink3)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The two lines under a score: what it means today, in plain words.
class ScoreWords extends StatelessWidget {
  final String headline;
  final String body;
  const ScoreWords({super.key, required this.headline, required this.body});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(headline, style: F.head.copyWith(color: p.ink)),
      const SizedBox(height: S.x1),
      Text(body, style: F.body.copyWith(color: p.ink2, height: 1.45)),
    ]);
  }
}

/// A quiet, full-width prompt bar: "Learn more about your recovery". Opens
/// the screen that explains the number.
class PromptBar extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  const PromptBar(this.text,
      {super.key, this.icon = LucideIcons.sparkles, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: text,
      child: Container(
        constraints: const BoxConstraints(minHeight: S.tap),
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: R.rPill,
          border: Border.all(color: p.line),
        ),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                shape: BoxShape.circle, border: Border.all(color: p.ink3)),
            child: Icon(icon, size: 12, color: p.ink2),
          ),
          const SizedBox(width: S.x3),
          Expanded(
              child: Text(text,
                  style: F.body.copyWith(color: p.ink3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

/// One line of a statistics list: name, today's value, and your own average
/// under it with an arrow for which way today sits. No average yet reads as
/// just the value — the arrow is never drawn against a number that is not
/// there.
class StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? baseline;

  /// Positive: today above the average; negative: below; null: no verdict.
  final int? direction;

  /// Whether up is good for this metric (HRV) or bad (resting HR); null keeps
  /// the arrow neutral.
  final bool? upIsGood;
  final VoidCallback? onTap;

  const StatRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.baseline,
    this.direction,
    this.upIsGood,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = direction ?? 0;
    final arrowColor = d == 0 || upIsGood == null
        ? p.ink3
        : ((d > 0) == upIsGood! ? p.on(C.green) : p.on(C.orange));
    return Pressable(
      onTap: onTap,
      semanticLabel:
          '$label $value${baseline == null ? '' : ', your average $baseline'}',
      child: Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        child: Row(children: [
          Icon(icon, size: 18, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
              child: Text(label.toUpperCase(),
                  style: F.over.copyWith(
                      color: p.ink, fontWeight: FontWeight.w700))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: F.n24.copyWith(
                          color: p.ink, fontWeight: FontWeight.w800)),
                  if (baseline != null) ...[
                    const SizedBox(width: S.x1),
                    Icon(
                        d > 0
                            ? LucideIcons.arrowUp
                            : d < 0
                                ? LucideIcons.arrowDown
                                : LucideIcons.minus,
                        size: 11,
                        color: arrowColor),
                  ],
                ]),
            if (baseline != null)
              Text(baseline!, style: F.cap.copyWith(color: p.ink3)),
          ]),
        ]),
      ),
    );
  }
}

/// The last seven days of one number: bars or a line, a weekday letter under
/// each, today's column marked. Missing days are gaps, never zeros.
class WeekChart extends StatelessWidget {
  final String title;
  final IconData icon;
  final String unit;

  /// Seven values, oldest first, null where the day has none.
  final List<double?> values;
  final List<String> dayLetters;
  final Color color;
  final bool bars;

  /// Per-bar colour from the value — a recovery bar in its band's colour.
  final Color Function(double)? colorOf;

  const WeekChart({
    super.key,
    required this.title,
    required this.icon,
    required this.values,
    required this.dayLetters,
    required this.color,
    this.unit = '',
    this.bars = true,
    this.colorOf,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final present = [for (final v in values) ?v];
    final axis = AxisSpec.of(present, ticks: 3, floor: bars ? 0 : null);
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: p.ink2),
          const SizedBox(width: S.x2),
          Text(title.toUpperCase(),
              style: F.over.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (unit.isNotEmpty)
            Text(unit, style: F.cap.copyWith(color: p.ink3)),
        ]),
        const SizedBox(height: S.x3),
        if (present.isEmpty || axis == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x4),
            child: Text('Nothing recorded in the last 7 days yet.',
                style: F.cap.copyWith(color: p.ink3)),
          )
        else ...[
          // The value over each column, as the reference prints it.
          Row(children: [
            for (final v in values)
              Expanded(
                child: Text(
                  v == null ? '' : _short(v),
                  textAlign: TextAlign.center,
                  style: F.cap.copyWith(
                      color: p.ink2, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ),
          ]),
          const SizedBox(height: S.x1),
          SizedBox(
            height: 110,
            child: CustomPaint(
              size: Size.infinite,
              painter: bars
                  ? Bars(values, p.on(color),
                      axis: axis,
                      highlight: values.length - 1,
                      colorOf: colorOf,
                      t: animate(c, 1))
                  : LineChart(values, p.on(color),
                      axis: axis, dots: true, fill: false),
            ),
          ),
          const SizedBox(height: S.x2),
          Row(children: [
            for (var i = 0; i < dayLetters.length; i++)
              Expanded(
                child: Text(dayLetters[i],
                    textAlign: TextAlign.center,
                    style: F.cap.copyWith(
                        color: i == dayLetters.length - 1 ? p.ink : p.ink3,
                        fontWeight: i == dayLetters.length - 1
                            ? FontWeight.w700
                            : FontWeight.w400)),
              ),
          ]),
        ],
      ]),
    );
  }

  static String _short(double v) => v >= 1000
      ? '${(v / 1000).toStringAsFixed(1)}k'
      : v == v.roundToDouble()
          ? v.round().toString()
          : v.toStringAsFixed(1);
}
