import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../providers/nav_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/tour_service.dart';
import '../utils/safe_haptics.dart';
import '../widgets/app_loading_screen.dart';
import '../widgets/app_logo.dart';
import 'home_dashboard.dart';
import 'insights_screen.dart';
import 'journal_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';
import 'planner_screen.dart';
import 'profile_screen.dart';
import 'syllabus_screen.dart';
import 'timer_screen.dart';
import 'university_dashboard_screen.dart';

/// Main Mobile Navigation Shell wrapping:
/// - Top App Bar: Compact brand logo + action icons (Journal, Theme toggle, Notifications, Profile avatar).
/// - Bottom Dock (5 tabs): [ Home | Courses | Timer | Planner | Insights ]
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  bool? _wasWide;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    User? currentUser;
    try {
      if (Firebase.apps.isNotEmpty) {
        currentUser = FirebaseAuth.instance.currentUser;
      }
    } catch (_) {
      currentUser = null;
    }

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

    // Safely dismiss any active PopupRoute (e.g. PopupMenuButton on DesktopNavBar)
    // when transitioning across the desktop-to-mobile breakpoint so no orphaned barrier remains.
    if (_wasWide != null && _wasWide != isWide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
          } catch (_) {}
        }
      });
    }
    _wasWide = isWide;

    if (isWide) {
      return const MainShell();
    }

    final bool isUni = profile.isUniversityStudent;
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mobile tab screens (5 tabs: Home, Courses/Syllabus, Timer, Planner, Insights)
    final List<Widget> screens = [
      const HomeDashboardScreen(),
      isUni ? const UniversityDashboardScreen() : const SyllabusScreen(),
      const TimerScreen(),
      const PlannerScreen(),
      const InsightsScreen(),
    ];

    // Map desktop/external 6-tab index (where Journal was 4, Insights was 5)
    // to mobile 5-tab dock index safely:
    // 0: Home, 1: Courses, 2: Timer, 3: Planner, 4: Insights (or 5 -> 4)
    int effectiveMobileIndex = selectedIndex;
    if (effectiveMobileIndex >= screens.length) {
      effectiveMobileIndex = screens.length - 1; // Map Insights (5) to 4
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isTimerScreen = effectiveMobileIndex == 2;
    final hideBottomNav = isLandscape && isTimerScreen;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: _buildMobileTopAppBar(context, profile, colors, isDark),
      body: ShowCaseWidget(
        enableAutoScroll: true,
        blurValue: 2.0,
        builder: (showcaseContext) => IndexedStack(
          index: effectiveMobileIndex.clamp(0, screens.length - 1),
          children: screens,
        ),
      ),
      bottomNavigationBar: hideBottomNav
          ? null
          : _buildMobileBottomDock(context, effectiveMobileIndex, isUni, colors, isDark),
    );
  }

  /// Compact Brand Logo + Action Icons (Journal, Theme Toggle, Notifications, Profile Avatar)
  PreferredSizeWidget _buildMobileTopAppBar(
    BuildContext context,
    UserProfile profile,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final photoUrl = profile.photoUrl.isNotEmpty ? profile.photoUrl : profile.profileImageUrl;
    final displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.fullName.isNotEmpty ? profile.fullName.split(' ').first : 'Student');

    return AppBar(
      backgroundColor: colors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16.0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(
            size: 28,
            showContainer: false,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'চন্দ্রবিন্দু',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.primary,
                  fontSize: 15.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  height: 1.1,
                ),
              ),
              Text(
                'CHONDROBINDU',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.secondary,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: colors.surfaceBorder,
          height: 1.0,
        ),
      ),
      actions: [
        // 1. Journal Action Icon
        IconButton(
          tooltip: 'Academic Journal',
          icon: Icon(Icons.edit_note_rounded, color: colors.textMuted, size: 22),
          onPressed: () {
            SafeHaptics.selectionClick();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const JournalScreen()),
            );
          },
        ),

        // 2. Theme Toggle Action Icon
        IconButton(
          tooltip: isDark ? 'Switch to Lime Wash' : 'Switch to Indigo Slate',
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: colors.textMuted,
            size: 20,
          ),
          onPressed: () {
            SafeHaptics.selectionClick();
            ref.read(themeModeProvider.notifier).toggleTheme();
          },
        ),

        // 3. Notifications Bell Action Icon
        IconButton(
          tooltip: 'Notifications',
          icon: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications_none_rounded, color: colors.textMuted, size: 21),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 1.2),
                  ),
                ),
              ),
            ],
          ),
          onPressed: () {
            SafeHaptics.selectionClick();
            // Jump to Planner tab to view timeline/alerts
            ref.read(navigationIndexProvider.notifier).state = 3;
          },
        ),

        // 4. Profile Avatar Action
        Padding(
          padding: const EdgeInsets.only(right: 12.0, left: 4.0),
          child: GestureDetector(
            onTap: () {
              SafeHaptics.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: CircleAvatar(
              radius: 15,
              backgroundColor: colors.surfaceBorder,
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Mobile Bottom Dock with 5 tabs: [ Home | Courses | Timer | Planner | Insights ]
  Widget _buildMobileBottomDock(
    BuildContext context,
    int activeIndex,
    bool isUni,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.95),
            border: Border(
              top: BorderSide(
                color: colors.surfaceBorder,
                width: 1.0,
              ),
            ),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              elevation: 0,
              height: 62,
              indicatorColor: colors.primary.withValues(alpha: isDark ? 0.22 : 0.15),
              indicatorShape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusPill),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return GoogleFonts.plusJakartaSans(
                    color: colors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  );
                }
                return GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 11.0,
                  fontWeight: FontWeight.w500,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: colors.primary, size: 22);
                }
                return IconThemeData(color: colors.textMuted, size: 22);
              }),
            ),
            child: NavigationBar(
              selectedIndex: activeIndex,
              onDestinationSelected: (index) {
                SafeHaptics.selectionClick();
                TourService().dismissActiveTour();
                // Map mobile tab 4 (Insights) to index 5 on desktop if needed,
                // or keep 4 synchronized
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
    );
  }
}
