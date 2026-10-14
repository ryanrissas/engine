// The 10-minute auto-continue ceiling is a background budget. On screen, a
// productive backlog drain keeps going instead of pausing until the next
// scheduled backfill.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/sync/sync_policy.dart';

void main() {
  bool cont(double elapsed, int ceiling) =>
      BackfillContinuation.shouldAutoContinue(
        stillConnected: true,
        strapNewestTs: 1792000000,
        ourFrontierTs: 1791900000,
        rowsPersistedThisSession: 500,
        lastTrimAdvanced: true,
        consecutiveUnproductiveCount: 0,
        elapsedSeconds: elapsed,
        maxAutoContinueSeconds: ceiling,
      );

  test('background: a productive run still stops at ten minutes', () {
    expect(
        cont(601, BackfillContinuation.defaultMaxAutoContinueSeconds), isFalse);
  });

  test('foreground: the same run keeps draining', () {
    expect(BackfillContinuation.foregroundMaxAutoContinueSeconds,
        greaterThan(BackfillContinuation.defaultMaxAutoContinueSeconds));
    expect(cont(601, BackfillContinuation.foregroundMaxAutoContinueSeconds),
        isTrue);
  });

  test('foreground: an unproductive streak still ends it', () {
    expect(
      BackfillContinuation.shouldAutoContinue(
        stillConnected: true,
        strapNewestTs: 1792000000,
        ourFrontierTs: 1791900000,
        rowsPersistedThisSession: 0,
        lastTrimAdvanced: true,
        consecutiveUnproductiveCount:
            BackfillContinuation.defaultMaxAutoContinues,
        elapsedSeconds: 30,
        maxAutoContinueSeconds:
            BackfillContinuation.foregroundMaxAutoContinueSeconds,
      ),
      isFalse,
    );
  });
}
