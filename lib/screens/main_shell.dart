import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/nav_provider.dart';
import '../widgets/desktop_nav_bar.dart';
import 'home_screen.dart';
import 'courses_screen.dart';
import 'timer_screen.dart';
import 'planner_screen.dart';
import 'insights_screen.dart';

/// Unified stateful desktop navigation shell.
/// Embeds [DesktopNavBar] pinned at the top and an [IndexedStack] body
/// supporting 5 core workspaces:
/// 0: Home Command Center
/// 1: Courses & Syllabus Directory
/// 2: Deep Focus Timer
/// 3: Timetable Matrix & Planner
/// 4: Academic Analytics & Insights
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
    InsightsScreen(),
  ];

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
    // Keep synchronized with Riverpod navigationIndexProvider for external triggers (e.g. "Start Focus →")
    final navIndex = ref.watch(navigationIndexProvider);
    final activeIndex = (navIndex >= 0 && navIndex < _screens.length) ? navIndex : _selectedIndex;

    return Scaffold(
      backgroundColor: const Color(0xFF151211),
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
