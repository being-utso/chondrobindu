import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/nav_provider.dart';
import '../providers/user_profile_provider.dart';
import '../screens/auth_screen.dart';
import '../screens/profile_screen.dart';
import '../utils/safe_haptics.dart';

/// Global Top Navigation Shell pinned across desktop views (width >= 800px).
/// Implements Dark Espresso aesthetic (#140F0E, #1E1816, #2E2623, #F2B78A).
class DesktopNavBar extends ConsumerWidget implements PreferredSizeWidget {
  final int? selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  const DesktopNavBar({
    super.key,
    this.selectedIndex,
    this.onDestinationSelected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  void _showGlobalSearchPalette(BuildContext context, WidgetRef ref) {
    SafeHaptics.selectionClick();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogCtx) => _GlobalSearchDialog(
        onDestinationSelected: onDestinationSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIndex = selectedIndex ?? ref.watch(navigationIndexProvider);
    final liveProfileAsync = ref.watch(liveUserProfileProvider);
    final fallbackProfile = ref.watch(userProfileProvider);
    final profile = liveProfileAsync.value ?? fallbackProfile;
    final String displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.fullName.isNotEmpty ? profile.fullName.split(' ').first : 'Student');
    final photoUrl = profile.photoUrl.isNotEmpty ? profile.photoUrl : profile.profileImageUrl;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyK &&
            (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
          _showGlobalSearchPalette(context, ref);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        height: 64.0,
        decoration: const BoxDecoration(
          color: Color(0xFF140F0E),
          border: Border(
            bottom: BorderSide(
              color: Color(0xFF2E2623),
              width: 1.0,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            // Left: Moon Crescent + Bengali Wordmark + Subtitle
            _buildBrand(),

            const SizedBox(width: 16.0),

            // Center: Navigation Tabs
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.hardEdge,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _NavTabItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      label: 'Home',
                      isSelected: activeIndex == 0,
                      onTap: () {
                        SafeHaptics.selectionClick();
                        onDestinationSelected?.call(0);
                        ref.read(navigationIndexProvider.notifier).state = 0;
                      },
                    ),
                    _NavTabItem(
                      icon: Icons.school_outlined,
                      selectedIcon: Icons.school_rounded,
                      label: 'Courses',
                      isSelected: activeIndex == 1,
                      onTap: () {
                        SafeHaptics.selectionClick();
                        onDestinationSelected?.call(1);
                        ref.read(navigationIndexProvider.notifier).state = 1;
                      },
                    ),
                    _NavTabItem(
                      icon: Icons.timer_outlined,
                      selectedIcon: Icons.timer_rounded,
                      label: 'Timer',
                      isSelected: activeIndex == 2,
                      onTap: () {
                        SafeHaptics.selectionClick();
                        onDestinationSelected?.call(2);
                        ref.read(navigationIndexProvider.notifier).state = 2;
                      },
                    ),
                    _NavTabItem(
                      icon: Icons.calendar_month_outlined,
                      selectedIcon: Icons.calendar_month_rounded,
                      label: 'Planner',
                      isSelected: activeIndex == 3,
                      onTap: () {
                        SafeHaptics.selectionClick();
                        onDestinationSelected?.call(3);
                        ref.read(navigationIndexProvider.notifier).state = 3;
                      },
                    ),
                    _NavTabItem(
                      icon: Icons.insights_outlined,
                      selectedIcon: Icons.insights_rounded,
                      label: 'Insights',
                      isSelected: activeIndex == 4,
                      onTap: () {
                        SafeHaptics.selectionClick();
                        onDestinationSelected?.call(4);
                        ref.read(navigationIndexProvider.notifier).state = 4;
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 16.0),

            // Right: Quick Search, Notification Bell, Profile Chip
            _buildRightActions(context, ref, profile, displayName, photoUrl),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Moon Crescent Glyph with soft glow
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1816),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF382A24), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.dark_mode_rounded,
            color: Color(0xFFF2B78A),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'চন্দ্রবিন্দু',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFF2B78A),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF2B78A),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            Text(
              'CHONDROBINDU',
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF9E8C82),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRightActions(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    String name,
    String? imageUrl,
  ) {
    final assessments = ref.watch(upcomingAssessmentsStreamProvider).value ?? [];
    final now = DateTime.now();
    final in3Days = now.add(const Duration(days: 3));
    final upcomingAlerts = assessments.where((a) {
      if (a.date == null) return false;
      return a.date!.isAfter(now.subtract(const Duration(hours: 12))) && a.date!.isBefore(in3Days);
    }).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick Command / Search Bar Pill
        InkWell(
          onTap: () => _showGlobalSearchPalette(context, ref),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 36,
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1816),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF9E8C82),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search anything...',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF9E8C82),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF241C1A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF382A24), width: 0.8),
                  ),
                  child: Text(
                    '⌘K',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF9E8C82),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 14),

        // Notification Bell Popup
        PopupMenuButton<void>(
          tooltip: 'Notifications & Alerts',
          offset: const Offset(0, 48),
          color: const Color(0xFF1E1816),
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF2E2623), width: 1),
          ),
          itemBuilder: (menuCtx) {
            if (upcomingAlerts.isEmpty) {
              return [
                PopupMenuItem<void>(
                  enabled: false,
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF34D399), size: 36),
                        const SizedBox(height: 10),
                        Text(
                          'All caught up! No upcoming exam or routine alerts.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFEDE8E3),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ];
            }
            return [
              PopupMenuItem<void>(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    'UPCOMING ALERTS (${upcomingAlerts.length})',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFF2B78A),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const PopupMenuDivider(height: 1),
              ...upcomingAlerts.take(5).map((a) {
                final days = a.date!.difference(now).inDays;
                final dueStr = days <= 0
                    ? 'Due Today'
                    : (days == 1 ? 'Due Tomorrow' : 'Due in $days days');
                return PopupMenuItem<void>(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    onDestinationSelected?.call(3);
                    ref.read(navigationIndexProvider.notifier).state = 3;
                  },
                  child: SizedBox(
                    width: 280,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF241C1A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF382A24)),
                          ),
                          child: Text(
                            a.courseCode,
                            style: GoogleFonts.jetBrainsMono(
                              color: const Color(0xFFF2B78A),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                a.name,
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFFEDE8E3),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                dueStr,
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFFEF4444),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ];
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFFABA093),
                  size: 21,
                ),
              ),
              if (upcomingAlerts.isNotEmpty)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF140F0E), width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Profile Chip with Popup Menu
        PopupMenuButton<String>(
          tooltip: 'User Profile & Settings',
          offset: const Offset(0, 48),
          color: const Color(0xFF1E1816),
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF2E2623), width: 1),
          ),
          onSelected: (value) async {
            if (value == 'track') {
              SafeHaptics.selectionClick();
              final newIsUni = !profile.isUniversityStudent;
              final newTrack = newIsUni ? InstitutionType.university : InstitutionType.college;
              final updated = profile.copyWith(
                isUniversityStudent: newIsUni,
                institutionType: newTrack,
              );
              await ref.read(userProfileProvider.notifier).saveProfile(updated);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Switched academic track to ${newTrack.displayName}'),
                    backgroundColor: const Color(0xFF1E1816),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } else if (value == 'settings') {
              SafeHaptics.selectionClick();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            } else if (value == 'sign_out') {
              SafeHaptics.mediumImpact();
              if (Firebase.apps.isNotEmpty) {
                await FirebaseAuth.instance.signOut();
              }
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              }
            }
          },
          itemBuilder: (menuCtx) => [
            // Header: Display user's displayName and email with divider
            PopupMenuItem<String>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.displayName.isNotEmpty ? profile.displayName : name,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFEDE8E3),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.email.isNotEmpty ? profile.email : 'student@chondrobindu.edu',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF9E8C82),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFF2E2623), height: 1),
                ],
              ),
            ),
            // Academic Track Item with toggle option
            PopupMenuItem<String>(
              value: 'track',
              child: Row(
                children: [
                  const Icon(Icons.school_outlined, color: Color(0xFFF2B78A), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Academic Track',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFEDE8E3),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          profile.isUniversityStudent ? 'University' : 'College',
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFF9E8C82),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF241C1A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF382A24)),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFFF2B78A), size: 14),
                  ),
                ],
              ),
            ),
            // Settings Item
            PopupMenuItem<String>(
              value: 'settings',
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined, color: Color(0xFF9E8C82), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Settings',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFEDE8E3),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(height: 8),
            // Sign Out Item
            PopupMenuItem<String>(
              value: 'sign_out',
              child: Row(
                children: [
                  const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Sign Out',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFEF4444),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1816),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFF382A24),
                  backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                      ? NetworkImage(imageUrl)
                      : null,
                  child: (imageUrl == null || imageUrl.isEmpty)
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'S',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFF2B78A),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFEDE8E3),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF9E8C82),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavTabItem extends StatefulWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavTabItem> createState() => _NavTabItemState();
}

class _NavTabItemState extends State<_NavTabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool active = widget.isSelected;
    final Color textColor = active
        ? const Color(0xFFF2B78A)
        : (_isHovered ? const Color(0xFFEDE8E3) : const Color(0xFF9E8C82));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFFF2B78A) : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? widget.selectedIcon : widget.icon,
                color: textColor,
                size: 18,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: GoogleFonts.plusJakartaSans(
                  color: textColor,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Global Search Command Palette Dialog (`⌘K` / click)
class _GlobalSearchDialog extends ConsumerStatefulWidget {
  final ValueChanged<int>? onDestinationSelected;

  const _GlobalSearchDialog({this.onDestinationSelected});

  @override
  ConsumerState<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<_GlobalSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesStreamProvider).value ?? [];
    final assessments = ref.watch(upcomingAssessmentsStreamProvider).value ?? [];
    final q = _query.trim().toLowerCase();

    final matchedCourses = q.isEmpty
        ? <Course>[]
        : courses.where((c) =>
            c.code.toLowerCase().contains(q) ||
            c.title.toLowerCase().contains(q)).toList();

    final matchedAssessments = q.isEmpty
        ? <Assessment>[]
        : assessments.where((a) =>
            a.name.toLowerCase().contains(q) ||
            a.courseCode.toLowerCase().contains(q)).toList();

    final bool hasResults = matchedCourses.isNotEmpty || matchedAssessments.isNotEmpty;

    return Dialog(
      backgroundColor: const Color(0xFF1E1816),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2E2623), width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Input Row
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF241C1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF382A24), width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFFF2B78A), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search courses, topics, assessments...',
                          hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 14),
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => setState(() => _query = val),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF9E8C82), size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1816),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF2E2623)),
                      ),
                      child: Text(
                        'ESC',
                        style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Results List
              Flexible(
                child: q.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.travel_explore_rounded, color: Color(0xFF382A24), size: 40),
                              const SizedBox(height: 10),
                              Text(
                                'Type a course code (e.g. EEE 2105) or assessment name...',
                                style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : !hasResults
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 36.0),
                              child: Text(
                                'No matching courses or assessments found.',
                                style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                              ),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              if (matchedCourses.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                                  child: Text(
                                    'COURSES',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: const Color(0xFF9E8C82),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                ...matchedCourses.map((c) => ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  leading: const Icon(Icons.school_outlined, color: Color(0xFFF2B78A), size: 20),
                                  title: Text(
                                    '${c.code} • ${c.title}',
                                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '${c.credits} Credits • ${c.courseType.displayName}',
                                    style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 11),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    widget.onDestinationSelected?.call(1);
                                    ref.read(navigationIndexProvider.notifier).state = 1;
                                  },
                                )),
                                const SizedBox(height: 12),
                              ],
                              if (matchedAssessments.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                                  child: Text(
                                    'ASSESSMENTS & EXAMS',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: const Color(0xFF9E8C82),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                ...matchedAssessments.map((a) => ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  leading: const Icon(Icons.assignment_outlined, color: Color(0xFF34D399), size: 20),
                                  title: Text(
                                    '${a.courseCode} — ${a.name}',
                                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    a.date != null ? 'Date: ${a.date!.day}/${a.date!.month}/${a.date!.year}' : 'Unscheduled',
                                    style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 11),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    widget.onDestinationSelected?.call(3);
                                    ref.read(navigationIndexProvider.notifier).state = 3;
                                  },
                                )),
                              ],
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
