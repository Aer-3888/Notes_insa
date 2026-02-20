import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/auth_service.dart';
import 'providers/grades_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'background_tasks.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackgroundTasks();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Insa Notes',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// Provider for authentication state
final authCheckProvider = FutureProvider<bool>((ref) async {
  final authService = AuthService();

  // Load stored grades first for instant display
  await ref.read(gradesProvider.notifier).loadStoredGrades();

  // Check if we have credentials stored
  final hasCreds = await authService.isLoggedIn();

  if (!hasCreds) return false;

  // If stored, ask for Biometrics
  final bioSuccess = await authService.authenticate();

  if (!bioSuccess) return false;

  // Fetch grades using stored credentials
  try {
    await ref.read(gradesProvider.notifier).fetchGradesWithStoredCredentials();
    return true;
  } catch (_) {
    // Even if fetch fails, allow login if biometrics passed
    return true;
  }
});

// Authentication gate that decides whether to show Login or Dashboard.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authCheck = ref.watch(authCheckProvider);

    return authCheck.when(
      data: (isLoggedIn) {
        return isLoggedIn ? const DashboardScreen() : const LoginScreen();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => const LoginScreen(),
    );
  }
}
