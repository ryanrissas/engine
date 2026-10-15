// What a workout was. The band can tell that you trained, never what you
// did — a bullpen and a squat rack look the same from the wrist — so the app
// asks once, when a detected workout is confirmed, and a session saved
// without an answer can still be named later from its row.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../grammar.dart';
import '../theme.dart';
import 'catalogue.dart';
import 'picker.dart';

/// Offered first, large: what this athlete actually does.
const kPrimarySportNames = ['Weight training', 'Baseball'];

/// Offered next, as chips: the common ones.
const kCommonSportNames = [
  'Running',
  'Basketball',
  'Golf',
  'Walking',
  'Cycling',
  'HIIT',
];

/// The stored types that say nothing about the sport — a detected workout
/// confirmed before this question existed is saved as `other`.
bool isUnnamedWorkoutType(String? type) {
  final t = type?.trim().toLowerCase() ?? '';
  return t.isEmpty || t == 'other' || t == 'workout';
}

/// Ask what the workout was. Null when the sheet is dismissed — the caller
/// then does nothing, so a stray swipe never saves a guess.
Future<Activity?> askWorkoutSport(BuildContext c) {
  return showModalBottomSheet<Activity>(
    context: c,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (s) => const _SportSheet(),
  );
}

class _SportSheet extends StatelessWidget {
  const _SportSheet();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final primary = [
      for (final n in kPrimarySportNames) ?activityByName(n),
    ];
    final common = [
      for (final n in kCommonSportNames) ?activityByName(n),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(S.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What kind of workout was it?',
                style: F.head.copyWith(color: p.ink)),
            const SizedBox(height: S.x1),
            Text('The band knows you trained, not what you did.',
                style: F.cap.copyWith(color: p.ink2)),
            const SizedBox(height: S.x4),
            for (final a in primary) ...[
              _Big(a),
              const SizedBox(height: S.x2),
            ],
            const SizedBox(height: S.x2),
            Wrap(spacing: S.x2, runSpacing: S.x2, children: [
              for (final a in common) _Chip(a),
            ]),
            const SizedBox(height: S.x4),
            Pressable(
              semanticLabel: 'Something else',
              onTap: () async {
                Activity? picked;
                await Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => ActivityPicker(onPick: (pc, a) {
                    picked = a;
                    Navigator.of(pc).pop();
                  }),
                ));
                if (picked != null && c.mounted) {
                  Navigator.of(c).pop(picked);
                }
              },
              child: Row(children: [
                Icon(LucideIcons.ellipsis, size: 16, color: p.ink2),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text('Something else',
                      style: F.body.copyWith(
                          color: p.ink2, fontWeight: FontWeight.w600)),
                ),
                Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  final Activity a;
  const _Big(this.a);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final name = a.displayName(c);
    return Pressable(
      semanticLabel: name,
      onTap: () => Navigator.of(c).pop(a),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x4),
        decoration: BoxDecoration(
          color: p.wash(a.color),
          borderRadius: R.rMd,
          border: Border.all(color: p.line),
        ),
        child: Row(children: [
          Icon(a.icon, size: 22, color: p.on(a.color)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(name,
                style: F.head.copyWith(color: p.ink)),
          ),
          Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Activity a;
  const _Chip(this.a);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final name = a.displayName(c);
    return Pressable(
      semanticLabel: name,
      onTap: () => Navigator.of(c).pop(a),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
        decoration: BoxDecoration(
          color: p.card2,
          borderRadius: R.rPill,
          border: Border.all(color: p.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(a.icon, size: 14, color: p.on(a.color)),
          const SizedBox(width: S.x1),
          Text(name, style: F.body.copyWith(color: p.ink)),
        ]),
      ),
    );
  }
}
