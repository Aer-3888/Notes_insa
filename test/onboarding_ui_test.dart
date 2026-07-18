import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/app_colors.dart';
import 'package:notes_insa/screens/onboarding/onboarding_theme.dart';
import 'package:notes_insa/screens/onboarding/slides/credentials_slide.dart';

void main() {
  testWidgets('login stays usable on a compact phone viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final username = TextEditingController();
    final password = TextEditingController();
    addTearDown(username.dispose);
    addTearDown(password.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildOnboardingTheme(ThemeData(useMaterial3: true)),
        home: Scaffold(
          backgroundColor: AppColors.onboardingBg,
          body: SafeArea(
            child: CredentialsSlide(
              userController: username,
              passController: password,
              onConnect: () {},
              isLoading: false,
              stepCount: 1,
              currentIndex: 0,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('Relevé'), findsNothing);

    var button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Se connecter'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'prenom.nom');
    await tester.enterText(find.byType(TextField).last, 'mot-de-passe');
    await tester.pump();

    button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Se connecter'),
    );
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authentication error is shown next to the form', (tester) async {
    final username = TextEditingController(text: 'prenom.nom');
    final password = TextEditingController(text: 'mot-de-passe');
    addTearDown(username.dispose);
    addTearDown(password.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildOnboardingTheme(ThemeData(useMaterial3: true)),
        home: Scaffold(
          backgroundColor: AppColors.onboardingBg,
          body: SafeArea(
            child: CredentialsSlide(
              userController: username,
              passController: password,
              onConnect: () {},
              isLoading: false,
              error: 'Erreur d’authentification',
              stepCount: 3,
              currentIndex: 0,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Erreur d’authentification'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
