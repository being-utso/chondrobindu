import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../providers/nav_provider.dart';
import '../providers/profile_provider.dart';
import 'home_dashboard.dart';
import 'home_screen.dart';
import 'courses_screen.dart';
import 'syllabus_screen.dart';
import 'timer_screen.dart';
import 'planner_screen.dart';
import 'insights_screen.dart';
import 'onboarding_screen.dart';
import 'university_dashboard_screen.dart';
import '../widgets/app_loading_screen.dart';
import '../widgets/desktop_nav_bar.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:showcaseview/showcaseview.dart';
import '../providers/user_profile_provider.dart';
import '../services/tour_service.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Main Navigation Screen wrapping 5 tabs (Home, Syllabus/Courses, Timer, Exams, Insights)
class MainNavigationScreen extends ConsumerWidget {
  const MainNavigationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final currentUser = FirebaseAuth.instance.currentUser;

    // Task 4: Only route to Onboarding if user is signed in, profile is loaded, AND mandatory setup is missing
    if (currentUser != null) {
      if (!profile.isLoaded) {
        return const AppLoadingScreen(message: 'Loading academic profile...');
      }

      if (!profile.isProfileComplete) {
        return const OnboardingScreen();
      }
    }

    final selectedIndex = ref.watch(navigationIndexProvider);
    final bool isWide = MediaQuery.of(context).size.width >= 800;

    // Desktop screens
    final List<Widget> desktopScreens = [
      const HomeScreen(),
      const CoursesScreen(),
      const TimerScreen(),
      const PlannerScreen(),
      const InsightsScreen(),
    ];

    if (isWide) {
      return Scaffold(
        backgroundColor: const Color(0xFF151211),
        appBar: const DesktopNavBar(),
        body: IndexedStack(
          index: selectedIndex < desktopScreens.length ? selectedIndex : 0,
          children: desktopScreens,
        ),
      );
    }

    final bool isUni = profile.isUniversityStudent;

    // Mobile tab screens (Conditional: UniversityDashboardScreen for Uni students, SyllabusScreen for Admission candidates)
    final List<Widget> screens = [
      const HomeDashboardScreen(),
      isUni ? const UniversityDashboardScreen() : const SyllabusScreen(),
      const TimerScreen(),
      const PlannerScreen(),
      const InsightsScreen(),
    ];

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isTimerScreen = selectedIndex == 2;
    final hideBottomNav = isLandscape && isTimerScreen;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: ShowCaseWidget(
        enableAutoScroll: true,
        blurValue: 2.0,
        builder: (showcaseContext) => IndexedStack(
          index: selectedIndex < screens.length ? selectedIndex : 0,
          children: screens,
        ),
      ),
      bottomNavigationBar: hideBottomNav
          ? null
          : ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF140F0E),
                    border: Border(
                      top: BorderSide(
                        color: const Color(0xFF4A3830).withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                  ),
                  child: NavigationBarTheme(
                    data: NavigationBarThemeData(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      height: 64,
                      indicatorColor: const Color(0xFFF2B78A).withValues(alpha: 0.2),
                      indicatorShape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusPill),
                      labelTextStyle: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return const TextStyle(
                            color: Color(0xFFF2B78A),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          );
                        }
                        return const TextStyle(
                          color: Color(0xFFABA093),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        );
                      }),
                      iconTheme: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return const IconThemeData(color: Color(0xFFF2B78A), size: 22);
                        }
                        return const IconThemeData(color: Color(0xFFABA093), size: 22);
                      }),
                    ),
                    child: NavigationBar(
                      selectedIndex: selectedIndex < screens.length ? selectedIndex : 0,
                      onDestinationSelected: (index) {
                        SafeHaptics.selectionClick();
                        TourService().dismissActiveTour();
                        ref.read(navigationIndexProvider.notifier).state = index;
                      },
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: 'Home',
                        ),
                        NavigationDestination(
                          icon: Icon(isUni ? Icons.class_outlined : Icons.menu_book_outlined),
                          selectedIcon: Icon(isUni ? Icons.class_rounded : Icons.menu_book_rounded),
                          label: isUni ? 'Courses' : 'Syllabus',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.timer_outlined),
                          selectedIcon: Icon(Icons.timer_rounded),
                          label: 'Timer',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.calendar_month_outlined),
                          selectedIcon: Icon(Icons.calendar_month_rounded),
                          label: 'Planner',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.insights_outlined),
                          selectedIcon: Icon(Icons.insights_rounded),
                          label: 'Insights',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
