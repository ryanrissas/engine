// The Sleep tab.
//
// Sleep used to be spread over the Home ring, a Health row that opened a
// generic chart, Wellness's "Recovery" sub-tab (need, debt, bedtime), Health's
// Body clock and the alarm in Settings. This tab is the Sleep screen itself,
// with those pieces under the night. The screens are the same ones; only
// where they live changed.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../state/clock_format.dart' show formatClockOf;
import '../profile/alarm.dart';
import '../ui2.dart';
import 'circadian_detail.dart';
import 'home_screen.dart' show envValue, repoOf;
import 'metric_detail.dart' show detailLinkRow;
import 'sleep_detail.dart';
import 'wellness_screen.dart';

class SleepTab extends StatelessWidget {
  const SleepTab({super.key});

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    return SleepDetail(
      embedded: true,
      footer: [
        const Section('Sleep consistency', _Consistency()),
        Section(
          l?.sleepTabPlanTitle ?? 'Your sleep plan',
          const WellnessScreen(sleepPlanOnly: true),
        ),
        Section(
          l?.sleepTabMoreTitle ?? 'Alarm and body clock',
          Column(children: [
            detailLinkRow(
                c,
                LucideIcons.alarmClock,
                l?.settingsAlarmRowTitle ?? 'Alarm',
                l?.settingsAlarmRowSub ??
                    'Buzzes on your wrist, on the band’s own clock',
                () => Navigator.of(c).push(MaterialPageRoute<void>(
                    builder: (_) => const AlarmScreen()))),
            const SizedBox(height: S.x3),
            detailLinkRow(
                c,
                LucideIcons.sunMoon,
                l?.healthBodyClockTitle ?? 'Body clock',
                l?.healthChronotypeJetlagRegularity ??
                    'Natural bedtime, weekend shift and schedule consistency',
                () => Navigator.of(c).push(MaterialPageRoute<void>(
                    builder: (_) => const CircadianDetail()))),
          ]),
        ),
      ],
    );
  }
}

/// When you went to bed and got up, each of the last seven nights, with the
/// schedule-consistency score over them when there is one. The times are the
/// nights as detected — a night with no sleep says so — and the score is the
/// regularity index the Body clock screen explains (it needs a few weeks).
class _Consistency extends StatefulWidget {
  const _Consistency();

  @override
  State<_Consistency> createState() => _ConsistencyState();
}

class _ConsistencyState extends State<_Consistency> with RevisionReload {
  List<Map<String, dynamic>> _nights = const [];
  num? _score;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  @override
  void reload() => _load();

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final nights = await repo.sleepWindows(days: 7);
      final reg = envValue((await repo.getInsights())['regularity']);
      if (!mounted) return;
      setState(() {
        _nights = nights;
        _score = reg?['sri'] as num?;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    String clock(Object? ts) => ts is num
        ? formatClockOf(DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000))
        : '';
    final rows = <Widget>[
      for (final n in _nights)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x1),
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Text(
                  DateFormat.E()
                      .format(DateTime.parse(n['date'].toString())),
                  style: F.cap.copyWith(color: p.ink3)),
            ),
            Expanded(
              child: n['onset_ts'] is num && n['wake_ts'] is num
                  ? Text('${clock(n['onset_ts'])}  →  ${clock(n['wake_ts'])}',
                      style: F.body.copyWith(color: p.ink))
                  : Text('No sleep recorded',
                      style: F.body.copyWith(color: p.ink3)),
            ),
          ]),
        ),
    ];
    return Pressable(
      onTap: () => Navigator.of(c).push(MaterialPageRoute<void>(
          builder: (_) => const CircadianDetail())),
      semanticLabel: 'Sleep consistency, last seven nights. Opens Body clock.',
      child: Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('BED → WAKE · LAST 7 NIGHTS',
                style: F.over.copyWith(color: p.ink3)),
            const Spacer(),
            if (_score != null)
              Text('${_score!.round()} / 100',
                  style: F.body.copyWith(
                      color: p.ink, fontWeight: FontWeight.w600)),
            const SizedBox(width: S.x1),
            Icon(LucideIcons.chevronRight, size: 15, color: p.ink3),
          ]),
          const SizedBox(height: S.x2),
          if (!_loaded)
            Text('Reading your nights…', style: F.cap.copyWith(color: p.ink3))
          else if (rows.isEmpty)
            Text('Nights you sleep in the band show up here.',
                style: F.cap.copyWith(color: p.ink3))
          else
            ...rows,
          if (_loaded && _score == null && rows.isNotEmpty) ...[
            const SizedBox(height: S.x2),
            Text('A consistency score appears after a few weeks of nights.',
                style: F.cap.copyWith(color: p.ink3)),
          ],
        ]),
      ),
    );
  }
}
