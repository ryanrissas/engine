// Profile — the on-device personal profile fed to the DerivationEngine.
//
// Sourced from AppState's local profile map (shared_preferences). Algorithms
// that NEED a field (HRmax via Tanaka, Keytel calories, TRIMP sex constant,
// fitness-age) read it from here; algorithms that don't simply ignore it.
//
// HONESTY: a missing field => the DEPENDENT metric must return null+confidence 0
// (never a fabricated default). The engine therefore passes nullable getters and
// only computes profile-gated metrics when the input is present.

import 'hr_max.dart' show manualMaxHrFromProfile, manualZoneBoundsFromProfile;

class Profile {
  final int? ageYears;
  final double? weightKg;
  final double? heightCm;
  final String? sex; // 'm' | 'f' (lowercase; matches the AppState profile map)
  final int? restingHrManual; // optional user-supplied RHR
  /// Optional user-supplied max heart rate (a field or lab test). Validated
  /// by `manualMaxHrFromProfile`; overrides the age estimate everywhere.
  final double? maxHrManual;
  // The zones screen's manual edges. Carried so the day derive (which only
  // sees [toMap]) bands on the same set the zones screen shows.
  final List<int>? hrZoneBounds;

  /// A VO2max TEST the user entered (mL/kg/min), its local date and how it
  /// was measured ('lab' | 'cooper'). Healthspan's fitness term reads it and
  /// nothing else: no VO2max is ever estimated from resting heart rate.
  final double? vo2maxTest;
  final String? vo2maxTestDate;
  final String? vo2maxTestMethod;

  const Profile({
    this.ageYears,
    this.weightKg,
    this.heightCm,
    this.sex,
    this.restingHrManual,
    this.maxHrManual,
    this.hrZoneBounds,
    this.vo2maxTest,
    this.vo2maxTestDate,
    this.vo2maxTestMethod,
  });

  static Profile fromMap(Map<String, dynamic>? m) {
    if (m == null) return const Profile();
    return Profile(
      ageYears: (m['age'] as num?)?.round(),
      weightKg: (m['weight_kg'] as num?)?.toDouble(),
      heightCm: (m['height_cm'] as num?)?.toDouble(),
      sex: (m['sex'] as String?)?.toLowerCase(),
      restingHrManual: (m['resting_hr'] as num?)?.round(),
      maxHrManual: manualMaxHrFromProfile(m),
      hrZoneBounds: manualZoneBoundsFromProfile(m),
      vo2maxTest: vo2maxTestFromProfile(m),
      vo2maxTestDate: vo2maxTestFromProfile(m) == null
          ? null
          : m['vo2max_test_date'] as String?,
      vo2maxTestMethod: vo2maxTestFromProfile(m) == null
          ? null
          : m['vo2max_test_method'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        if (ageYears != null) 'age': ageYears,
        if (weightKg != null) 'weight_kg': weightKg,
        if (heightCm != null) 'height_cm': heightCm,
        if (sex != null) 'sex': sex,
        if (restingHrManual != null) 'resting_hr': restingHrManual,
        if (maxHrManual != null) 'max_hr': maxHrManual,
        if (hrZoneBounds != null) 'hr_zone_bounds': hrZoneBounds,
        if (vo2maxTest != null) 'vo2max_test': vo2maxTest,
        if (vo2maxTestDate != null) 'vo2max_test_date': vo2maxTestDate,
        if (vo2maxTestMethod != null) 'vo2max_test_method': vo2maxTestMethod,
      };

  // NO `hrMaxTanaka` HERE. It was `208 − 0.7·age` inlined on the profile, which
  // made the HR ceiling a property of the ATHLETE alone — and the app then
  // carried four of them (this one, `220−age` twice, and `(220−age)+25`), so
  // one user's zone timeline and that same day's session zone bands were banded
  // off different ceilings with nothing on screen saying so.
  //
  // The one definition is `compute/hr_max.dart`'s `estimatedMaxHr(age, family)`
  // and it takes the STRAP as well: what a band can read at intensity is a
  // property of its sensor, so an uncalibrated or unstamped strap gets no
  // ceiling rather than gen4's. Callers resolve it at the layer that knows
  // which device measured the window and pass it down. (TS-03a)

  bool get isComplete =>
      ageYears != null && weightKg != null && heightCm != null && sex != null;

  /// The anchors Keytel (2005) needs to turn heart rate into kcal: age, body
  /// mass and sex. Height is not one of them, so it is deliberately absent
  /// here — gating calories on [isComplete] would refuse to score a profile
  /// that has everything the formula actually reads.
  ///
  /// The one definition of "can we cost this session in calories", shared by
  /// the live tick and the substrate re-score. They used to disagree: the
  /// re-score refused to guess while the live tick silently substituted a
  /// 30-year-old 70 kg male, so an unfinished profile produced a confident
  /// kcal number that was simply somebody else's.
  bool get hasCalorieAnchors =>
      ageYears != null && weightKg != null && sex != null;
}

/// Plausible bounds for an entered VO2max (mL/kg/min).
const double kVo2maxTestMin = 15;
const double kVo2maxTestMax = 95;

/// The user's entered VO2max test, validated, or null. Needs a date: an
/// undated number cannot be aged out.
double? vo2maxTestFromProfile(Map<String, dynamic> m) {
  final v = (m['vo2max_test'] as num?)?.toDouble();
  final d = m['vo2max_test_date'];
  if (v == null || d is! String || DateTime.tryParse(d) == null) return null;
  if (v < kVo2maxTestMin || v > kVo2maxTestMax) return null;
  return v;
}

/// Body mass index (kg/m²) off a weight and a height, or null without both.
double? bmiOf(num? weightKg, num? heightCm) =>
    weightKg == null || heightCm == null || heightCm <= 0
        ? null
        : weightKg / ((heightCm / 100) * (heightCm / 100));

/// Normalise every sex spelling the app can persist onto the three names the
/// analytics coefficient tables key on: 'male' | 'female' | 'nonbinary'.
///
/// Two writers disagree. Onboarding (`profile_setup_screen`) stores 'm'/'f';
/// the profile screen offers 'male'/'female'/'other'. Every scored path — day
/// calories, TRIMP, the live tick, a manually logged session — has to land on
/// the same coefficient block for the same stored value, or one field of one
/// profile scores as two different people. It happened: TRIMP tested `== 'f'`
/// while the calorie path accepted 'female' too, so a profile written by the
/// profile screen got female calories and male TRIMP.
///
/// 'other' and anything unrecognised map to `nonbinary`, which the analytics
/// tables define as the mean of the two published sex constants rather than a
/// guess at one of them.
String workoutSex(String? sex) {
  switch ((sex ?? '').toLowerCase()) {
    case 'm':
    case 'male':
      return 'male';
    case 'f':
    case 'female':
      return 'female';
    default:
      return 'nonbinary';
  }
}
