// HEALTHSPAN — Engine Age, its inputs one row each, and the VO2max test entry.
//
// Reads the cross-day rollup's `healthspan` envelope (compute/healthspan.dart)
// and draws only what it published. The warning that the cohorts are 40–70 is
// part of the number, so it sits under it every time, not behind a tap.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/healthspan.dart'
    show cooperVo2max, kHealthspanWarning;
import '../../compute/profile.dart' show kVo2maxTestMax, kVo2maxTestMin;
import '../../data/day_label.dart';
import '../../models/metric.dart' show whyFromNote;
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show go, repoOf;
import 'journal_compose.dart' show OsTextField;
import 'metric_detail.dart' show detailScaffold;

/// The `healthspan` envelope's value map, or null when absent.
Map<String, dynamic>? healthspanValueOf(Map<String, dynamic> insights) {
  final env = insights['healthspan'];
  final v = env is Map ? env['value'] : null;
  return v is Map ? v.cast<String, dynamic>() : null;
}

/// The envelope's own reason it is absent, in words, or null.
String? healthspanWhyAbsent(Map<String, dynamic> insights) {
  final env = insights['healthspan'];
  final note = env is Map ? env['note'] as String? : null;
  if (note == null) return null;
  if (note.startsWith('need_baseline:') || note.startsWith('need_inputs:')) {
    return 'Needs about three weeks of nights and worn days in the last month '
        'across at least four habits — resting heart rate, sleep, activity, '
        'strength, steps, regularity or a fitness test.';
  }
  return whyFromNote(note);
}

const Map<String, String> _labels = {
  'rhr': 'Resting heart rate',
  'vo2max': 'Fitness (VO2max test)',
  'mvpa': 'Moderate + vigorous activity',
  'steps': 'Steps',
  'strength': 'Strength training',
  'sleep': 'Sleep duration',
  'sri': 'Sleep regularity',
};

const Map<String, String> _missingCopy = {
  'vo2max': 'Enter a lab test or a 12-minute run to add your fitness.',
  'steps': 'Needs real step counts from a pedometer.',
  'strength': 'Counts once you save a strength session.',
  'mvpa': 'Needs worn days with heart rate.',
  'sri': 'Needs consecutive scored nights.',
  'rhr': 'Needs scored nights.',
  'sleep': 'Needs scored nights.',
};

String _signedYears(num y) {
  final s = y.abs() < 0.05 ? '0.0' : y.abs().toStringAsFixed(1);
  return y < -0.05 ? '−$s' : (y > 0.05 ? '+$s' : s);
}

String _fmtValue(Map<String, dynamic> i) {
  final v = (i['value'] as num?)?.toDouble();
  if (v == null) return '';
  final unit = i['unit'] as String? ?? '';
  final digits = (unit == 'h/night' || unit == 'MET-h/week') ? 1 : 0;
  return '${v.toStringAsFixed(digits)} $unit';
}

/// The Health-tab card: the age, or why there is none yet.
class HealthspanCard extends StatelessWidget {
  final Map<String, dynamic> insights;
  const HealthspanCard(this.insights, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final v = healthspanValueOf(insights);
    final age = (v?['engine_age'] as num?)?.toDouble();
    final impact = (v?['impact_years'] as num?)?.toDouble();
    return Surface(
      onTap: () => go(c, HealthspanScreen(insights: insights)),
      child: Row(children: [
        const Icon(LucideIcons.hourglass, color: C.green, size: 22),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Engine Age', style: F.head.copyWith(color: p.ink)),
            const SizedBox(height: S.x1),
            Text(
              v == null
                  ? (healthspanWhyAbsent(insights) ?? 'Not enough data yet.')
                  : age != null
                      ? '${age.toStringAsFixed(1)} years · '
                          '${_signedYears(impact ?? 0)} vs your age'
                      : '${_signedYears(impact ?? 0)} years vs your age',
              style: F.cap.copyWith(color: p.ink3, height: 1.4),
            ),
          ]),
        ),
        Icon(LucideIcons.chevronRight, color: p.ink3, size: 18),
      ]),
    );
  }
}

class HealthspanScreen extends StatefulWidget {
  final Map<String, dynamic> insights;
  const HealthspanScreen({super.key, this.insights = const {}});

  @override
  State<HealthspanScreen> createState() => _HealthspanScreenState();
}

class _HealthspanScreenState extends State<HealthspanScreen> {
  late Map<String, dynamic> _insights = widget.insights;

  Future<void> _reload() async {
    final repo = repoOf(context);
    if (repo == null) return;
    final cd = await repo.getInsights();
    if (mounted) setState(() => _insights = cd);
  }

  Future<void> _enterTest(BuildContext c) async {
    final app = c.read<AppState>();
    final ctrl = TextEditingController();
    var cooper = false;
    final saved = await showModalBottomSheet<bool>(
      context: c,
      isScrollControlled: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) => StatefulBuilder(
        builder: (s, set) => Padding(
          padding: EdgeInsets.only(
              left: S.x5,
              right: S.x5,
              top: S.x5,
              bottom: MediaQuery.of(s).viewInsets.bottom + S.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add a fitness test',
                  style: F.head.copyWith(color: P.of(s).ink)),
              const SizedBox(height: S.x2),
              Text(
                'A lab VO2max result, or the distance you covered in a '
                '12-minute run on a track (Cooper test). Engine never '
                'estimates VO2max from resting heart rate. A test counts for '
                'a year.',
                style: F.cap.copyWith(color: P.of(s).ink3, height: 1.4),
              ),
              const SizedBox(height: S.x4),
              Row(children: [
                Expanded(
                  child: BigButton('Lab result',
                      soft: cooper,
                      color: C.green,
                      onTap: () => set(() => cooper = false)),
                ),
                const SizedBox(width: S.x2),
                Expanded(
                  child: BigButton('12-min run',
                      soft: !cooper,
                      color: C.green,
                      onTap: () => set(() => cooper = true)),
                ),
              ]),
              const SizedBox(height: S.x4),
              OsTextField(
                controller: ctrl,
                label: cooper ? 'Distance in 12 minutes' : 'VO2max',
                hint: cooper ? 'metres' : 'mL/kg/min',
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: S.x4),
              BigButton('Save',
                  color: C.green, onTap: () => Navigator.of(s).pop(true)),
            ],
          ),
        ),
      ),
    );
    final typed = Typed.of(ctrl.text);
    ctrl.dispose();
    if (saved != true || !c.mounted) return;
    final raw = typed.value;
    final v = raw == null ? null : (cooper ? cooperVo2max(raw) : raw);
    if (typed.bad || v == null || v < kVo2maxTestMin || v > kVo2maxTestMax) {
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(
        content: Text(cooper
            ? 'That distance does not give a VO2max between '
                '${kVo2maxTestMin.round()} and ${kVo2maxTestMax.round()}. '
                'Nothing was saved.'
            : 'Enter a VO2max between ${kVo2maxTestMin.round()} and '
                '${kVo2maxTestMax.round()} mL/kg/min. Nothing was saved.'),
      ));
      return;
    }
    await app.updateProfile({
      'vo2max_test': double.parse(v.toStringAsFixed(1)),
      'vo2max_test_date': todayLabel(),
      'vo2max_test_method': cooper ? 'cooper' : 'lab',
    });
    if (!c.mounted) return;
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      content: Text('Saved VO2max ${v.toStringAsFixed(1)}. Engine Age '
          'updates after the next sync.'),
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final v = healthspanValueOf(_insights);
    final age = (v?['engine_age'] as num?)?.toDouble();
    final chrono = (v?['chronological_age'] as num?)?.toInt();
    final impact = (v?['impact_years'] as num?)?.toDouble() ?? 0;
    final impactNchs = (v?['impact_years_nchs'] as num?)?.toDouble();
    final se = (v?['se_years'] as num?)?.toDouble();
    final pace = (v?['pace'] as num?)?.toDouble();
    final windowDays = (v?['window_days'] as num?)?.toInt();
    final inputs = [
      for (final i in (v?['inputs'] as List? ?? const []))
        if (i is Map) i.cast<String, dynamic>(),
    ]..sort((a, b) => ((a['years'] as num).abs())
        .compareTo((b['years'] as num).abs()) * -1);
    final missing = (v?['missing'] as Map?)?.cast<String, dynamic>() ?? {};

    return detailScaffold(c, 'Engine Age', [
      if (v == null)
        StatusCard(
          'No Engine Age yet',
          healthspanWhyAbsent(_insights) ?? 'Not enough data yet.',
          icon: LucideIcons.hourglass,
        )
      else ...[
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              age != null
                  ? age.toStringAsFixed(1)
                  : '${_signedYears(impact)} y',
              style: F.n34.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x1),
            Text(
              [
                if (chrono != null) 'You are $chrono',
                '${_signedYears(impact)} years from your habits',
                if (se != null) '±${se.toStringAsFixed(1)}',
              ].join(' · '),
              style: F.cap.copyWith(color: p.ink2),
            ),
            if (impactNchs != null) ...[
              const SizedBox(height: S.x1),
              Text(
                'On the US life table the same habits read '
                '${_signedYears(impactNchs)} years.',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
            if (pace != null) ...[
              const SizedBox(height: S.x3),
              Text('Pace of aging ${pace.toStringAsFixed(1)}×',
                  style: F.head.copyWith(color: p.ink)),
              Text(
                'Your last 30 days against the whole window. 1.0× is one '
                'year per year; lower is better.',
                style: F.cap.copyWith(color: p.ink3, height: 1.4),
              ),
            ],
            const SizedBox(height: S.x3),
            Text(kHealthspanWarning,
                style: F.cap.copyWith(color: p.ink3, height: 1.4)),
            if (windowDays != null) ...[
              const SizedBox(height: S.x2),
              Text('From your last $windowDays days.',
                  style: F.cap.copyWith(color: p.ink3)),
            ],
          ]),
        ),
        Section(
          'What moves it',
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(children: [
              for (var k = 0; k < inputs.length; k++) ...[
                if (k > 0) Divider(color: p.line, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _labels[inputs[k]['key']] ??
                                    '${inputs[k]['key']}',
                                style: F.body.copyWith(color: p.ink)),
                            Text(
                                '${_fmtValue(inputs[k])} · ideal '
                                '${inputs[k]['referent']} · '
                                '${inputs[k]['source']}',
                                style: F.cap.copyWith(color: p.ink3)),
                          ]),
                    ),
                    Text('${_signedYears(inputs[k]['years'] as num)} y',
                        style: F.head.copyWith(
                            color: (inputs[k]['years'] as num) <= 0
                                ? C.green
                                : C.red)),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        if (missing.isNotEmpty)
          Section(
            'Not counted yet',
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final k in missing.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.x2),
                      child: Text(
                        '${_labels[k] ?? k} — '
                        '${_missingCopy[k] ?? 'Not enough data yet.'}',
                        style: F.cap.copyWith(color: p.ink2, height: 1.4),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: S.x4),
      BigButton('Add a fitness test',
          icon: LucideIcons.plus,
          color: C.green,
          onTap: () => _enterTest(c)),
    ]);
  }
}
