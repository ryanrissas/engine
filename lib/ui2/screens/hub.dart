// The Sleep / Recovery / Strain sub-tabs of Home: the score as a ring, what
// it means today, the day's numbers against your own month, and the last
// seven days. Reads the same stores every other screen does; the parts it
// draws are in hub_parts.dart.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../compute/recovery_calibration.dart';
import '../../data/day_label.dart' show dayLabelOf, todayLabel;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart';
import '../activity/day_strain.dart' show DayStrainDetail;
import '../ui2.dart';
import 'home_screen.dart';
import 'hub_parts.dart';
import 'metric_detail.dart';
import 'readiness_detail.dart';
import 'sleep_detail.dart';

enum HubKind { sleep, recovery, strain }

/// Everything one sub-tab draws, loaded in one go.
class HubTabData {
  final HomeData today;
  /// One trend series per metric: the last 30 days by date label, oldest
  /// first.
  final Map<String, Map<String, double>> series;
  const HubTabData({required this.today, this.series = const {}});

  static const _metrics = {
    HubKind.sleep: ['sleep', 'efficiency', 'deep', 'rem'],
    HubKind.recovery: ['recovery', 'hrv', 'resting_hr', 'resp_rate'],
    HubKind.strain: ['strain', 'waking_hr', 'calories', 'steps'],
  };

  static Future<HubTabData> load(
      LocalRepository repo, HubKind kind, AppLocalizations? l) async {
    final today = await HomeData.load(repo, l);
    final series = <String, Map<String, double>>{};
    for (final m in _metrics[kind]!) {
      try {
        final pts = (await repo.getChart(m))['points'];
        final s = <String, double>{};
        for (final e in (pts is List ? pts : const [])) {
          if (e is! Map) continue;
          final t = e['t'], v = e['v'];
          if (t is! num || v is! num) continue;
          s[dayLabelOf(DateTime.fromMillisecondsSinceEpoch(t.toInt() * 1000))] =
              v.toDouble();
        }
        series[m] = s;
      } catch (_) {
        // A series that fails to read is a chart that says so, not a crash.
      }
    }
    return HubTabData(today: today, series: series);
  }

  /// Mean of the 30 days BEFORE today, or null under 3 of them: a baseline
  /// from one or two days is a coincidence, not your usual.
  double? avg30(String metric) {
    final s = series[metric];
    if (s == null) return null;
    final today = todayLabel();
    final vs = [for (final e in s.entries) if (e.key != today) e.value];
    if (vs.length < 3) return null;
    final last = vs.length > 30 ? vs.sublist(vs.length - 30) : vs;
    return last.reduce((a, b) => a + b) / last.length;
  }

  /// The last seven calendar days ending today, null where a day has none.
  List<double?> week(String metric) {
    final s = series[metric] ?? const {};
    final now = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        s[dayLabelOf(DateTime(now.year, now.month, now.day - i))],
    ];
  }

  static List<String> get weekLetters {
    final now = DateTime.now();
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return [
      for (var i = 6; i >= 0; i--)
        letters[DateTime(now.year, now.month, now.day - i).weekday - 1],
    ];
  }
}

/// A Home sub-tab. [inline] renders a Column for a host that already scrolls
/// (the Sleep night and the Strain workouts put this above their own lists);
/// otherwise it is its own scrolling page.
class HubScoreTab extends StatefulWidget {
  final HubKind kind;
  final bool inline;
  final HubTabData? data;
  const HubScoreTab(this.kind, {super.key, this.inline = false, this.data});

  @override
  State<HubScoreTab> createState() => _HubScoreTabState();
}

class _HubScoreTabState extends State<HubScoreTab> with RevisionReload {
  HubTabData? _d;

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    if (_d == null) WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  @override
  bool get revisionReloads => widget.data == null;

  @override
  void reload() => _load();

  Future<void> _load() async {
    if (!mounted) return;
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final d = await HubTabData.load(repo, widget.kind, AppLocalizations.of(context));
      if (mounted) setState(() => _d = d);
    } catch (_) {
      // Leave what is on screen; the next revision tries again.
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = _d;
    final children = d == null
        ? const <Widget>[
            Padding(
              padding: EdgeInsets.only(top: S.x8),
              child: Center(child: CircularProgressIndicator()),
            ),
          ]
        : switch (widget.kind) {
            HubKind.sleep => _sleep(c, d),
            HubKind.recovery => _recovery(c, d),
            HubKind.strain => _strain(c, d),
          };
    if (widget.inline) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x16),
      children: children,
    );
  }

  // ── shared pieces ──

  static String _fmt(double v, int dp) =>
      dp == 0 ? v.round().toString() : v.toStringAsFixed(dp);

  List<Widget> _stats(BuildContext c, HubTabData d, String caption,
          List<(IconData, String, Metric, String, int, bool?, String)> rows) =>
      [
        Row(children: [
          Text('${_kindWord.toUpperCase()} STATISTICS',
              style: F.over.copyWith(color: P.of(c).ink3)),
          const Spacer(),
          Text(caption, style: F.over.copyWith(color: P.of(c).ink3)),
        ]),
        const SizedBox(height: S.x3),
        for (final (icon, label, m, metric, dp, upIsGood, unit) in rows) ...[
          Builder(builder: (c) {
            final v = m.value?.toDouble();
            final base = d.avg30(metric);
            return StatRow(
              icon: icon,
              label: label,
              value: v == null ? 'Not yet' : '${_fmt(v, dp)}$unit',
              baseline: base == null ? null : '${_fmt(base, dp)}$unit',
              direction: v == null || base == null
                  ? null
                  : (v - base).abs() < 0.05 * base.abs()
                      ? 0
                      : (v > base ? 1 : -1),
              upIsGood: upIsGood,
              onTap: () => go(c, MetricDetail(metric)),
            );
          }),
          const SizedBox(height: S.x2),
        ],
      ];

  String get _kindWord => switch (widget.kind) {
        HubKind.sleep => 'Sleep',
        HubKind.recovery => 'Recovery',
        HubKind.strain => 'Strain',
      };

  Widget _charts(List<Widget> charts) => Column(children: [
        for (final w in charts) ...[w, const SizedBox(height: S.x3)],
      ]);

  // ── sleep ──

  List<Widget> _sleep(BuildContext c, HubTabData d) {
    final t = d.today;
    final slept = t.sleepMin.value?.toDouble();
    final need = t.sleepNeedMin.value?.toDouble();
    final perf = slept != null && need != null && need > 0
        ? (slept / need * 100).clamp(0, 999).round()
        : null;
    final p = P.of(c);
    final letters = HubTabData.weekLetters;
    final (head, body) = perf == null
        ? slept == null
            ? ('No night scored yet',
                'Wear the band tonight; the night is scored once you are up '
                    'and the band has synced.')
            : ('${hm(slept)} asleep',
                'Your sleep need appears once Engine has a week of your '
                    'nights to learn it from; performance is scored against '
                    'that.')
        : perf >= 95
            ? ('You met your sleep need',
                'A night like this is where recovery is built. Keeping a '
                    'steady bedtime makes it the normal one.')
            : perf >= 80
                ? ('Close to your need',
                    'You got most of the sleep your body asked for. An earlier '
                        'night, or a nap, would clear the rest.')
                : ('Short of your need',
                    'Tonight matters more than usual: aim for your '
                        'recommended bedtime and give the night its full length.');
    return [
      const SizedBox(height: S.x2),
      ScoreHero(
        label: 'Sleep performance',
        color: C.blueSoft,
        value: perf?.toString(),
        unit: perf == null ? '' : '%',
        frac: perf == null ? null : perf / 100,
        word: slept == null ? 'No night yet' : 'Learning your need',
        sub: slept != null && perf == null
            ? '${hm(slept)} asleep'
            : '',
      ),
      const SizedBox(height: S.x4),
      Row(children: [
        Expanded(
            child: _pill(c, slept == null ? '—' : hm(slept), 'Hours of sleep',
                C.blueSoft)),
        const SizedBox(width: S.x3),
        Expanded(
            child: _pill(c, need == null ? 'Learning' : hm(need), 'Sleep needed',
                C.green)),
      ]),
      const SizedBox(height: S.x5),
      ScoreWords(headline: head, body: body),
      const SizedBox(height: S.x3),
      PromptBar('Learn more about your sleep',
          onTap: () => go(c, SleepDetail())),
      const SizedBox(height: S.x5),
      ..._stats(c, d, 'VS. PREVIOUS 30 DAYS', [
        (LucideIcons.moon, 'Time asleep', t.sleepMin, 'sleep', 0, true, ' min'),
        (
          LucideIcons.gauge,
          'Sleep efficiency',
          Metric(value: d.series['efficiency']?[todayLabel()] ??
              d.series['efficiency']?[_latestKey(d, 'efficiency')]),
          'efficiency',
          0,
          true,
          '%'
        ),
        (
          LucideIcons.battery,
          'Restorative sleep',
          Metric(value: _restorative(d, todayLabel()) ?? _restorative(d, _latestKey(d, 'deep'))),
          'deep',
          0,
          true,
          '%'
        ),
      ]),
      const SizedBox(height: S.x3),
      Row(children: [
        Text('SLEEP STATISTICS', style: F.over.copyWith(color: p.ink3)),
        const Spacer(),
        Text('VS. LAST 7 DAYS', style: F.over.copyWith(color: p.ink3)),
      ]),
      const SizedBox(height: S.x3),
      _charts([
        WeekChart(
            title: 'Hours of sleep',
            icon: LucideIcons.moon,
            unit: 'hours',
            values: [for (final v in d.week('sleep')) v == null ? null : v / 60],
            dayLetters: letters,
            color: C.blueSoft),
        WeekChart(
            title: 'Restorative sleep',
            icon: LucideIcons.battery,
            unit: 'deep + REM, min',
            values: [
              for (var i = 0; i < 7; i++)
                _sum(d.week('deep')[i], d.week('rem')[i])
            ],
            dayLetters: letters,
            color: C.purple),
        WeekChart(
            title: 'Sleep efficiency',
            icon: LucideIcons.gauge,
            unit: '%',
            values: d.week('efficiency'),
            dayLetters: letters,
            color: C.blue,
            bars: false),
      ]),
    ];
  }

  static double? _sum(double? a, double? b) =>
      a == null && b == null ? null : (a ?? 0) + (b ?? 0);

  static String? _latestKey(HubTabData d, String metric) {
    final s = d.series[metric];
    if (s == null || s.isEmpty) return null;
    final keys = s.keys.toList()..sort();
    return keys.last;
  }

  static double? _restorative(HubTabData d, String? day) {
    if (day == null) return null;
    final deep = d.series['deep']?[day], rem = d.series['rem']?[day];
    final tst = d.series['sleep']?[day];
    if (tst == null || tst <= 0 || (deep == null && rem == null)) return null;
    return ((deep ?? 0) + (rem ?? 0)) / tst * 100;
  }

  Widget _pill(BuildContext c, String value, String label, Color color) {
    final p = P.of(c);
    return Column(children: [
      Text(value,
          style: F.n34.copyWith(color: p.on(color), fontWeight: FontWeight.w800)),
      const SizedBox(height: S.x1),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
        decoration: BoxDecoration(
            borderRadius: R.rPill, border: Border.all(color: p.on(color))),
        child: Text(label.toUpperCase(),
            style: F.over.copyWith(color: p.on(color))),
      ),
    ]);
  }

  // ── recovery ──

  List<Widget> _recovery(BuildContext c, HubTabData d) {
    final t = d.today;
    final v = t.readiness.value?.toDouble();
    final nights = t.hrvNights;
    final calibrating = nights != null && recoveryCalibrating(nights);
    final band = readinessBand(v, AppLocalizations.of(c));
    final letters = HubTabData.weekLetters;
    final hrv = t.hrv.value?.toDouble();
    final hrvBase = d.avg30('hrv');
    final rhr = t.rhr.value?.toDouble();
    final rhrBase = d.avg30('resting_hr');
    // The headline names the driver that moved most against your own month.
    String head, body;
    if (calibrating) {
      head = 'Learning your usual';
      body = 'Recovery is scored against your own nights, and a week of them '
          'is the least that means anything. $nights of '
          '$kRecoveryCalibrationNights so far.';
    } else if (v == null) {
      head = t.recoveryState == 'night_in_progress' ? 'Sleeping…' : 'Not scored';
      body = t.recoveryState == 'night_in_progress'
          ? 'Recovery is scored after you wake and the band has synced.'
          : 'No night with enough heart-rate data was recorded, so there is '
              'nothing to score today against.';
    } else {
      final hrvPct = hrv != null && hrvBase != null && hrvBase > 0
          ? ((hrv - hrvBase) / hrvBase * 100).round()
          : null;
      final rhrPct = rhr != null && rhrBase != null && rhrBase > 0
          ? ((rhr - rhrBase) / rhrBase * 100).round()
          : null;
      if (hrvPct != null && hrvPct.abs() >= 5) {
        head = hrvPct > 0 ? 'HRV above your usual' : 'HRV below your usual';
        body = 'Your HRV is ${hrvPct.abs()}% ${hrvPct > 0 ? 'higher' : 'lower'} '
            'than your 30-day average. ${band.tier >= 2 ? 'Your body is ready for a hard day.' : band.tier == 1 ? 'A lighter day will serve you better than a hard one.' : 'Rest is the training today.'}';
      } else if (rhrPct != null && rhrPct.abs() >= 5) {
        head = rhrPct > 0
            ? 'Resting heart rate above your usual'
            : 'Resting heart rate below your usual';
        body = 'Your resting heart rate is ${rhrPct.abs()}% '
            '${rhrPct > 0 ? 'higher' : 'lower'} than your 30-day average. '
            '${band.tier >= 2 ? 'Good sign — take on the day.' : 'Go easier than planned and watch tomorrow.'}';
      } else {
        head = band.label;
        body = band.tier >= 2
            ? 'Your overnight numbers sit at your usual. Train as planned.'
            : band.tier == 1
                ? 'Your overnight numbers are a little off your usual. Keep '
                    'the effort moderate.'
                : 'Your overnight numbers are well off your usual. Take the '
                    'day easy.';
      }
    }
    return [
      const SizedBox(height: S.x2),
      ScoreHero(
        label: 'Recovery',
        color: v == null ? C.green : band.color,
        value: v?.round().toString(),
        unit: v == null ? '' : '%',
        frac: v == null
            ? (calibrating ? nights / kRecoveryCalibrationNights : null)
            : v / 100,
        word: calibrating ? 'Learning' : head,
        sub: calibrating ? '$nights of $kRecoveryCalibrationNights nights' : '',
      ),
      const SizedBox(height: S.x5),
      ScoreWords(headline: head, body: body),
      const SizedBox(height: S.x3),
      PromptBar('Learn more about your recovery',
          onTap: () => go(c, const ReadinessDetail())),
      const SizedBox(height: S.x5),
      ..._stats(c, d, 'VS. PREVIOUS 30 DAYS', [
        (LucideIcons.activity, 'HRV', t.hrv, 'hrv', 0, true, ''),
        (LucideIcons.heart, 'RHR', t.rhr, 'resting_hr', 0, false, ''),
        (LucideIcons.wind, 'Respiratory rate', t.resp, 'resp_rate', 1, null, ''),
      ]),
      const SizedBox(height: S.x3),
      Row(children: [
        Text('RECOVERY STATISTICS', style: F.over.copyWith(color: P.of(c).ink3)),
        const Spacer(),
        Text('VS. LAST 7 DAYS', style: F.over.copyWith(color: P.of(c).ink3)),
      ]),
      const SizedBox(height: S.x3),
      _charts([
        WeekChart(
            title: 'Recovery',
            icon: LucideIcons.batteryCharging,
            unit: '%',
            values: d.week('recovery'),
            dayLetters: letters,
            color: C.green,
            colorOf: (x) => P.of(c).on(readinessBand(x).color)),
        WeekChart(
            title: 'Heart rate variability',
            icon: LucideIcons.activity,
            unit: 'ms',
            values: d.week('hrv'),
            dayLetters: letters,
            color: C.blue,
            bars: false),
        WeekChart(
            title: 'Resting heart rate',
            icon: LucideIcons.heart,
            unit: 'bpm',
            values: d.week('resting_hr'),
            dayLetters: letters,
            color: C.blue,
            bars: false),
        WeekChart(
            title: 'Respiratory rate',
            icon: LucideIcons.wind,
            unit: 'br/min',
            values: d.week('resp_rate'),
            dayLetters: letters,
            color: C.blue,
            bars: false),
      ]),
    ];
  }

  // ── strain ──

  List<Widget> _strain(BuildContext c, HubTabData d) {
    final t = d.today;
    final v = t.strain.value?.toDouble();
    final tg = t.strainTarget;
    final lo = (tg?['low'] as num?)?.toDouble();
    final hi = (tg?['high'] as num?)?.toDouble();
    final target = lo != null && hi != null && hi > lo ? (lo: lo, hi: hi) : null;
    final letters = HubTabData.weekLetters;
    final note = t.strain.note;
    final counts = baselineCountsFromNote(note);
    final (head, body) = v == null
        ? counts != null
            ? ('Learning your quiet level',
                'Strain is priced against your own quiet, awake heart rate, '
                    'and that takes ${counts.need} days to learn. '
                    '${counts.have} of ${counts.need} so far.')
            : ('Not scored yet',
                'Strain needs a resting heart rate from your own night. '
                    'Once a night is scored, the day is priced against it.')
        : target == null
            ? ('${strainWord(v)} so far',
                'Your target range appears once a morning recovery is scored; '
                    'until then this is simply what the day has cost.')
            : v < target.lo
                ? ('Room to push today',
                    'Your optimal range is ${target.lo.toStringAsFixed(1)}–'
                        '${target.hi.toStringAsFixed(1)}. You are '
                        '${(target.lo - v).toStringAsFixed(1)} short of it.')
                : v <= target.hi
                    ? ('In your optimal range',
                        'Today sits inside your '
                            '${target.lo.toStringAsFixed(1)}–${target.hi.toStringAsFixed(1)} target. '
                            'More now adds fatigue faster than fitness.')
                    : ('Above your range',
                        'Today passed your ${target.lo.toStringAsFixed(1)}–'
                            '${target.hi.toStringAsFixed(1)} target. Recovery '
                            'tonight is the priority.');
    return [
      const SizedBox(height: S.x2),
      ScoreHero(
        label: 'Strain',
        color: C.blue,
        value: v?.toStringAsFixed(1),
        frac: v == null ? null : v / 21,
        word: counts != null ? 'Learning' : 'Not yet',
        sub: counts != null ? '${counts.have} of ${counts.need} days' : '',
      ),
      const SizedBox(height: S.x5),
      ScoreWords(headline: head, body: body),
      const SizedBox(height: S.x3),
      PromptBar('Learn more about your strain',
          onTap: () => go(c, const DayStrainDetail())),
      const SizedBox(height: S.x5),
      ..._stats(c, d, 'VS. PREVIOUS 30 DAYS', [
        (LucideIcons.footprints, 'Steps', t.steps, 'steps', 0, null, ''),
        (
          LucideIcons.heart,
          'Average HR',
          Metric(value: d.series['waking_hr']?[todayLabel()]),
          'waking_hr',
          0,
          null,
          ''
        ),
        (
          LucideIcons.flame,
          'Calories',
          t.caloriesTotal.value != null ? t.caloriesTotal : t.calories,
          'calories',
          0,
          null,
          ''
        ),
      ]),
      const SizedBox(height: S.x3),
      Row(children: [
        Text('STRAIN STATISTICS', style: F.over.copyWith(color: P.of(c).ink3)),
        const Spacer(),
        Text('VS. LAST 7 DAYS', style: F.over.copyWith(color: P.of(c).ink3)),
      ]),
      const SizedBox(height: S.x3),
      _charts([
        WeekChart(
            title: 'Strain',
            icon: LucideIcons.zap,
            unit: 'of 21',
            values: d.week('strain'),
            dayLetters: letters,
            color: C.blue),
        WeekChart(
            title: 'Average HR',
            icon: LucideIcons.heart,
            unit: 'bpm, awake',
            values: d.week('waking_hr'),
            dayLetters: letters,
            color: C.blue,
            bars: false),
        WeekChart(
            title: 'Calories',
            icon: LucideIcons.flame,
            unit: 'kcal',
            values: d.week('calories'),
            dayLetters: letters,
            color: C.blue),
      ]),
    ];
  }
}
