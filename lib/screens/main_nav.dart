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
import '../providers/timer_provider.dart';
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
/// - Bottom Dock (6 tabs): [ Home | Courses | Timer | Planner | Journal | Insights ]
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  bool? _wasWide;

  @override
  Widget build(BuildContext context) {
    ref.watch(timerProvider);
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

    // Mobile tab screens (6 tabs: Home, Courses/Syllabus, Timer, Planner, Journal, Insights)
    final List<Widget> screens = [
      const HomeDashboardScreen(),
      isUni ? const UniversityDashboardScreen() : const SyllabusScreen(),
      const TimerScreen(),
      const PlannerScreen(),
      const JournalScreen(),
      const InsightsScreen(),
    ];

    // Synchronized 6-tab dock index matching desktop exactly:
    // 0: Home, 1: Courses, 2: Timer, 3: Planner, 4: Journal, 5: Insights
    final int effectiveMobileIndex = selectedIndex.clamp(0, screens.length - 1);

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
      titleSpacing: 12.0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(
            size: 26,
            showContainer: false,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'চন্দ্রবিন্দু',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.primary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'CHONDROBINDU',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.secondary,
                    fontSize: 8.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(Icons.edit_note_rounded, color: colors.textMuted, size: 21),
          onPressed: () {
            SafeHaptics.selectionClick();
            ref.read(navigationIndexProvider.notifier).state = 4;
          },
        ),

        // 2. Theme Toggle Action Icon
        IconButton(
          tooltip: isDark ? 'Switch to Lime Wash' : 'Switch to Indigo Slate',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            color: colors.textMuted,
            size: 19,
          ),
          onPressed: () {
            SafeHaptics.selectionClick();
            ref.read(themeModeProvider.notifier).toggleTheme();
          },
        ),

        // 3. Notifications Bell Action Icon
        IconButton(
          tooltip: 'Notifications',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications_none_rounded, color: colors.textMuted, size: 20),
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
          padding: const EdgeInsets.only(right: 12.0, left: 2.0),
          child: GestureDetector(
            onTap: () {
              SafeHaptics.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: CircleAvatar(
              radius: 14,
              backgroundColor: colors.surfaceBorder,
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Mobile Bottom Dock with 6 tabs: [ Home | Courses | Timer | Planner | Journal | Insights ]
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
              height: 64,
              indicatorColor: colors.primary.withValues(alpha: isDark ? 0.22 : 0.15),
              indicatorShape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusPill),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return GoogleFonts.plusJakartaSans(
                    color: colors.primary,
                    fontSize: 11.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  );
                }
                return GoogleFonts.plusJakartaSans(
                  color: isDark ? colors.primary.withValues(alpha: 0.60) : colors.textMuted,
                  fontSize: 11.0,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: colors.primary, size: 21);
                }
                return IconThemeData(
                  color: isDark ? colors.primary.withValues(alpha: 0.60) : colors.textMuted,
                  size: 21,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: activeIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
                  icon: Icon(Icons.auto_stories_outlined),
                  selectedIcon: Icon(Icons.auto_stories_rounded),
                  label: 'Journal',
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
