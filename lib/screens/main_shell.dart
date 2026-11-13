import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../providers/nav_provider.dart';
import '../providers/timer_provider.dart';
import '../widgets/desktop_nav_bar.dart';
import 'courses_screen.dart';
import 'home_screen.dart';
import 'insights_screen.dart';
import 'journal_screen.dart';
import 'planner_screen.dart';
import 'timer_screen.dart';

/// Unified stateful desktop navigation shell (width >= 800px).
/// Embeds [DesktopNavBar] (60px) pinned at the top and an [IndexedStack] body
/// supporting 6 core workspaces:
/// 0: Home Command Center
/// 1: Courses & Granular Syllabus Workspace
/// 2: Deep Focus Timer
/// 3: Timetable Matrix & Planner
/// 4: Academic Journal & Brain Dump
/// 5: Academic Analytics & Insights
class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _selectedIndex;

  final List<Widget> _screens = const [
    HomeScreen(),
    CoursesScreen(),
    TimerScreen(),
    PlannerScreen(),
    JournalScreen(),
    InsightsScreen(),
  ];

  NavigatorState? _rootNavigator;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(navigationIndexProvider.notifier).state = widget.initialIndex;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rootNavigator = Navigator.maybeOf(context, rootNavigator: true);
  }

  @override
  void deactivate() {
    final nav = _rootNavigator;
    if (nav != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          nav.popUntil((route) => route is! PopupRoute);
        } catch (_) {}
      });
    }
    super.deactivate();
  }

  void _onDestinationSelected(int index) {
    if (index >= 0 && index < _screens.length) {
      setState(() {
        _selectedIndex = index;
      });
      ref.read(navigationIndexProvider.notifier).state = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(timerProvider);
    final colors = AppColors.of(context);
    // Keep synchronized with Riverpod navigationIndexProvider for external triggers (e.g. "Start Focus →")
    final navIndex = ref.watch(navigationIndexProvider);
    final activeIndex = (navIndex >= 0 && navIndex < _screens.length) ? navIndex : _selectedIndex;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: DesktopNavBar(
        selectedIndex: activeIndex,
        onDestinationSelected: _onDestinationSelected,
      ),
      body: IndexedStack(
        index: activeIndex.clamp(0, _screens.length - 1),
        children: _screens,
      ),
    );
  }
}

/// Convenience alias requested for unified dashboard architecture
typedef DashboardScreen = MainShell;
