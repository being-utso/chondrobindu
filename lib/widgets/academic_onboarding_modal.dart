import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_profile.dart';
import '../providers/firestore_providers.dart';
import '../utils/safe_haptics.dart';

class AcademicOnboardingModal extends ConsumerStatefulWidget {
  final String uid;

  const AcademicOnboardingModal({super.key, required this.uid});

  static Future<void> showIfNeeded(BuildContext context, WidgetRef ref, UserProfile profile) async {
    // If institutionType is already set and user has courses, no need
    if (profile.uid.isEmpty || profile.isOnboarded) return;
    final hasData = await ref.read(dataSeedServiceProvider).hasUserData(profile.uid);
    if (!hasData && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AcademicOnboardingModal(uid: profile.uid),
      );
    }
  }

  @override
  ConsumerState<AcademicOnboardingModal> createState() => _AcademicOnboardingModalState();
}

class _AcademicOnboardingModalState extends ConsumerState<AcademicOnboardingModal> {
  InstitutionType? _selectedTrack;
  bool _isLoading = false;

  Future<void> _handleConfirm() async {
    if (_selectedTrack == null || _isLoading) return;
    setState(() => _isLoading = true);
    SafeHaptics.mediumImpact();

    try {
      await ref.read(dataSeedServiceProvider).seedInitialTrackData(widget.uid, _selectedTrack!);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set up academic track: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1816),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF2E2623), width: 1.5),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E2623),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFFF2B78A), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Academic Track',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFEDE8E3),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Chondrobindu customizes your curriculum & grading.',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF9E8C82),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Track Option 1: University
            _buildTrackCard(
              track: InstitutionType.university,
              title: 'University / Engineering',
              subtitle: '4.00 CGPA scale • Level/Term • Course Codes • CTs & Term Finals',
              icon: Icons.account_balance_rounded,
            ),

            const SizedBox(height: 14),

            // Track Option 2: College
            _buildTrackCard(
              track: InstitutionType.college,
              title: 'College / Higher Secondary',
              subtitle: '5.00 GPA scale • Class 11/12 • Science/Commerce • Pre-Test & Board',
              icon: Icons.menu_book_rounded,
            ),

            const SizedBox(height: 28),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedTrack != null ? const Color(0xFFF2B78A) : const Color(0xFF382A24),
                  foregroundColor: const Color(0xFF151211),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: (_selectedTrack != null && !_isLoading) ? _handleConfirm : null,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF151211)),
                      )
                    : Text(
                        'Get Started →',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackCard({
    required InstitutionType track,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedTrack == track;

    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() => _selectedTrack = track);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E2623) : const Color(0xFF151211),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF2E2623),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? const Color(0xFFEDE8E3) : const Color(0xFFABA093),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF9E8C82),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFFF2B78A), size: 20),
          ],
        ),
      ),
    );
  }
}
