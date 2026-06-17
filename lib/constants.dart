/// Base URL for the Notes INSA Cloudflare Worker.
/// No trailing slash — service methods append /submit and /averages.
const kWorkerBaseUrl = 'https://notesinsa.theo-phan-quoc-huy.workers.dev';

/// Identifies a fetched dataset by department + semester + academic year.
/// Shared by the coefficients and averages provider families and cache keys.
typedef SemesterParams = ({
  String department,
  int semester,
  String academicYear,
});

/// Builds a per-(department, semester, academicYear) storage key from a prefix.
/// Used for cached coefficients/averages and the last-submitted grades hash.
String semesterCacheKey(
  String prefix,
  String department,
  int semester,
  String academicYear,
) => '$prefix${department}_${semester}_$academicYear';

/// Placeholder department used when the real code can't be resolved from the
/// grades payload. Treated as "no department" by [isRealDepartment].
const kUnknownDepartment = 'Etudiant';

/// True when [department] is a resolved code we can fetch shared data for —
/// i.e. non-empty and not the [kUnknownDepartment] placeholder.
bool isRealDepartment(String department) =>
    department.isNotEmpty && department != kUnknownDepartment;

/// Secret shared with the Cloudflare Worker to authenticate submissions.
/// Pass this at build time using: --dart-define=APP_SECRET=your_secret_here
const kAppSecret = String.fromEnvironment('APP_SECRET');

/// Storage keys for FlutterSecureStorage.
const kStorageUser = 'username';
const kStoragePass = 'password';
// Optional — stored only when the user explicitly opts in.
const kStorageOtpSecret = 'otp_secret';
// CAS session token — exported after successful auth to allow silent session restore.
const kStorageCasSession = 'cas_session';
// Cached grades JSON — shared between GradesService and the background task.
const kStorageGradesJson = 'stored_grades_json';
// Epoch-ms timestamp of the last grades write, in each store. Used to reconcile
// the foreground and background-worker snapshots on resume (newer wins).
const kStorageGradesUpdatedAt = 'stored_grades_updated_at';
// User PIN for secondary authentication (fallback for biometrics).
// Stored as a salted SHA-256 hash (never plaintext).
const kStoragePin = 'user_pin';
// Random per-user salt for the PIN hash.
const kStoragePinSalt = 'user_pin_salt';
// Consecutive failed PIN attempts (current window), and lockout expiry
// timestamp (ISO-8601).
const kStoragePinAttempts = 'user_pin_attempts';
const kStoragePinLockUntil = 'user_pin_lock_until';
// Cumulative lockout count — never reset on lockout, only on a successful
// unlock or a new PIN. Drives the escalating lockout backoff.
const kStoragePinLockoutCount = 'user_pin_lockout_count';
// Length of the configured PIN, used to detect legacy short (<6) PINs that
// should be upgraded on next unlock.
const kStoragePinLength = 'user_pin_length';
// Cached coefficients JSON — keyed per dept_semester_year.
const kStorageCoefficientsPrefix = 'coefficients_';
// Last-submitted grades hash — keyed per dept_semester_year, used to skip
// redundant Cloudflare Worker submissions when grades haven't changed.
const kStorageSubmittedHashPrefix = 'submitted_hash_';
// Cached class averages JSON — keyed per dept_semester_year.
const kStorageAveragesPrefix = 'averages_';
// Academic year of the most recent grades fetch (e.g. "2025-2026"). Frozen at
// fetch time so cache keys for a given snapshot don't drift across the August
// academic-year boundary; only a fresh fetch advances it.
const kStorageAcademicYearBaseline = 'academic_year_baseline';
