import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single, consistently configured [FlutterSecureStorage] instance shared by
/// every service so all secrets are stored with the same platform options.
///
/// Android: the flutter_secure_storage 10.x default already encrypts values
/// with AES-GCM under an Android Keystore wrapped key, so no extra Android
/// options are needed. The old encryptedSharedPreferences flag is deprecated
/// and ignored in 10.x.
///
/// Apple (iOS and macOS, for the staged port): pin keychain items to this
/// device after first unlock. They stay unreadable before the first unlock
/// following a reboot and are never eligible for iCloud Keychain sync, so INSA
/// credentials and the OTP secret remain on device only.
const FlutterSecureStorage kSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  mOptions: MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);
