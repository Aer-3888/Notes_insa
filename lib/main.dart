import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_colors.dart';
import 'core/time.dart';
import 'background_tasks.dart';
import 'constants.dart';
import 'core/auth/privacy_cover.dart';
import 'shell/campus_shell.dart';

// Root navigator key so lifecycle handling can dismiss open modal routes
// (bottom sheets, dialogs, pushed screens) when the app is backgrounded.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCampusTime();
  if (kAppSecret.isEmpty) {
    throw StateError('APP_SECRET not provided via --dart-define');
  }
  unawaited(initBackgroundTasks());
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Campus INSA',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: AppColors.scaffoldBg,
        useMaterial3: true,
      ),
      // Wrap every route in a privacy curtain so the OS task-switcher snapshot
      // never reveals user data. Sits above the Navigator, so it also covers
      // open bottom sheets and dialogs.
      builder: (context, child) =>
          PrivacyCover(child: child ?? const SizedBox.shrink()),
      home: const CampusShell(),
    );
  }
}
