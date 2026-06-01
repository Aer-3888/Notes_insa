/// Base URL for the Notes INSA Cloudflare Worker.
/// No trailing slash — service methods append /submit and /averages.
const kWorkerBaseUrl = 'https://notesinsa.theo-phan-quoc-huy.workers.dev';

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
// User PIN for secondary authentication (fallback for biometrics).
// Stored as a salted SHA-256 hash (never plaintext).
const kStoragePin = 'user_pin';
// Random per-user salt for the PIN hash.
const kStoragePinSalt = 'user_pin_salt';
// Consecutive failed PIN attempts, and lockout expiry timestamp (ISO-8601).
const kStoragePinAttempts = 'user_pin_attempts';
const kStoragePinLockUntil = 'user_pin_lock_until';
// Cached coefficients JSON — keyed per dept_semester_year.
const kStorageCoefficientsPrefix = 'coefficients_';
