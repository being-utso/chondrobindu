import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/screens/auth_screen.dart';
import 'package:chondrobindu/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AuthScreen Portal & Dual-Pane Tests', () {
    testWidgets('Desktop view renders dual-pane layout with left brand poster and right auth card', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const ProviderScope(
            child: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Brand Poster Elements (Left Pane)
      expect(find.text('• CHONDROBINDU ACADEMIC OS'), findsOneWidget);
      expect(find.text('Built for rigorous semesters & deep focus.'), findsOneWidget);
      expect(find.text('3-Level Syllabus Tree'), findsOneWidget);
      expect(find.text('Exam-Aware Routine & CT Ledger'), findsOneWidget);
      expect(find.text('Live Pomodoro & CGPA Forecaster'), findsOneWidget);
      expect(find.text('— SCHOLASTIC MAXIM'), findsOneWidget);

      // Sign In Form View (Right Pane initial state)
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Enter Workspace'), findsOneWidget);
    });

    testWidgets('Switching to Create Account reveals academic track toggle and conditional admission fields', (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const ProviderScope(
            child: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Create Account" tab
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Create Scholar Account'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Create Password'), findsOneWidget);
      expect(find.text('ACADEMIC TRACK'), findsOneWidget);
      expect(find.text('🏛️ University (4.00)'), findsOneWidget);
      expect(find.text('📚 College / Admission (5.00)'), findsOneWidget);

      // Switch to College / Admission Track
      await tester.tap(find.text('📚 College / Admission (5.00)'));
      await tester.pumpAndSettle();

      // Conditional College fields
      expect(find.text('LAST ATTENDED COLLEGE / INSTITUTION'), findsOneWidget);
      expect(find.text('HSC BATCH'), findsOneWidget);
      expect(find.text('HSC GROUP / DIVISION'), findsOneWidget);
      expect(find.text('Admission Candidate'), findsOneWidget);

      // Conditional Target Cards for default Science group
      expect(find.text('PRIMARY ADMISSION TARGET'), findsOneWidget);
      expect(find.text('BUET / Engineering'), findsWidgets);
      expect(find.text('Medical / Dental'), findsWidgets);
      expect(find.text('Varsity A-Unit (Science)'), findsWidgets);
      expect(find.text('IBA / BBA'), findsWidgets);

      // Select Medical target
      await tester.tap(find.text('Medical / Dental').first);
      await tester.pumpAndSettle();

      // Create button
      expect(find.text('Create Account & Initialize'), findsOneWidget);
    });

    testWidgets('Mobile view renders single-column responsive portal layout', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const ProviderScope(
            child: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mobile brand header
      expect(find.text('চন্দ্রবিন্দু'), findsOneWidget);
      expect(find.text('CHONDROBINDU ACADEMIC OS'), findsOneWidget);

      // Sign in elements
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Enter Workspace'), findsOneWidget);
    });
  });
}
