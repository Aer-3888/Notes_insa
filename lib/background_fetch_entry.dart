import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'services/background_fetch.dart';

/// Channel shared with GradesBackgroundWorker.kt.
const MethodChannel _channel = MethodChannel(
  'com.aer.notes_insa/background_fetch',
);

/// Entry point for the headless isolate the background worker starts.
///
/// The worker holds the credentials and hands them over, so nothing here reads
/// storage and no plugin needs registering in this isolate.
@pragma('vm:entry-point')
Future<void> backgroundFetchMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final args = await _channel.invokeMapMethod<String, dynamic>('takeRequest');
    if (args == null) {
      await _channel.invokeMethod<void>('failed', <String, dynamic>{
        'status': 'retry',
      });
      return;
    }

    final result = await runBackgroundFetch(
      username: args['username'] as String,
      password: args['password'] as String,
      otpSecret: args['otpSecret'] as String?,
      casSession: args['casSession'] as String?,
      claimedTotpStep: (args['claimedTotpStep'] as num?)?.toInt(),
      claimTotpStep: (int step) async {
        await _channel.invokeMethod<void>('claimTotpStep', <String, dynamic>{
          'step': step,
        });
      },
    );

    await _channel.invokeMethod<void>('complete', <String, dynamic>{
      'status': result.status.name,
      'gradesJson': result.gradesJson,
      'casSession': result.casSession,
    });
  } catch (e) {
    await _channel.invokeMethod<void>('failed', <String, dynamic>{
      'status': 'retry',
      'reason': '$e',
    });
  }
}
