import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herenow/core/state/auth_provider.dart';
import 'package:herenow/core/state/session_provider.dart';
import 'package:herenow/main.dart';
import 'package:herenow/ui/screens/auth/login_screen.dart';
import 'package:herenow/ui/screens/home/home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('HereNow App launches and requires authentication (renders LoginScreen)', (WidgetTester tester) async {
    await tester.pumpWidget(const HereNowApp());
    await tester.pumpAndSettle();

    // Verify brand title
    expect(find.text('HereNow'), findsOneWidget);

    // Verify authentication is mandatory: shows Sign In form
    expect(find.text('Sign In'), findsNWidgets(2));
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // Guest login option must NOT exist
    expect(find.text('Continue as Guest / Offline'), findsNothing);
  });

  testWidgets('LoginScreen toggles between Sign In and Create Account without guest options', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Sign In mode elements
    expect(find.text('Sign In'), findsNWidgets(2)); // Switcher + button
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Continue as Guest / Offline'), findsNothing);

    // Switch to Create Account mode
    await tester.tap(find.text('Create Account').first);
    await tester.pumpAndSettle();

    // Verify Create Account fields
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Phone Number (Optional)'), findsOneWidget);
    expect(find.text('Create Account'), findsNWidgets(2)); // Switcher + button
  });

  testWidgets('HomeScreen renders clean empty state when no active session exists', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => SessionProvider()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify brand and core message
    expect(find.text('HereNow'), findsOneWidget);
    expect(find.text("Know who's here,\nwithout calling everyone."), findsOneWidget);

    // Verify core action buttons
    expect(find.text('Create Check'), findsOneWidget);
    expect(find.text('Join Session'), findsOneWidget);

    // Verify clean empty states (NOT fake Company Trip)
    expect(find.text('No Active Session'), findsOneWidget);
    expect(find.text('No recent sessions'), findsOneWidget);
    expect(find.text('Company Trip — Digha'), findsNothing);
    expect(find.text('Switch to Member'), findsNothing);
    expect(find.text('Switch to Organizer'), findsNothing);
  });
}
