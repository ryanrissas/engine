/// Nights of measured overnight HRV before a recovery grade is shown or
/// announced.
///
/// HRV and resting heart rate only mean something against the wearer's own
/// normal, and a normal built from a few nights is mostly noise. A week
/// matches how athlete HRV is read in the literature (a 7-day rolling
/// lnRMSSD). The score keeps refining past it: the readiness calibration only
/// re-centres on the wearer's own spread once 14 nights exist.
const int kRecoveryCalibrationNights = 7;

/// True while the first-week calibration should hold the recovery grade back.
/// [hrvNights] null means unknown, which never holds anything back.
bool recoveryCalibrating(int? hrvNights) =>
    hrvNights != null && hrvNights < kRecoveryCalibrationNights;
