/// Base URL for the Notes INSA Cloudflare Worker.
/// No trailing slash — service methods append /submit and /averages.
const kWorkerBaseUrl = 'https://notesinsa.theo-phan-quoc-huy.workers.dev';

/// Secret shared with the Cloudflare Worker to authenticate submissions.
/// Pass this at build time using: --dart-define=APP_SECRET=your_secret_here
const kAppSecret = String.fromEnvironment('APP_SECRET');

/// Storage keys for FlutterSecureStorage.
const kStorageToken = 'api_token';
const kStorageUser = 'username';
const kStoragePass = 'password';
