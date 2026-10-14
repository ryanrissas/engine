// A chunk stamped below the plausible-epoch floor must not wedge the band's
// queue once the strap clock is known to be right.
//
// Seen on a WHOOP 4.0 whose RTC reset to 2023-09-01 after its battery ran
// flat: the pre-SET_CLOCK stretch was refused by the RecordGate (correctly,
// it can never be admitted), the trim was then refused too, and the band
// re-delivered the same 30 records forever. A day of correctly stamped
// workout and sleep sat behind them on the band; the app showed nothing but
// live heart rate.
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_state.dart';

void main() {
  group('TrimAckPolicy.blockingDrops', () {
    test('below-floor drops stop blocking once the strap clock is sane', () {
      final blocking = TrimAckPolicy.blockingDrops(
        dropped: 29,
        droppedBelowFloor: 29,
        strapClockSane: true,
      );
      expect(blocking, 0);
      // ...so the drop-only burst may be trimmed (its bytes ride the same
      // commit into raw_archive).
      expect(
        TrimAckPolicy.evaluate(
          sessionCurrent: true,
          burstDiscarded: false,
          commitDurable: true,
          hadDurableRows: false,
          droppedThisBurst: blocking,
        ),
        TrimAckVerdict.send,
      );
    });

    test('with the strap clock unknown or unset, every drop still blocks', () {
      final blocking = TrimAckPolicy.blockingDrops(
        dropped: 29,
        droppedBelowFloor: 29,
        strapClockSane: false,
      );
      expect(blocking, 29);
      expect(
        TrimAckPolicy.evaluate(
          sessionCurrent: true,
          burstDiscarded: false,
          commitDurable: true,
          hadDurableRows: false,
          droppedThisBurst: blocking,
        ),
        TrimAckVerdict.blockedNoDurableProgress,
      );
    });

    test('in-range drops (a wandering clock) still block', () {
      // 5 below the floor, 3 distrusted for another reason (future, or
      // outside the strap's own range): those 3 may yet be admitted.
      final blocking = TrimAckPolicy.blockingDrops(
        dropped: 8,
        droppedBelowFloor: 5,
        strapClockSane: true,
      );
      expect(blocking, 3);
      expect(
        TrimAckPolicy.evaluate(
          sessionCurrent: true,
          burstDiscarded: false,
          commitDurable: true,
          hadDurableRows: false,
          droppedThisBurst: blocking,
        ),
        TrimAckVerdict.blockedNoDurableProgress,
      );
    });

    test('never negative', () {
      expect(
        TrimAckPolicy.blockingDrops(
            dropped: 0, droppedBelowFloor: 4, strapClockSane: true),
        0,
      );
    });
  });
}
