import 'provisional_recovery.dart' show kProvisionalRecoveryNights;

/// Nights of measured overnight HRV before a recovery grade is shown or
/// announced: the night that has [kProvisionalRecoveryNights] nights of
/// baseline behind it.
///
/// WHOOP shows a first, calibrating recovery after about four nights. From
/// here to night 15 the score is PROVISIONAL (provisional_recovery.dart): the
/// composite against the short baseline, shrunk toward the middle by
/// nights/14, and labelled "early read". The readiness calibration still only
/// re-centres on the wearer's own spread once 14 nights exist.
const int kRecoveryCalibrationNights = kProvisionalRecoveryNights + 1;

/// The night the ordinary 14-night composite takes over from the early read.
const int kRecoveryFullBaselineNight = 15;

/// True while a shown recovery is still an early read.
bool recoveryEarlyRead(int? hrvNights) =>
    hrvNights != null &&
    hrvNights >= kRecoveryCalibrationNights &&
    hrvNights < kRecoveryFullBaselineNight;

/// True while the first-week calibration should hold the recovery grade back.
/// [hrvNights] null means unknown, which never holds anything back.
bool recoveryCalibrating(int? hrvNights) =>
    hrvNights != null && hrvNights < kRecoveryCalibrationNights;
