import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/nav_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_profile_provider.dart';
import '../screens/auth_screen.dart';
import '../screens/help_screen.dart';
import '../screens/profile_screen.dart';
import '../utils/safe_haptics.dart';
import 'app_logo.dart';

/// Global Top Navigation Bar for Desktop Views (60px height).
/// Implements Chondrobindu Dual-Theme Tokens:
/// - Light: bg-surface #F7F5F0, border #DCD7C8, primary accent #2F4A6D, text #1F2A3A / #5A6578
/// - Dark: bg-surface #202733, border #2E3846, primary accent #8FA8C8, text #EDEAE0 / #94A3B8
class DesktopNavBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final int? selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  const DesktopNavBar({
    super.key,
    this.selectedIndex,
    this.onDestinationSelected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60.0);

  @override
  ConsumerState<DesktopNavBar> createState() => _DesktopNavBarState();
}

class _DesktopNavBarState extends ConsumerState<DesktopNavBar> {
  NavigatorState? _rootNavigator;

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

  void _showGlobalSearchPalette(BuildContext context, WidgetRef ref) {
    SafeHaptics.selectionClick();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogCtx) => _GlobalSearchDialog(
        onDestinationSelected: widget.onDestinationSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.selectedIndex ?? ref.watch(navigationIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(context);

    final liveProfileAsync = ref.watch(liveUserProfileProvider);
    final fallbackProfile = ref.watch(userProfileProvider);
    final profile = liveProfileAsync.value ?? fallbackProfile;
    final String displayName = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.fullName.isNotEmpty ? profile.fullName.split(' ').first : 'Student');
    final photoUrl = profile.photoUrl.isNotEmpty ? profile.photoUrl : profile.profileImageUrl;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompactDesktop = screenWidth <= 1200;

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
        height: 60.0,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            bottom: BorderSide(
              color: colors.surfaceBorder,
              width: 1.0,
            ),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: isCompactDesktop ? 12.0 : 20.0),
        child: Row(
          children: [
            // Left: Chondrobindu logo mark + "চন্দ্রবিন্দু • CHONDROBINDU"
            _buildBrand(isCompactDesktop, colors),

            const SizedBox(width: 12.0),

            // Center: 6 Navigation Pills
            // [ Home | Courses | Timer | Planner | Journal | Insights ]
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Container(
                    padding: const EdgeInsets.all(3.0),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(color: colors.surfaceBorder, width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NavTabPill(
                          label: 'Home',
                          isSelected: activeIndex == 0,
                          colors: colors,
                          isDark: isDark,
                          onTap: () => _selectTab(0),
                        ),
                        _NavTabPill(
                          label: 'Courses',
                          isSelected: activeIndex == 1,
                          colors: colors,
                          isDark: isDark,
                          onTap: () => _selectTab(1),
                        ),
                        _NavTabPill(
                          label: 'Timer',
                          isSelected: activeIndex == 2,
                          colors: colors,
                          isDark: isDark,
                          onTap: () => _selectTab(2),
                        ),
                        _NavTabPill(
                          label: 'Planner',
                          isSelected: activeIndex == 3,
                          colors: colors,
                          isDark: isDark,
                          onTap: () => _selectTab(3),
                        ),
                        _NavTabPill(
                          label: 'Journal',
                          isSelected: activeIndex == 4,
                          colors: colors,
                          isDark: isDark,
                          onTap: () => _selectTab(4),
                        ),
                        _NavTabPill(
                          label: 'Insights',
                          isSelected: activeIndex == 5,
                          colors: colors,
                          isDark: isDark,
                          onTap: () => _selectTab(5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12.0),

            // Right: 260px search bar (⌘K), Theme toggle pill, Notification bell, Profile avatar
            _buildRightActions(context, ref, profile, displayName, photoUrl, colors, isDark, isCompactDesktop),
          ],
        ),
      ),
    );
  }

  void _selectTab(int index) {
    SafeHaptics.selectionClick();
    widget.onDestinationSelected?.call(index);
    ref.read(navigationIndexProvider.notifier).state = index;
  }

  Widget _buildBrand(bool isCompact, ChondrobinduThemeColors colors) {
    return InkWell(
      onTap: () => _selectTab(0),
      borderRadius: BorderRadius.circular(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(
              size: 32,
              showContainer: false,
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'চন্দ্রবিন্দু',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.primary,
                    fontSize: isCompact ? 15.0 : 16.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5.0),
                  child: Text(
                    '•',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 12.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'CHONDROBINDU',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.primary,
                    fontSize: isCompact ? 11.5 : 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightActions(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
    String name,
    String? imageUrl,
    ChondrobinduThemeColors colors,
    bool isDark,
    bool isCompactDesktop,
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
        // 1. 260px Command Search Bar (`⌘K`)
        if (!isCompactDesktop)
          InkWell(
            onTap: () => _showGlobalSearchPalette(context, ref),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 36,
              width: 260.0,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.surfaceBorder, width: 1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: colors.textMuted,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Search anything...',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.surfaceBorder, width: 0.8),
                    ),
                    child: Text(
                      '⌘K',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          IconButton(
            tooltip: 'Search (⌘K)',
            icon: Icon(Icons.search_rounded, color: colors.textMuted, size: 20),
            onPressed: () => _showGlobalSearchPalette(context, ref),
          ),

        SizedBox(width: isCompactDesktop ? 6.0 : 10.0),

        // 2. Working Theme Toggle Pill (Lime / Indigo)
        _buildThemeTogglePill(ref, colors, isDark),

        SizedBox(width: isCompactDesktop ? 6.0 : 10.0),

        // 3. Notification Bell with Badge
        _buildNotificationBell(context, ref, upcomingAlerts, now, colors, isDark),

        SizedBox(width: isCompactDesktop ? 6.0 : 10.0),

        // 4. Profile Avatar / Dropdown Pill
        _buildProfileDropdown(context, profile, name, imageUrl, colors, isDark, isCompactDesktop),
      ],
    );
  }

  Widget _buildThemeTogglePill(WidgetRef ref, ChondrobinduThemeColors colors, bool isDark) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder, width: 1),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Light Mode Button
          InkWell(
            onTap: () {
              SafeHaptics.selectionClick();
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: !isDark ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: !isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        )
                      ]
                    : null,
              ),
              child: Icon(
                Icons.light_mode_outlined,
                size: 15,
                color: !isDark ? colors.primary : colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Dark Mode Button
          InkWell(
            onTap: () {
              SafeHaptics.selectionClick();
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDark ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        )
                      ]
                    : null,
              ),
              child: Icon(
                Icons.dark_mode_outlined,
                size: 15,
                color: isDark ? colors.primary : colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBell(
    BuildContext context,
    WidgetRef ref,
    List<Assessment> upcomingAlerts,
    DateTime now,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    return PopupMenuButton<void>(
      tooltip: 'Notifications & Alerts',
      offset: const Offset(0, 44),
      color: colors.surface,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.surfaceBorder, width: 1),
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
                    Icon(Icons.check_circle_outline_rounded, color: colors.success, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      'All caught up! No upcoming exam or routine alerts.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
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
                  color: colors.secondary,
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
              onTap: () => _selectTab(3), // Jump to Planner
              child: SizedBox(
                width: 280,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Text(
                        a.courseCode,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.primary,
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
                              color: colors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            dueStr,
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.secondary,
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
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceBorder, width: 1),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: colors.textMuted,
              size: 19,
            ),
          ),
          if (upcomingAlerts.isNotEmpty)
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileDropdown(
    BuildContext context,
    UserProfile profile,
    String name,
    String? imageUrl,
    ChondrobinduThemeColors colors,
    bool isDark,
    bool isCompactDesktop,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'User Profile & Settings',
      offset: const Offset(0, 44),
      color: colors.surface,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.surfaceBorder, width: 1),
      ),
      onSelected: (value) async {
        if (value == 'settings') {
          SafeHaptics.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
        } else if (value == 'journal') {
          SafeHaptics.selectionClick();
          _selectTab(4);
        } else if (value == 'help') {
          SafeHaptics.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()));
        } else if (value == 'about') {
          SafeHaptics.selectionClick();
          if (context.mounted) {
            showAboutDialog(
              context: context,
              applicationName: 'Chondrobindu',
              applicationVersion: '1.0.0',
              applicationLegalese: '© 2026 Chondrobindu.\nDeveloped by Shahriyer Sayem (Utso).',
              children: [
                const SizedBox(height: 12),
                Text(
                  'Chondrobindu is an all-in-one academic planner, syllabus manager, and focus companion crafted for university and college students.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: colors.textMuted),
                ),
              ],
            );
          }
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
        // Header: Profile info
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary.withValues(alpha: 0.15),
                      border: Border.all(color: colors.primary.withValues(alpha: 0.4), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (profile.displayName.isNotEmpty ? profile.displayName : name).characters.first.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName.isNotEmpty ? profile.displayName : name,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile.email.isNotEmpty ? profile.email : 'student@chondrobindu.edu',
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(color: colors.surfaceBorder, height: 1),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, color: colors.textMuted, size: 18),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'journal',
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: colors.textMuted, size: 18),
              const SizedBox(width: 10),
              Text(
                'Academic Journal',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'help',
          child: Row(
            children: [
              Icon(Icons.help_outline_rounded, color: colors.textMuted, size: 18),
              const SizedBox(width: 10),
              Text(
                'Help & Support',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'about',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: colors.textMuted, size: 18),
              const SizedBox(width: 10),
              Text(
                'About Developer',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
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
        padding: EdgeInsets.symmetric(horizontal: isCompactDesktop ? 6.0 : 8.0, vertical: 3.5),
        decoration: BoxDecoration(
          color: colors.recessed,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.surfaceBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: colors.surfaceBorder,
              backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                  ? NetworkImage(imageUrl)
                  : null,
              child: (imageUrl == null || imageUrl.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    )
                  : null,
            ),
            SizedBox(width: isCompactDesktop ? 5 : 7),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isCompactDesktop ? 70 : 120),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: isCompactDesktop ? 12.0 : 13.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigation Pill Widget for Desktop Top Bar.
/// Uses Primary Accent (#2F4A6D Light / #8FA8C8 Dark) for active tab with contrasting text,
/// and Muted Text (#5A6578 Light / #94A3B8 Dark) for inactive tabs with hover state.
class _NavTabPill extends StatefulWidget {
  final String label;
  final bool isSelected;
  final ChondrobinduThemeColors colors;
  final bool isDark;
  final VoidCallback onTap;

  const _NavTabPill({
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_NavTabPill> createState() => _NavTabPillState();
}

class _NavTabPillState extends State<_NavTabPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected;
    final colors = widget.colors;

    // Active tab uses primary accent background with contrasting text:
    // Light: #2F4A6D bg with White text
    // Dark: #8FA8C8 bg with #171C24 dark text
    final Color activeBg = colors.primary;
    final Color activeText = widget.isDark ? const Color(0xFF171C24) : Colors.white;

    final Color inactiveText = _isHovered ? colors.textPrimary : colors.textMuted;
    final Color inactiveBg = _isHovered ? colors.surface.withValues(alpha: 0.7) : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: active ? activeBg : inactiveBg,
            borderRadius: BorderRadius.circular(18.0),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.plusJakartaSans(
              color: active ? activeText : inactiveText,
              fontSize: 13.0,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: 0.1,
            ),
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
    final colors = AppColors.of(context);
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
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.surfaceBorder, width: 1),
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
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.surfaceBorder, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: colors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search courses, topics, assessments...',
                          hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 14),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                        ),
                        onChanged: (val) => setState(() => _query = val),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Text(
                        'ESC',
                        style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10),
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
                              Icon(Icons.travel_explore_rounded, color: colors.textMuted.withValues(alpha: 0.5), size: 40),
                              const SizedBox(height: 10),
                              Text(
                                'Type a course code (e.g. EEE 2105) or assessment name...',
                                style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
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
                                style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
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
                                      color: colors.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                ...matchedCourses.map((c) => ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  leading: Icon(Icons.school_outlined, color: colors.primary, size: 20),
                                  title: Text(
                                    '${c.code} • ${c.title}',
                                    style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '${c.credits} Credits • ${c.courseType.displayName}',
                                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
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
                                      color: colors.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                ...matchedAssessments.map((a) => ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  leading: Icon(Icons.assignment_outlined, color: colors.success, size: 20),
                                  title: Text(
                                    '${a.courseCode} — ${a.name}',
                                    style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    a.date != null ? 'Date: ${a.date!.day}/${a.date!.month}/${a.date!.year}' : 'Unscheduled',
                                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
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
