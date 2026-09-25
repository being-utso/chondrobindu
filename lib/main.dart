import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_wrapper.dart';
import 'screens/journal_screen.dart';
import 'services/background_audit_service.dart';
import 'services/notification_service.dart';
import 'services/tour_service.dart';
import 'core/theme/app_theme.dart';

/// Configures Firebase Auth persistence with graceful web fallbacks for Safari/WebKit
Future<void> configureAuthPersistence() async {
  if (kIsWeb) {
    try {
      // Set to browser session persistence to prevent Safari IndexedDB lockups
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } catch (e) {
      debugPrint('Warning setting web auth persistence LOCAL: $e');
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
      } catch (e2) {
        debugPrint('Warning setting web auth persistence SESSION: $e2');
        try {
          // Fallback to in-memory persistence if IndexedDB is completely blocked/hidden
          await FirebaseAuth.instance.setPersistence(Persistence.NONE);
        } catch (e3) {
          debugPrint('Warning setting web auth persistence NONE: $e3');
        }
      }
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Safe Web Auth Persistence initialization for WebKit / Safari
    await configureAuthPersistence();

    // Explicitly configure Cloud Firestore offline persistence with unlimited cache
    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } else {
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (e) {
        debugPrint('Firestore web persistence disabled/error: $e');
      }
    }

    // Initialize notification service and timezone data
    await NotificationService().init();

    // Initialize Onboarding Tour Service local cache
    await TourService().initialize();

    // Task 1: Initialize Workmanager & register daily periodic audit with network & battery constraints
    if (!kIsWeb) {
      await BackgroundAuditService.initializeWorkmanager();
    }
  } catch (e) {
    debugPrint('Initialization error: $e');
  }

  runApp(
    // ProviderScope required for Riverpod state management
    const ProviderScope(
      child: ChondrobinduApp(),
    ),
  );
}

class ChondrobinduApp extends StatelessWidget {
  const ChondrobinduApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chondrobindu',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AuthWrapper(),
      builder: (context, child) {
        return Container(
          color: const Color(0xFF151211), // Base dark espresso canvas background
          child: child ?? const SizedBox.shrink(),
        );
      },
      routes: {
        '/journal': (context) => const JournalScreen(initialTag: 'Study Sessions'),
      },
    );
  }
}
