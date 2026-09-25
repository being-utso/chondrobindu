import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/firestore_providers.dart';
import '../providers/nav_provider.dart';
import '../providers/user_profile_provider.dart';
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

    return Container(
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
          _buildRightActions(context, displayName, photoUrl),
        ],
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

  Widget _buildRightActions(BuildContext context, String name, String? imageUrl) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick Command / Search Bar Pill
        Container(
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

        const SizedBox(width: 14),

        // Notification Bell Ghost Button
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: Color(0xFFABA093),
                size: 21,
              ),
              splashRadius: 20,
              onPressed: () {
                SafeHaptics.selectionClick();
              },
            ),
            Positioned(
              top: 10,
              right: 12,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2B78A),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF140F0E), width: 1),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(width: 8),

        // Profile Chip
        InkWell(
          onTap: () {
            SafeHaptics.selectionClick();
          },
          borderRadius: BorderRadius.circular(20),
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
