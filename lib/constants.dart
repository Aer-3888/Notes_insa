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
const kStoragePin = 'user_pin';
