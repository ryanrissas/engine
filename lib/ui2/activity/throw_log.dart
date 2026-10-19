// The throw log for a Baseball session. The band cannot count throws (it has
// no high-rate gyro), so the player types them: what kind, how many, how hard.
// Stored as `strength_set` rows on `throw_<type>` keys (compute/throw_load.dart)
// so they ride the session's own row, cascade with it, and back up with it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../compute/throw_load.dart';
import '../../data/db.dart';
import '../grammar.dart';
import '../theme.dart';

/// Overridable for tests; production reads and writes the session's rows.
typedef ThrowRowsLoader = Future<List<Map<String, Object?>>> Function(
    String sessionId);
ThrowRowsLoader throwRowsLoader = LocalDb.strengthSets;

/// The throw entries among a session's rows, with their row `seq`.
List<({int seq, ThrowEntry e})> throwEntriesOf(
    List<Map<String, Object?>> rows) => [
      for (final r in rows)
        if (throwTypeOf((r['exercise_key'] as String?) ?? '') != null &&
            (r['reps'] as num?) != null &&
            (r['rpe'] as num?) != null)
          (
            seq: (r['seq'] as num?)?.toInt() ?? 0,
            e: ThrowEntry(
              throwTypeOf(r['exercise_key'] as String)!,
              (r['reps'] as num).toInt(),
              (r['rpe'] as num).toInt(),
            ),
          ),
    ];

/// Ask for one throw entry and save it. True when something was saved.
Future<bool> logThrows(BuildContext c, String sessionId) async {
  final e = await showModalBottomSheet<ThrowEntry>(
    context: c,
    isScrollControlled: true,
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (_) => const _ThrowSheet(),
  );
  if (e == null) return false;
  try {
    await LocalDb.addThrowEntries(sessionId, [
      {
        'exercise_key': throwKey(e.type),
        'set_index': 1,
        'reps': e.count,
        'load_kg': null,
        'rpe': e.intent,
        'rpe_source': 'user',
        'at_ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
    ]);
    return true;
  } catch (_) {
    return false;
  }
}

class _ThrowSheet extends StatefulWidget {
  const _ThrowSheet();
  @override
  State<_ThrowSheet> createState() => _ThrowSheetState();
}

class _ThrowSheetState extends State<_ThrowSheet> {
  String? type;
  int count = 0;
  int? intent; // nothing chosen until the player chooses

  bool get ready => type != null && count > 0 && intent != null;

  Widget _chip(P p, String label, bool on, VoidCallback tap, Color col) =>
      Pressable(
        semanticLabel: label,
        onTap: tap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
          decoration: BoxDecoration(
            color: on ? p.fill(col) : p.card2,
            borderRadius: R.rPill,
            border: Border.all(color: p.line),
          ),
          child: Text(label,
              style: F.body.copyWith(color: on ? p.inkOnFill : p.ink)),
        ),
      );

  Widget _step(P p, String label, int d) => Pressable(
        semanticLabel: label,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => count = (count + d).clamp(0, 400));
        },
        child: Container(
          width: 52,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
          child: Text(label, style: F.head.copyWith(color: p.ink)),
        ),
      );

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(S.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Log throws', style: F.head.copyWith(color: p.ink)),
            const SizedBox(height: S.x1),
            Text('The band can\'t count throws, so your arm load comes from '
                'what you log here.',
                style: F.cap.copyWith(color: p.ink2)),
            const SizedBox(height: S.x4),
            Text('KIND', style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Wrap(spacing: S.x2, runSpacing: S.x2, children: [
              for (final t in kThrowTypeWeight.keys)
                _chip(p, kThrowTypeLabel[t]!, type == t,
                    () => setState(() => type = t), C.red),
            ]),
            const SizedBox(height: S.x4),
            Text('THROWS', style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Row(children: [
              _step(p, '−5', -5),
              const SizedBox(width: S.x2),
              _step(p, '−1', -1),
              Expanded(
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: F.n34.copyWith(color: p.ink)),
              ),
              _step(p, '+1', 1),
              const SizedBox(width: S.x2),
              _step(p, '+5', 5),
            ]),
            const SizedBox(height: S.x4),
            Text('INTENT (6 easy – 10 max)',
                style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Wrap(spacing: S.x2, runSpacing: S.x2, children: [
              for (var v = 6; v <= 10; v++)
                _chip(p, '$v', intent == v, () => setState(() => intent = v),
                    C.orange),
            ]),
            const SizedBox(height: S.x5),
            Pressable(
              semanticLabel: 'Save throws',
              onTap: ready
                  ? () => Navigator.of(c).pop(ThrowEntry(type!, count, intent!))
                  : null,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ready ? p.fill(C.red) : p.card2,
                  borderRadius: R.rMd,
                ),
                child: Text('Save',
                    style: F.head.copyWith(
                        color: ready ? p.inkOnFill : p.ink3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The session's logged throws and a button to add more. Loads its rows
/// itself, best-effort: a read that fails shows the button alone.
class ThrowSection extends StatefulWidget {
  final String sessionId;
  const ThrowSection(this.sessionId, {super.key});
  @override
  State<ThrowSection> createState() => _ThrowSectionState();
}

class _ThrowSectionState extends State<ThrowSection> {
  List<({int seq, ThrowEntry e})> rows = const [];

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final r = throwEntriesOf(await throwRowsLoader(widget.sessionId));
      if (mounted) setState(() => rows = r);
    } catch (_) {/* nothing logged is a normal session */}
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final total = rows.fold(0, (a, r) => a + r.e.count);
    final load = sessionThrowLoad([for (final r in rows) r.e]);
    return Section(
      'Throws',
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (rows.isEmpty)
            Text('No throws logged for this session yet.',
                style: F.body.copyWith(color: p.ink2))
          else ...[
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: S.x1),
                child: Text(
                    '${kThrowTypeLabel[r.e.type]} · ${r.e.count} throws · '
                    'intent ${r.e.intent}',
                    style: F.body.copyWith(color: p.ink)),
              ),
            const SizedBox(height: S.x1),
            Text(
                '$total throws'
                '${load == null ? '' : ' · arm load ${load.toStringAsFixed(0)}'}',
                style: F.cap.copyWith(color: p.ink2)),
          ],
          const SizedBox(height: S.x3),
          Pressable(
            semanticLabel: 'Log throws',
            onTap: () async {
              if (await logThrows(c, widget.sessionId)) await _read();
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.plus, size: 16, color: p.on(C.red)),
              const SizedBox(width: S.x2),
              Text('Log throws',
                  style: F.body.copyWith(
                      color: p.on(C.red), fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}
