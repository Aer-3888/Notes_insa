/// Base URL for the Notes INSA Cloudflare Worker.
/// No trailing slash — service methods append /submit and /averages.
const kWorkerBaseUrl = 'https://notesinsa.theo-phan-quoc-huy.workers.dev';

/// Secret shared with the Cloudflare Worker to authenticate submissions.
/// Pass this at build time using: --dart-define=APP_SECRET=your_secret_here
const kAppSecret = String.fromEnvironment(
  'APP_SECRET',
  defaultValue: 'development_fallback',
);

/// Salt for computing the anonymous user hash.
/// Pass this at build time using: --dart-define=USER_HASH_SALT=your_salt_here
const kUserHashSalt = String.fromEnvironment(
  'USER_HASH_SALT',
  defaultValue: 'notes-insa-user-v1',
);

/// Storage keys for FlutterSecureStorage.
const kStorageToken = 'api_token';
const kStorageUser = 'username';
const kStoragePass = 'password';
