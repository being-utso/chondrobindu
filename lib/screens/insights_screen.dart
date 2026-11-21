import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart' show isSameDay;

import '../models/routine_models.dart' show HolidaySettings, AttendanceRecord, AttendanceStatus;
import '../models/study_session_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/journal_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../services/timer_service.dart' show deduplicateSessions;
import '../theme/app_theme.dart';
import '../utils/safe_haptics.dart';
import '../widgets/cgpa_forecaster_workspace.dart';
import 'journal_screen.dart' show holidaySettingsStreamProvider;

/// Period selector for analytics and study sessions
enum InsightPeriod { day, week, month, trend }

/// Data bucket for timespan-driven Focus Distribution charts
class FocusBucket {
  final String label;
  final String fullLabel;
  final double hours;
  final int seconds;
  final bool isCurrent;

  const FocusBucket({
    required this.label,
    required this.fullLabel,
    required this.hours,
    required this.seconds,
    this.isCurrent = false,
  });
}

/// Dynamic Y-axis scale calculation for Focus Distribution charts
class FocusChartScale {
  final double maxY;
  final List<double> ticks;

  const FocusChartScale({required this.maxY, required this.ticks});

  static FocusChartScale compute(double peakHours, double goalHours) {
    final rawMax = math.max(peakHours, goalHours);
    if (rawMax <= 0.0) {
      return const FocusChartScale(maxY: 3.0, ticks: [0.0, 1.0, 2.0, 3.0]);
    }
    if (rawMax <= 3.0) {
      return const FocusChartScale(maxY: 3.0, ticks: [0.0, 1.0, 2.0, 3.0]);
    }
    if (rawMax <= 6.0) {
      return const FocusChartScale(maxY: 6.0, ticks: [0.0, 2.0, 4.0, 6.0]);
    }
    if (rawMax <= 8.0) {
      return const FocusChartScale(maxY: 8.0, ticks: [0.0, 2.0, 4.0, 6.0, 8.0]);
    }
    if (rawMax <= 12.0) {
      return const FocusChartScale(maxY: 12.0, ticks: [0.0, 3.0, 6.0, 9.0, 12.0]);
    }
    if (rawMax <= 16.0) {
      return const FocusChartScale(maxY: 16.0, ticks: [0.0, 4.0, 8.0, 12.0, 16.0]);
    }
    final step = (rawMax / 4.0).ceilToDouble();
    final top = step * 4.0;
    return FocusChartScale(
      maxY: top,
      ticks: [0.0, step, step * 2, step * 3, top],
    );
  }
}

/// Computes track-aware date range minimum boundary (minDate).
DateTime computeMinDate({
  required bool isUniversity,
  DateTime? semesterStart,
  DateTime? userCreatedAt,
  DateTime? firebaseCreationTime,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  if (isUniversity && semesterStart != null) {
    final semStart = DateTime(semesterStart.year, semesterStart.month, semesterStart.day);
    if (!semStart.isAfter(today)) {
      return semStart;
    }
  }

  DateTime? creation = userCreatedAt;
  if (creation == null || creation.year < 2000) {
    creation = firebaseCreationTime;
  }

  if (creation != null) {
    final creationDate = DateTime(creation.year, creation.month, creation.day);
    if (!creationDate.isAfter(today)) {
      return creationDate;
    }
  }

  return today.subtract(const Duration(days: 90));
}

/// Safe division and ratio calculation helper guarding strictly against NaN,
/// division by zero, and infinite values.
double safeRatio(num numerator, num denominator) {
  if (denominator <= 0 || numerator.isNaN || denominator.isNaN) return 0.0;
  final val = numerator / denominator;
  if (val.isNaN || val.isInfinite) return 0.0;
  return val.clamp(0.0, 1.0);
}

/// Academic Insights & Telemetry Screen
/// 1:1 Parity with Stitch Academic OS Design System
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

/// Typedef alias for compatibility across router and widget test harnesses
typedef AcademicInsightsScreen = InsightsScreen;

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  String _desktopCategoryTab = 'Overview';
  InsightPeriod _selectedPeriod = InsightPeriod.week;
  DateTime _currentAnchorDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime? _customTrendStart;
  DateTime? _customTrendEnd;

  DateTime get _minDate {
    final profile = ref.watch(liveUserProfileProvider).value ?? ref.watch(userProfileProvider);
    final isUni = profile?.isUniversityStudent == true || profile?.institutionType == InstitutionType.university;
    final holidaySettings = ref.watch(holidaySettingsStreamProvider).valueOrNull;

    DateTime? firebaseCreation;
    try {
      firebaseCreation = FirebaseAuth.instance.currentUser?.metadata.creationTime;
    } catch (_) {
      firebaseCreation = null;
    }

    return computeMinDate(
      isUniversity: isUni,
      semesterStart: holidaySettings?.semesterStart,
      userCreatedAt: profile?.createdAt,
      firebaseCreationTime: firebaseCreation,
    );
  }

  DateTime get _maxDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _canStepBack {
    final minD = _minDate;
    final anchor = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        final prev = DateTime(anchor.year, anchor.month, anchor.day - 1);
        return !prev.isBefore(minD);
      case InsightPeriod.week:
        final daysFromSaturday = (anchor.weekday % 7 + 1) % 7;
        final currentSat = DateTime(anchor.year, anchor.month, anchor.day - daysFromSaturday);
        final prevSat = DateTime(currentSat.year, currentSat.month, currentSat.day - 7);
        final prevFri = DateTime(prevSat.year, prevSat.month, prevSat.day + 6);
        return !prevFri.isBefore(minD);
      case InsightPeriod.month:
        final currentMonthStart = DateTime(anchor.year, anchor.month, 1);
        final minMonthStart = DateTime(minD.year, minD.month, 1);
        return currentMonthStart.isAfter(minMonthStart);
      case InsightPeriod.trend:
        return _rangeStart.isAfter(minD);
    }
  }

  bool get _canStepForward {
    final today = _maxDate;
    final anchor = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        final next = DateTime(anchor.year, anchor.month, anchor.day + 1);
        return !next.isAfter(today);
      case InsightPeriod.week:
        final todayDaysFromSat = (today.weekday % 7 + 1) % 7;
        final currentWeekSat = DateTime(today.year, today.month, today.day - todayDaysFromSat);
        final anchorDaysFromSat = (anchor.weekday % 7 + 1) % 7;
        final activeSat = DateTime(anchor.year, anchor.month, anchor.day - anchorDaysFromSat);
        return activeSat.isBefore(currentWeekSat);
      case InsightPeriod.month:
        final activeMonthStart = DateTime(anchor.year, anchor.month, 1);
        final currentMonthStart = DateTime(today.year, today.month, 1);
        return activeMonthStart.isBefore(currentMonthStart);
      case InsightPeriod.trend:
        return _rangeEnd.isBefore(today);
    }
  }

  DateTime get _rangeStart {
    final anchor = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        return anchor.isBefore(_minDate) ? _minDate : anchor;
      case InsightPeriod.week:
        final daysFromSaturday = (anchor.weekday % 7 + 1) % 7;
        final sat = DateTime(anchor.year, anchor.month, anchor.day - daysFromSaturday);
        return sat.isBefore(_minDate) ? _minDate : sat;
      case InsightPeriod.month:
        final mStart = DateTime(anchor.year, anchor.month, 1);
        return mStart.isBefore(_minDate) ? _minDate : mStart;
      case InsightPeriod.trend:
        if (_customTrendStart != null) {
          final s = DateTime(_customTrendStart!.year, _customTrendStart!.month, _customTrendStart!.day);
          return s.isBefore(_minDate) ? _minDate : s;
        }
        final end = anchor;
        final start = DateTime(end.year, end.month, end.day - 29);
        return start.isBefore(_minDate) ? _minDate : start;
    }
  }

  DateTime get _rangeEnd {
    final anchor = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        return DateTime(anchor.year, anchor.month, anchor.day, 23, 59, 59, 999);
      case InsightPeriod.week:
        final daysFromSaturday = (anchor.weekday % 7 + 1) % 7;
        final sat = DateTime(anchor.year, anchor.month, anchor.day - daysFromSaturday);
        final fri = DateTime(sat.year, sat.month, sat.day + 6, 23, 59, 59, 999);
        return fri.isAfter(_maxDate) ? DateTime(_maxDate.year, _maxDate.month, _maxDate.day, 23, 59, 59, 999) : fri;
      case InsightPeriod.month:
        final nextMonthFirst = DateTime(anchor.year, anchor.month + 1, 1);
        final lastDay = nextMonthFirst.subtract(const Duration(milliseconds: 1));
        return lastDay.isAfter(_maxDate) ? DateTime(_maxDate.year, _maxDate.month, _maxDate.day, 23, 59, 59, 999) : lastDay;
      case InsightPeriod.trend:
        if (_customTrendEnd != null) {
          final e = DateTime(_customTrendEnd!.year, _customTrendEnd!.month, _customTrendEnd!.day, 23, 59, 59, 999);
          return e.isAfter(_maxDate) ? DateTime(_maxDate.year, _maxDate.month, _maxDate.day, 23, 59, 59, 999) : e;
        }
        return DateTime(anchor.year, anchor.month, anchor.day, 23, 59, 59, 999);
    }
  }

  String get _dateRangeLabel {
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        return DateFormat('d MMM yyyy').format(_currentAnchorDate);
      case InsightPeriod.week:
        final start = _rangeStart;
        final end = _rangeEnd;
        if (start.month == end.month && start.year == end.year) {
          return '${start.day} – ${end.day} ${DateFormat('MMM yyyy').format(end)}';
        }
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
      case InsightPeriod.month:
        return DateFormat('MMMM yyyy').format(_currentAnchorDate);
      case InsightPeriod.trend:
        final start = _rangeStart;
        final end = _rangeEnd;
        if (start.month == end.month && start.year == end.year) {
          return '${start.day} – ${end.day} ${DateFormat('MMM yyyy').format(end)}';
        }
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
    }
  }

  void _stepDateRange(int direction) {
    if (direction < 0 && !_canStepBack) return;
    if (direction > 0 && !_canStepForward) return;
    SafeHaptics.selectionClick();
    final today = _maxDate;
    final minD = _minDate;
    final anchor = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);

    setState(() {
      switch (_selectedPeriod) {
        case InsightPeriod.day:
          final next = DateTime(anchor.year, anchor.month, anchor.day + direction);
          if (!next.isBefore(minD) && !next.isAfter(today)) {
            _currentAnchorDate = next;
          }
          break;
        case InsightPeriod.week:
          final daysFromSaturday = (anchor.weekday % 7 + 1) % 7;
          final currentSat = DateTime(anchor.year, anchor.month, anchor.day - daysFromSaturday);
          final nextSat = DateTime(currentSat.year, currentSat.month, currentSat.day + 7 * direction);
          if (nextSat.isAfter(today)) {
            _currentAnchorDate = today;
          } else if (nextSat.isBefore(minD)) {
            _currentAnchorDate = minD;
          } else {
            _currentAnchorDate = nextSat;
          }
          break;
        case InsightPeriod.month:
          final nextMonthStart = DateTime(anchor.year, anchor.month + direction, 1);
          final currentMonthStart = DateTime(today.year, today.month, 1);
          final minMonthStart = DateTime(minD.year, minD.month, 1);
          if (!nextMonthStart.isBefore(minMonthStart) && !nextMonthStart.isAfter(currentMonthStart)) {
            _currentAnchorDate = nextMonthStart;
          }
          break;
        case InsightPeriod.trend:
          _customTrendStart = null;
          _customTrendEnd = null;
          final next = DateTime(anchor.year, anchor.month, anchor.day + 30 * direction);
          if (next.isAfter(today)) {
            _currentAnchorDate = today;
          } else if (next.isBefore(minD)) {
            _currentAnchorDate = minD;
          } else {
            _currentAnchorDate = next;
          }
          break;
      }
    });
  }

  String get _quickJumpLabel {
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        return 'Today';
      case InsightPeriod.week:
        return 'This Week';
      case InsightPeriod.month:
        return 'This Month';
      case InsightPeriod.trend:
        return 'Current';
    }
  }

  void _jumpToCurrentRange() {
    SafeHaptics.selectionClick();
    setState(() {
      final now = DateTime.now();
      _currentAnchorDate = DateTime(now.year, now.month, now.day);
      _customTrendStart = null;
      _customTrendEnd = null;
    });
  }

  void _showEditDailyGoalDialog(BuildContext context, ChondrobinduThemeColors colors, double currentGoal) {
    final textController = TextEditingController(text: currentGoal.toStringAsFixed(1));
    double selectedGoal = currentGoal;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final presets = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0];
          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.surfaceBorder),
            ),
            title: Row(
              children: [
                Icon(Icons.flag_rounded, size: 20, color: colors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Daily Focus Goal',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set target study hours per day. Charts, target variance, and progress badges will update dynamically.',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'QUICK PRESETS',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets.map((p) {
                    final active = (selectedGoal - p).abs() < 0.05;
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          selectedGoal = p;
                          textController.text = p.toStringAsFixed(1);
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? colors.secondary.withValues(alpha: 0.2) : colors.recessed,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? colors.secondary : colors.surfaceBorder,
                          ),
                        ),
                        child: Text(
                          '${p.toStringAsFixed(1)}h',
                          style: GoogleFonts.jetBrainsMono(
                            color: active ? colors.secondary : colors.textPrimary,
                            fontSize: 12,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  'CUSTOM TARGET (HOURS)',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: textController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colors.recessed,
                    suffixText: 'hours / day',
                    suffixStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.surfaceBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.secondary, width: 1.5),
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val.trim());
                    if (parsed != null && parsed > 0) {
                      setDialogState(() {
                        selectedGoal = parsed;
                      });
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: const Color(0xFF171C24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  final parsed = double.tryParse(textController.text.trim()) ?? selectedGoal;
                  if (parsed > 0) {
                    Navigator.of(ctx).pop();
                    _updateDailyFocusGoal(parsed);
                  }
                },
                child: Text(
                  'Save Target',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateDailyFocusGoal(double newGoal) async {
    if (newGoal <= 0) return;
    SafeHaptics.selectionClick();
    ref.read(userProfileProvider.notifier).updateDailyFocusGoal(newGoal);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty && Firebase.apps.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'dailyFocusGoalHours': newGoal,
          'targetFocusMinutes': (newGoal * 60).round(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error updating dailyFocusGoalHours: $e');
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Daily focus goal updated to ${newGoal.toStringAsFixed(1)}h/day'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showTrendRangeDialog(BuildContext context, ChondrobinduThemeColors colors, bool isUni) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minD = _minDate;

    DateTime tempStart = _rangeStart.isBefore(minD) ? minD : _rangeStart;
    DateTime tempEnd = _rangeEnd.isAfter(today) ? today : _rangeEnd;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final days = (tempEnd.difference(tempStart).inDays + 1).clamp(1, 1000);

          final presets = [
            ('Last 7 Days', today.subtract(const Duration(days: 6)), today),
            ('Last 14 Days', today.subtract(const Duration(days: 13)), today),
            ('Last 30 Days', today.subtract(const Duration(days: 29)), today),
            (isUni ? 'Since Semester Start' : 'Since Joined', minD, today),
          ];

          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.surfaceBorder),
            ),
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.date_range_rounded, size: 18, color: colors.secondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Telemetry Trend Window',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Select preset or custom date range',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUICK PRESETS',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((p) {
                      final pStart = p.$2.isBefore(minD) ? minD : p.$2;
                      final pEnd = p.$3.isAfter(today) ? today : p.$3;
                      final isSelected = isSameDay(tempStart, pStart) && isSameDay(tempEnd, pEnd);

                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            tempStart = pStart;
                            tempEnd = pEnd;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? colors.secondary.withValues(alpha: 0.2) : colors.recessed,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? colors.secondary : colors.surfaceBorder,
                            ),
                          ),
                          child: Text(
                            p.$1,
                            style: GoogleFonts.jetBrainsMono(
                              color: isSelected ? colors.secondary : colors.textPrimary,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'CUSTOM RANGE',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: tempStart,
                              firstDate: minD,
                              lastDate: tempEnd,
                              builder: (context, child) => Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.dark(
                                    primary: colors.secondary,
                                    surface: colors.surface,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                tempStart = DateTime(picked.year, picked.month, picked.day);
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'START DATE',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: colors.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('d MMM yyyy').format(tempStart),
                                  style: GoogleFonts.jetBrainsMono(
                                    color: colors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.arrow_forward_rounded, size: 16, color: colors.textMuted),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: tempEnd,
                              firstDate: tempStart,
                              lastDate: today,
                              builder: (context, child) => Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.dark(
                                    primary: colors.secondary,
                                    surface: colors.surface,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                tempEnd = DateTime(picked.year, picked.month, picked.day);
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'END DATE',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: colors.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('d MMM yyyy').format(tempEnd),
                                  style: GoogleFonts.jetBrainsMono(
                                    color: colors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Range: $days ${days == 1 ? "day" : "days"} (Bounded: ${DateFormat("d MMM yyyy").format(minD)} – Today)',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: const Color(0xFF171C24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  SafeHaptics.selectionClick();
                  setState(() {
                    _customTrendStart = tempStart;
                    _customTrendEnd = tempEnd;
                    _currentAnchorDate = tempEnd;
                  });
                },
                child: Text(
                  'Apply Window',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PURE DATA AGGREGATION & FORMATTING HELPERS
  // ---------------------------------------------------------------------------

  int _computeTotalFocusSeconds(List<StudySession> sessions) {
    return sessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
  }

  String _formatFocusDuration(int totalSec) {
    if (totalSec <= 0) return '0h 0m';
    final hours = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  int _computeMaxSessionSeconds(List<StudySession> sessions) {
    return sessions.fold<int>(0, (currMax, s) => s.durationSeconds > currMax ? s.durationSeconds : currMax);
  }

  String _computeLongestSessionCourse(List<StudySession> sessions) {
    if (sessions.isEmpty) return 'No sessions';
    StudySession longest = sessions.first;
    for (final s in sessions) {
      if (s.durationSeconds > longest.durationSeconds) {
        longest = s;
      }
    }
    return longest.courseCode.isNotEmpty ? longest.courseCode : (longest.courseTitle ?? 'General Study');
  }

  int _computeAvgDailyFocusSeconds(List<StudySession> sessions, int daysCount) {
    if (sessions.isEmpty || daysCount <= 0) return 0;
    final totalSec = _computeTotalFocusSeconds(sessions);
    return totalSec ~/ daysCount;
  }

  List<FocusBucket> _computeFocusDistributionData(
    List<StudySession> sessions, [
    List<StudySession>? recentSessions,
  ]) {
    final combined = deduplicateSessions([...sessions, ...(recentSessions ?? const [])]);

    switch (_selectedPeriod) {
      case InsightPeriod.day:
        final dayStart = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);
        final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
        final daySessions = combined.where((s) =>
            !s.startedAt.isBefore(dayStart) && !s.startedAt.isAfter(dayEnd)
        ).toList();

        final blockLabels = ['00-04', '04-08', '08-12', '12-16', '16-20', '20-24'];
        final blockFullLabels = [
          '00:00 – 04:00',
          '04:00 – 08:00',
          '08:00 – 12:00',
          '12:00 – 16:00',
          '16:00 – 20:00',
          '20:00 – 24:00',
        ];

        final List<int> blockSecs = List.filled(6, 0);
        for (final s in daySessions) {
          final blockIdx = (s.startedAt.hour ~/ 4).clamp(0, 5);
          blockSecs[blockIdx] += s.durationSeconds;
        }

        final now = DateTime.now();
        final isToday = isSameDay(_currentAnchorDate, now);
        final currentBlockIdx = isToday ? (now.hour ~/ 4).clamp(0, 5) : -1;

        final List<FocusBucket> buckets = [];
        for (int i = 0; i < 6; i++) {
          final double hrs = double.parse((blockSecs[i] / 3600.0).toStringAsFixed(1));
          buckets.add(FocusBucket(
            label: blockLabels[i],
            fullLabel: blockFullLabels[i],
            hours: hrs,
            seconds: blockSecs[i],
            isCurrent: i == currentBlockIdx,
          ));
        }
        return buckets;

      case InsightPeriod.week:
        final dayLabels = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
        final daysFromSaturday = (_currentAnchorDate.weekday % 7 + 1) % 7;
        final weekStart = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day)
            .subtract(Duration(days: daysFromSaturday));

        final List<FocusBucket> buckets = [];
        for (int i = 0; i < 7; i++) {
          final dayDate = weekStart.add(Duration(days: i));
          final daySessions = combined.where((s) => isSameDay(s.startedAt, dayDate));
          final int sec = daySessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
          final double hrs = double.parse((sec / 3600.0).toStringAsFixed(1));
          buckets.add(FocusBucket(
            label: dayLabels[i],
            fullLabel: DateFormat('EEE, d MMM').format(dayDate),
            hours: hrs,
            seconds: sec,
            isCurrent: isSameDay(dayDate, DateTime.now()),
          ));
        }
        return buckets;

      case InsightPeriod.month:
        final year = _currentAnchorDate.year;
        final month = _currentAnchorDate.month;
        final totalDays = DateTime(year, month + 1, 0).day;

        final List<(int, int, String, String)> weekDefs = [
          (1, 7, 'W1', '1–7 ${DateFormat('MMM').format(_currentAnchorDate)}'),
          (8, 14, 'W2', '8–14 ${DateFormat('MMM').format(_currentAnchorDate)}'),
          (15, 21, 'W3', '15–21 ${DateFormat('MMM').format(_currentAnchorDate)}'),
          (22, 28, 'W4', '22–28 ${DateFormat('MMM').format(_currentAnchorDate)}'),
        ];
        if (totalDays > 28) {
          weekDefs.add((29, totalDays, 'W5', '29–$totalDays ${DateFormat('MMM').format(_currentAnchorDate)}'));
        }

        final monthSessions = combined.where((s) =>
            s.startedAt.year == year && s.startedAt.month == month
        ).toList();

        final now = DateTime.now();
        final isCurrentMonth = now.year == year && now.month == month;

        final List<FocusBucket> buckets = [];
        for (final def in weekDefs) {
          final startDay = def.$1;
          final endDay = def.$2;
          final label = def.$3;
          final fullLabel = def.$4;

          final wSessions = monthSessions.where((s) => s.startedAt.day >= startDay && s.startedAt.day <= endDay);
          final int sec = wSessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
          final double hrs = double.parse((sec / 3600.0).toStringAsFixed(1));
          final bool isCurrent = isCurrentMonth && now.day >= startDay && now.day <= endDay;

          buckets.add(FocusBucket(
            label: label,
            fullLabel: fullLabel,
            hours: hrs,
            seconds: sec,
            isCurrent: isCurrent,
          ));
        }
        return buckets;

      case InsightPeriod.trend:
        final start = _rangeStart;
        final end = _rangeEnd;
        final daysCount = (end.difference(start).inDays + 1).clamp(1, 1000);

        if (daysCount <= 14) {
          final List<FocusBucket> buckets = [];
          for (int i = 0; i < daysCount; i++) {
            final dayDate = start.add(Duration(days: i));
            final daySessions = combined.where((s) => isSameDay(s.startedAt, dayDate));
            final int sec = daySessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
            final double hrs = double.parse((sec / 3600.0).toStringAsFixed(1));
            buckets.add(FocusBucket(
              label: DateFormat('d MMM').format(dayDate),
              fullLabel: DateFormat('EEE, d MMM yyyy').format(dayDate),
              hours: hrs,
              seconds: sec,
              isCurrent: isSameDay(dayDate, DateTime.now()),
            ));
          }
          return buckets;
        }

        if (daysCount <= 90) {
          final List<FocusBucket> buckets = [];
          DateTime chunkStart = start;
          int weekIdx = 1;
          final now = DateTime.now();

          while (!chunkStart.isAfter(end)) {
            DateTime chunkEnd = chunkStart.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
            if (chunkEnd.isAfter(end)) chunkEnd = end;

            final wSessions = combined.where((s) =>
                !s.startedAt.isBefore(chunkStart) && !s.startedAt.isAfter(chunkEnd)
            );
            final int sec = wSessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
            final double hrs = double.parse((sec / 3600.0).toStringAsFixed(1));
            final bool isCurrent = !now.isBefore(chunkStart) && !now.isAfter(chunkEnd);

            buckets.add(FocusBucket(
              label: 'W$weekIdx',
              fullLabel: '${DateFormat('d MMM').format(chunkStart)} – ${DateFormat('d MMM').format(chunkEnd)}',
              hours: hrs,
              seconds: sec,
              isCurrent: isCurrent,
            ));

            chunkStart = chunkEnd.add(const Duration(seconds: 1));
            weekIdx++;
          }
          return buckets;
        }

        // > 90 days: monthly buckets
        final List<FocusBucket> buckets = [];
        DateTime m = DateTime(start.year, start.month, 1);
        final DateTime limit = DateTime(end.year, end.month, 1);
        final now = DateTime.now();

        while (!m.isAfter(limit)) {
          final mStart = (m.year == start.year && m.month == start.month) ? start : m;
          DateTime mEnd = DateTime(m.year, m.month + 1, 1).subtract(const Duration(milliseconds: 1));
          if (mEnd.isAfter(end)) mEnd = end;

          final mSessions = combined.where((s) =>
              !s.startedAt.isBefore(mStart) && !s.startedAt.isAfter(mEnd)
          );
          final int sec = mSessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
          final double hrs = double.parse((sec / 3600.0).toStringAsFixed(1));
          final bool isCurrent = now.year == m.year && now.month == m.month;

          buckets.add(FocusBucket(
            label: DateFormat('MMM').format(m),
            fullLabel: DateFormat('MMMM yyyy').format(m),
            hours: hrs,
            seconds: sec,
            isCurrent: isCurrent,
          ));

          m = DateTime(m.year, m.month + 1, 1);
        }
        return buckets;
    }
  }

  List<Map<String, dynamic>> _computeSubjectAllocationData(List<StudySession> sessions, List<dynamic> enrolledCourses) {
    final Map<String, int> subjectSec = {};
    final Map<String, String> subjectTitles = {};

    for (final s in sessions) {
      final code = s.courseCode.isNotEmpty ? s.courseCode : 'General';
      subjectSec[code] = (subjectSec[code] ?? 0) + s.durationSeconds;
      if (s.courseTitle != null && s.courseTitle!.isNotEmpty) {
        subjectTitles[code] = s.courseTitle!;
      }
    }

    for (final c in enrolledCourses) {
      final code = (c.code as String? ?? '').isNotEmpty ? (c.code as String) : (c.title as String? ?? 'Module');
      subjectSec.putIfAbsent(code, () => 0);
      if ((c.title as String? ?? '').isNotEmpty) {
        subjectTitles[code] = c.title as String;
      }
    }

    final totalSec = subjectSec.values.fold<int>(0, (a, b) => a + b);
    final sorted = subjectSec.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    const palette = [
      Color(0xFF8FA8C8), // Indigo
      Color(0xFFC88256), // Rust
      Color(0xFF4E9F72), // Emerald
      Color(0xFFAFC9EA), // Soft Indigo
      Color(0xFFA5673F), // Amber
      Color(0xFF60A5FA), // Blue
    ];

    final List<Map<String, dynamic>> list = [];
    for (int i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      final pct = totalSec > 0 ? (safeRatio(entry.value, totalSec) * 100).round() : 0;
      final color = palette[i % palette.length];
      list.add({
        'code': entry.key,
        'title': subjectTitles[entry.key] ?? 'Module',
        'seconds': entry.value,
        'hoursStr': _formatFocusDuration(entry.value),
        'pct': pct,
        'color': color,
      });
    }

    return list;
  }

  Map<String, dynamic> _computeCircadianData(List<StudySession> sessions, DateTime anchorDate) {
    final daySessions = sessions.where((s) => isSameDay(s.startedAt, anchorDate)).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final hourSeconds = List.filled(24, 0);
    int morningSec = 0;
    int middaySec = 0;
    int nightSec = 0;

    for (final s in daySessions) {
      final h = s.startedAt.hour.clamp(0, 23);
      hourSeconds[h] += s.durationSeconds;
      if (h >= 5 && h < 12) {
        morningSec += s.durationSeconds;
      } else if (h >= 12 && h < 18) {
        middaySec += s.durationSeconds;
      } else {
        nightSec += s.durationSeconds;
      }
    }

    int peakH = -1;
    int maxHSec = 0;
    for (int h = 0; h < 24; h++) {
      if (hourSeconds[h] > maxHSec) {
        maxHSec = hourSeconds[h];
        peakH = h;
      }
    }

    String peakWindowStr = 'None';
    if (peakH != -1 && maxHSec > 0) {
      final startStr = '${peakH.toString().padLeft(2, '0')}:00';
      final endStr = '${((peakH + 2) % 24).toString().padLeft(2, '0')}:00';
      peakWindowStr = '$startStr – $endStr';
    }

    return {
      'daySessions': daySessions,
      'peakWindow': peakWindowStr,
      'morningHours': morningSec / 3600.0,
      'middayHours': middaySec / 3600.0,
      'nightHours': nightSec / 3600.0,
    };
  }

  Map<String, dynamic> _computeRigorMatrixData(List<StudySession> recentSessions, int weeksCount) {
    final now = DateTime.now();
    final daysToFriday = (5 - now.weekday + 7) % 7;
    final currentFriday = DateTime(now.year, now.month, now.day).add(Duration(days: daysToFriday));
    final matrixStart = currentFriday.subtract(Duration(days: weeksCount * 7 - 1));

    int activeDays = 0;
    final List<List<Map<String, dynamic>>> grid = List.generate(7, (_) => []);

    for (int w = 0; w < weeksCount; w++) {
      for (int d = 0; d < 7; d++) {
        final cellDate = matrixStart.add(Duration(days: w * 7 + d));
        final daySessions = recentSessions.where((s) => isSameDay(s.startedAt, cellDate));
        final int sec = daySessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
        final double hrs = sec / 3600.0;
        int intensity = 0;
        if (hrs > 0) {
          activeDays++;
          if (hrs < 1.0) {
            intensity = 1;
          } else if (hrs < 2.5) {
            intensity = 2;
          } else {
            intensity = 3;
          }
        }
        grid[d].add({
          'date': cellDate,
          'hours': hrs,
          'seconds': sec,
          'intensity': intensity,
          'isFuture': cellDate.isAfter(now),
        });
      }
    }

    return {
      'grid': grid,
      'activeDays': activeDays,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopWide = MediaQuery.of(context).size.width >= 800;
    if (isDesktopWide) {
      return _buildDesktopInsightsScreen(context);
    }
    return _buildMobileInsightsScreen(context);
  }

  // ---------------------------------------------------------------------------
  // DESKTOP-NATIVE ACADEMIC INSIGHTS SUITE
  // ---------------------------------------------------------------------------

  Widget _buildDesktopInsightsScreen(BuildContext context) {
    final colors = AppColors.of(context);
    final sessionsAsync = ref.watch(studySessionsRangeStreamProvider(DateRangeParam(_rangeStart, _rangeEnd)));
    final sessions = deduplicateSessions(sessionsAsync.value ?? []);
    final recentSessionsAsync = ref.watch(recentStudySessionsStreamProvider);
    final recentSessions = deduplicateSessions(recentSessionsAsync.value ?? []);
    final profile = ref.watch(liveUserProfileProvider).value ?? ref.watch(userProfileProvider);
    final isUni = profile?.isUniversityStudent == true || profile?.institutionType == InstitutionType.university;
    final effectiveCategoryTab = (isUni && _desktopCategoryTab == 'Performance') ? 'Overview' : _desktopCategoryTab;

    final coursesAsync = ref.watch(coursesStreamProvider);
    final enrolledCourses = coursesAsync.value ?? [];
    final attendanceAsync = ref.watch(attendanceRecordsStreamProvider);
    final attendanceRecords = attendanceAsync.value ?? [];
    final holidaySettings = ref.watch(holidaySettingsStreamProvider).valueOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Context Status Pill & Sync Indicator
                _buildDesktopStatusHeader(colors, profile, isUni, holidaySettings),

                const SizedBox(height: 16),

                // 2. Sub-Navigation Tabs & Granularity Filter Ribbon
                _buildDesktopAnalyticsSubNav(colors, isUni),

                const SizedBox(height: 20),

                if (effectiveCategoryTab == 'Time') ...[
                  _buildDesktopTopKpis(colors, sessions, profile, recentSessions),
                  const SizedBox(height: 20),
                  _buildDesktopCircadianRhythmCard(colors, sessions),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1024) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopWeeklyHistogram(colors, sessions, profile, recentSessions),
                            const SizedBox(height: 20),
                            _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 55,
                            child: _buildDesktopWeeklyHistogram(colors, sessions, profile, recentSessions),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 45,
                            child: _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ] else if (effectiveCategoryTab == 'Subjects') ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1024) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                            const SizedBox(height: 20),
                            _buildDesktopSubjectDeepDive(colors, sessions, enrolledCourses, isUni),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 45,
                            child: _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 55,
                            child: _buildDesktopSubjectDeepDive(colors, sessions, enrolledCourses, isUni),
                          ),
                        ],
                      );
                    },
                  ),
                ] else if (effectiveCategoryTab == 'Performance') ...[
                  _buildExamPerformanceDeltas(ref, colors.surface, colors.secondary),
                  const SizedBox(height: 20),
                  _buildDesktopPerformanceLedger(colors),
                ] else if (effectiveCategoryTab == 'CGPA Forecaster') ...[
                  _buildDesktopCgpaForecasterWorkspace(colors, isDesktop: true),
                ] else ...[
                  // Default 'Overview'
                  _buildDesktopTopKpis(colors, sessions, profile, recentSessions),

                  const SizedBox(height: 20),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrowDesktop = constraints.maxWidth < 1024;
                      if (isNarrowDesktop) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopWeeklyHistogram(colors, sessions, profile, recentSessions),
                            const SizedBox(height: 20),
                            _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                            const SizedBox(height: 20),
                            _buildDesktopCircadianRhythmCard(colors, sessions),
                            const SizedBox(height: 20),
                            _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Middle Charts Row (flex 55 Weekly / flex 45 Subject Donut)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 55,
                                child: _buildDesktopWeeklyHistogram(colors, sessions, profile, recentSessions),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 45,
                                child: _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Bottom Timeline & Heatmap Row (flex 1 Circadian / flex 1 Rigor Matrix)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _buildDesktopCircadianRhythmCard(colors, sessions),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 1,
                                child: _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],

                const SizedBox(height: 20),

                // Contextual Architectural Scholar Stamp
                _buildScholarOperationalStamp(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopStatusHeader(
    ChondrobinduThemeColors colors,
    dynamic profile,
    bool isUni,
    HolidaySettings? holidaySettings,
  ) {
    String trackStr = 'UNIVERSITY TRACK';
    String termStr = profile?.term?.isNotEmpty == true ? 'TERM ${profile.term}' : 'TERM 24.2';
    String? weekStr;

    if (isUni) {
      if (holidaySettings?.semesterStart != null) {
        final start = holidaySettings!.semesterStart!;
        final diffDays = _currentAnchorDate.difference(DateTime(start.year, start.month, start.day)).inDays;
        if (diffDays >= 0) {
          final weekNum = (diffDays ~/ 7) + 1;
          weekStr = 'WEEK ${weekNum.toString().padLeft(2, '0')} METRICS';
        }
      }
    } else {
      if (profile?.institutionType == InstitutionType.college || profile?.isCollegeStudent == true) {
        trackStr = 'COLLEGE TRACK';
        termStr = 'HSC 2026';
      } else {
        trackStr = 'ADMISSION TRACK';
        termStr = 'ENGINEERING TARGET';
      }
    }

    final String pillText = weekStr != null
        ? '$trackStr • $termStr • $weekStr'
        : (isUni ? '$trackStr • $termStr • METRICS' : '$trackStr • $termStr');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 850;
        final leftPill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  pillText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        );

        final rightSync = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'DATA REFLECTED: ${DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase()} • SYNCHRONIZED',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftPill,
              const SizedBox(height: 8),
              rightSync,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: leftPill)),
            const SizedBox(width: 16),
            Flexible(child: rightSync),
          ],
        );
      },
    );
  }

  Widget _buildDesktopAnalyticsSubNav(ChondrobinduThemeColors colors, bool isUni) {
    final categories = isUni
        ? ['Overview', 'Time', 'Subjects', 'CGPA Forecaster']
        : ['Overview', 'Time', 'Subjects', 'Performance'];
    final periods = [
      (InsightPeriod.day, 'Day'),
      (InsightPeriod.week, 'Week'),
      (InsightPeriod.month, 'Month'),
      (InsightPeriod.trend, 'Trend'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1260;

        final subTabsWidget = Container(
          height: 38,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: categories.map((cat) {
              final active = _desktopCategoryTab == cat;
              return InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  setState(() => _desktopCategoryTab = cat);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: active ? Border.all(color: colors.primary.withValues(alpha: 0.5)) : null,
                  ),
                  child: Text(
                    cat,
                    style: GoogleFonts.plusJakartaSans(
                      color: active ? colors.textPrimary : colors.textMuted,
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );

        final periodControls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Granularity Segmented Pill
            Container(
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: periods.map((p) {
                  final active = _selectedPeriod == p.$1;
                  return InkWell(
                    onTap: () {
                      SafeHaptics.selectionClick();
                      setState(() => _selectedPeriod = p.$1);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? colors.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: active ? Border.all(color: colors.surfaceBorder) : null,
                      ),
                      child: Text(
                        p.$2,
                        style: GoogleFonts.plusJakartaSans(
                          color: active ? colors.primary : colors.textMuted,
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(width: 8),

            // Date Stepper Pill (< Date Range >)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _canStepBack ? () => _stepDateRange(-1) : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _canStepBack ? colors.surface.withValues(alpha: 0.5) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 18,
                        color: _canStepBack ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _selectedPeriod == InsightPeriod.trend
                        ? () => _showTrendRangeDialog(context, colors, isUni)
                        : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _dateRangeLabel,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (_selectedPeriod == InsightPeriod.trend) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.tune_rounded, size: 12, color: colors.secondary),
                          ],
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _canStepForward ? () => _stepDateRange(1) : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _canStepForward ? colors.surface.withValues(alpha: 0.5) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: _canStepForward ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Quick-Jump Button
            InkWell(
              onTap: _jumpToCurrentRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restore_rounded, size: 13, color: colors.secondary),
                    const SizedBox(width: 5),
                    Text(
                      _quickJumpLabel,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: subTabsWidget,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: periodControls,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            subTabsWidget,
            const SizedBox(width: 12),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: periodControls,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDesktopTopKpis(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    dynamic profile,
    List<StudySession> recentSessions,
  ) {
    final int totalSec = _computeTotalFocusSeconds(sessions);
    final String focusTimeStr = _formatFocusDuration(totalSec);

    final String sessionCountStr = '${sessions.length}';
    final int daysCount = (_rangeEnd.difference(_rangeStart).inDays + 1).clamp(1, 365);
    final double avgSessionsPerDay = sessions.length / daysCount;
    final String sessionSubtitle = sessions.isNotEmpty
        ? 'Avg ${avgSessionsPerDay.toStringAsFixed(1)} sessions/day'
        : '0 sessions/day';

    final int maxSec = _computeMaxSessionSeconds(sessions);
    final String maxSessionStr = maxSec > 0
        ? (maxSec >= 3600 ? '${maxSec ~/ 3600}h ${(maxSec % 3600) ~/ 60}m' : '${maxSec ~/ 60}m')
        : '0m';
    final String longestCourse = _computeLongestSessionCourse(sessions);

    final int avgDailySec = _computeAvgDailyFocusSeconds(sessions, daysCount);
    final String avgDailyStr = avgDailySec > 0
        ? (avgDailySec >= 3600 ? '${avgDailySec ~/ 3600}h ${(avgDailySec % 3600) ~/ 60}m' : '${avgDailySec ~/ 60}m')
        : '0m';
    final double dailyGoalHours = (profile?.dailyFocusGoalHours != null && profile!.dailyFocusGoalHours > 0)
        ? profile.dailyFocusGoalHours
        : 1.0;
    final double targetRatio = safeRatio(avgDailySec, dailyGoalHours * 3600.0);
    final int targetPct = (targetRatio * 100).round();

    final int streakDays = profile?.streakDays ?? 0;
    final String streakSubtitle = '$streakDays-day streak active';

    // Dynamic calculation of delta vs previous period from real Firestore recentSessions
    final prevPeriodStart = _rangeStart.subtract(Duration(days: daysCount));
    final prevPeriodEnd = _rangeStart.subtract(const Duration(milliseconds: 1));
    final prevSessions = recentSessions.where((s) =>
        s.startedAt.isAfter(prevPeriodStart) && s.startedAt.isBefore(prevPeriodEnd));
    final int prevSec = prevSessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
    final double diffHours = (totalSec - prevSec) / 3600.0;
    final String deltaStr = sessions.isNotEmpty || prevSec > 0
        ? '${diffHours >= 0 ? '+' : ''}${diffHours.toStringAsFixed(1)}h vs last week'
        : '0.0h vs last week';

    final kpi1 = _kpiCard(
      colors: colors,
      title: 'TOTAL FOCUS TIME',
      value: focusTimeStr,
      subtitle: streakSubtitle,
      deltaWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            diffHours >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: diffHours >= 0 ? colors.success : colors.secondary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              deltaStr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                color: diffHours >= 0 ? colors.success : colors.secondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      icon: Icons.local_fire_department_rounded,
      iconColor: colors.secondary,
      iconBg: colors.secondary.withValues(alpha: 0.15),
    );

    final kpi2 = _kpiCard(
      colors: colors,
      title: 'SESSIONS RECORDED',
      value: sessionCountStr,
      subtitle: sessionSubtitle,
      deltaWidget: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.success.withValues(alpha: 0.3)),
        ),
        child: Text(
          sessions.isNotEmpty
              ? (sessions.length >= daysCount ? '▲ High consistency' : '● Consistency: Logged')
              : 'Consistency: Pending',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.jetBrainsMono(
            color: colors.success,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      icon: Icons.adjust_rounded,
      iconColor: colors.success,
      iconBg: colors.success.withValues(alpha: 0.15),
    );

    final kpi3 = _kpiCard(
      colors: colors,
      title: 'MAX SINGLE SESSION',
      value: maxSessionStr,
      subtitle: 'Longest flow state',
      deltaWidget: Text(
        longestCourse.isNotEmpty ? longestCourse : 'No flow recorded',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.jetBrainsMono(
          color: colors.primary,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icons.bolt_rounded,
      iconColor: colors.primary,
      iconBg: colors.primary.withValues(alpha: 0.15),
    );

    final kpi4 = _kpiCard(
      colors: colors,
      title: 'AVG DAILY FOCUS',
      value: avgDailyStr,
      subtitle: '$targetPct% of ${dailyGoalHours.toStringAsFixed(1)}h daily target ✎',
      progressFactor: targetRatio,
      icon: Icons.schedule_rounded,
      iconColor: colors.primary,
      iconBg: colors.recessed,
      onTap: () => _showEditDailyGoalDialog(context, colors, dailyGoalHours),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 960;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: kpi1),
                  const SizedBox(width: 16),
                  Expanded(child: kpi2),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: kpi3),
                  const SizedBox(width: 16),
                  Expanded(child: kpi4),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: kpi1),
            const SizedBox(width: 16),
            Expanded(child: kpi2),
            const SizedBox(width: 16),
            Expanded(child: kpi3),
            const SizedBox(width: 16),
            Expanded(child: kpi4),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required ChondrobinduThemeColors colors,
    required String title,
    required String value,
    required String subtitle,
    Widget? deltaWidget,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    double? progressFactor,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      height: 132,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
            ],
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              color: colors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: colors.textMuted,
              fontSize: 11,
            ),
          ),
          if (progressFactor != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progressFactor.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: colors.recessed,
                valueColor: AlwaysStoppedAnimation<Color>(colors.secondary),
              ),
            )
          else if (deltaWidget != null)
            deltaWidget
          else
            const SizedBox(height: 5),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: cardContent,
      );
    }
    return cardContent;
  }

  Widget _buildDesktopWeeklyHistogram(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    dynamic profile, [
    List<StudySession>? recentSessions,
  ]) {
    final buckets = _computeFocusDistributionData(sessions, recentSessions);
    double peakVal = 0.0;
    String peakDay = 'None';
    for (final b in buckets) {
      final hrs = b.hours;
      if (!hrs.isNaN && hrs > peakVal) {
        peakVal = hrs;
        peakDay = b.label;
      }
    }

    final double dailyGoalHours = (profile?.dailyFocusGoalHours != null && profile!.dailyFocusGoalHours > 0)
        ? profile.dailyFocusGoalHours
        : 1.0;

    double? chartGoalLine;
    String goalLineLabel = '';

    // Period-specific total and target math
    final int totalLoggedSeconds = sessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
    final double totalPeriodHours = totalLoggedSeconds / 3600.0;
    double targetPeriodHours;
    String periodFooterLabel;

    switch (_selectedPeriod) {
      case InsightPeriod.day:
        chartGoalLine = null; // Intra-day 4-hour blocks do not render daily goal line
        targetPeriodHours = dailyGoalHours;
        final pct = targetPeriodHours > 0 ? (safeRatio(totalPeriodHours, targetPeriodHours) * 100).round() : 0;
        periodFooterLabel = 'Total Day: ${totalPeriodHours.toStringAsFixed(1)}h / ${targetPeriodHours.toStringAsFixed(1)}h ($pct%)';
        break;
      case InsightPeriod.week:
        chartGoalLine = dailyGoalHours;
        goalLineLabel = 'GOAL TARGET (${dailyGoalHours.toStringAsFixed(1)}h/day)';
        targetPeriodHours = dailyGoalHours * 7.0;
        final pct = targetPeriodHours > 0 ? (safeRatio(totalPeriodHours, targetPeriodHours) * 100).round() : 0;
        periodFooterLabel = 'Total Week: ${totalPeriodHours.toStringAsFixed(1)}h / ${targetPeriodHours.toStringAsFixed(1)}h ($pct%)';
        break;
      case InsightPeriod.month:
        chartGoalLine = dailyGoalHours * 7.0;
        goalLineLabel = 'GOAL TARGET (${chartGoalLine.toStringAsFixed(1)}h/wk)';
        final daysInMonth = DateTime(_currentAnchorDate.year, _currentAnchorDate.month + 1, 0).day;
        targetPeriodHours = dailyGoalHours * daysInMonth.toDouble();
        final pct = targetPeriodHours > 0 ? (safeRatio(totalPeriodHours, targetPeriodHours) * 100).round() : 0;
        periodFooterLabel = 'Total Month: ${totalPeriodHours.toStringAsFixed(1)}h / ${targetPeriodHours.toStringAsFixed(1)}h ($pct%)';
        break;
      case InsightPeriod.trend:
        final daysInTrend = (_rangeEnd.difference(_rangeStart).inDays + 1).clamp(1, 1000);
        if (daysInTrend <= 14) {
          chartGoalLine = dailyGoalHours;
          goalLineLabel = 'GOAL TARGET (${dailyGoalHours.toStringAsFixed(1)}h/day)';
        } else if (daysInTrend <= 90) {
          chartGoalLine = dailyGoalHours * 7.0;
          goalLineLabel = 'GOAL TARGET (${chartGoalLine.toStringAsFixed(1)}h/wk)';
        } else {
          chartGoalLine = dailyGoalHours * 30.0;
          goalLineLabel = 'GOAL TARGET (${chartGoalLine.toStringAsFixed(1)}h/mo)';
        }
        targetPeriodHours = dailyGoalHours * daysInTrend.toDouble();
        final pct = targetPeriodHours > 0 ? (safeRatio(totalPeriodHours, targetPeriodHours) * 100).round() : 0;
        periodFooterLabel = 'Total Range: ${totalPeriodHours.toStringAsFixed(1)}h / ${targetPeriodHours.toStringAsFixed(1)}h ($pct%)';
        break;
    }
    final double variance = totalPeriodHours - targetPeriodHours;

    final FocusChartScale scale = FocusChartScale.compute(peakVal, chartGoalLine ?? 0.0);
    final double maxY = scale.maxY;

    final headerTitle = _selectedPeriod == InsightPeriod.day
        ? 'DAY FOCUS TIME'
        : (_selectedPeriod == InsightPeriod.month
            ? 'MONTH FOCUS TIME'
            : (_selectedPeriod == InsightPeriod.trend
                ? 'TREND FOCUS TIME'
                : 'Weekly Focus Distribution'));

    const double plotAreaHeight = 190.0;
    const double baselineBottom = 24.0;
    const double topPadding = 26.0;
    const double chartPlotHeight = plotAreaHeight - baselineBottom - topPadding; // 140.0 px

    final int count = buckets.length;
    final double barColWidth = count <= 6 ? 40.0 : (count <= 8 ? 32.0 : (count <= 14 ? 22.0 : 18.0));
    final double barWidth = count <= 6 ? 30.0 : (count <= 8 ? 24.0 : (count <= 14 ? 16.0 : 12.0));
    final double valFontSize = count <= 6 ? 10.0 : (count <= 8 ? 9.5 : 8.5);
    final double labelFontSize = count <= 6 ? 10.5 : (count <= 8 ? 10.0 : 9.0);

    return Container(
      height: 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Active academic load tracked by session timer',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      peakVal > 0 ? 'Peak: $peakDay (${peakVal.toStringAsFixed(1)} hrs)' : 'Peak: None (0 hrs)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          if (sessions.isEmpty)
            SizedBox(
              height: plotAreaHeight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded, color: colors.textMuted, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'No study sessions recorded for this period. Use the Timer to start logging focus blocks.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.secondary,
                        foregroundColor: const Color(0xFF171C24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () {
                        SafeHaptics.selectionClick();
                        ref.read(navigationIndexProvider.notifier).state = 2;
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('Start Focus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: plotAreaHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Ticks & subtle grid lines
                  ...scale.ticks.map((tick) {
                    final double tickBottom = baselineBottom + (tick / maxY).clamp(0.0, 1.0) * chartPlotHeight;
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: tickBottom,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '${tick.toStringAsFixed(1)}h',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: colors.surfaceBorder.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Dashed GOAL TARGET line (hidden for intra-day 4-hour blocks)
                  if (chartGoalLine != null)
                    Positioned(
                      left: 38,
                      right: 0,
                      bottom: baselineBottom + (chartGoalLine / maxY).clamp(0.0, 1.0) * chartPlotHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          CustomPaint(
                            size: const Size(double.infinity, 1),
                            painter: _DashedLinePainter(colors.secondary.withValues(alpha: 0.7)),
                          ),
                          Positioned(
                            right: 0,
                            top: -14,
                            child: InkWell(
                              onTap: () => _showEditDailyGoalDialog(context, colors, dailyGoalHours),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      goalLineLabel,
                                      style: GoogleFonts.jetBrainsMono(
                                        color: colors.secondary,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(Icons.edit_rounded, size: 9, color: colors.secondary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // The Bars (anchored to baseline)
                  Positioned(
                    left: 38,
                    right: 8,
                    bottom: baselineBottom,
                    top: 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: buckets.map((b) {
                        final double hrs = b.hours;
                        final bool isPeak = peakVal > 0 && hrs == peakVal;
                        final double barHeight = hrs > 0
                            ? ((hrs / maxY).clamp(0.0, 1.0) * chartPlotHeight).clamp(4.0, chartPlotHeight)
                            : 0.0;

                        return SizedBox(
                          width: barColWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (hrs > 0)
                                Text(
                                  '${hrs.toStringAsFixed(1)}h',
                                  maxLines: 1,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: isPeak ? colors.secondary : colors.primary,
                                    fontSize: valFontSize,
                                    fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                )
                              else
                                const SizedBox(height: 14),
                              const SizedBox(height: 3),
                              Container(
                                width: barWidth,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isPeak ? colors.secondary : colors.primary.withValues(alpha: 0.65),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  border: isPeak ? null : Border.all(color: colors.primary.withValues(alpha: 0.3)),
                                  boxShadow: isPeak
                                      ? [
                                          BoxShadow(
                                            color: colors.secondary.withValues(alpha: 0.35),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Period Labels (below baseline)
                  Positioned(
                    left: 38,
                    right: 8,
                    bottom: 0,
                    height: baselineBottom,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: buckets.map((b) {
                        final double hrs = b.hours;
                        final bool isPeak = peakVal > 0 && hrs == peakVal;
                        return SizedBox(
                          width: barColWidth,
                          child: Center(
                            child: Text(
                              b.label,
                              style: GoogleFonts.jetBrainsMono(
                                color: isPeak ? colors.textPrimary : colors.textMuted,
                                fontSize: labelFontSize,
                                fontWeight: isPeak ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Footer Metric Summary
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.verified_rounded, size: 14, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 11),
                            children: [
                              const TextSpan(text: 'Target Variance: '),
                              TextSpan(
                                text: '${variance >= 0 ? '+' : ''}${variance.toStringAsFixed(1)}h overall',
                                style: GoogleFonts.jetBrainsMono(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  periodFooterLabel,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSubjectDistribution(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    List<dynamic> enrolledCourses,
    bool isUni,
  ) {
    final allocationList = _computeSubjectAllocationData(sessions, enrolledCourses);
    final totalSec = allocationList.fold<int>(0, (acc, item) => acc + (item['seconds'] as int));
    final focusTimeStr = _formatFocusDuration(totalSec);
    final activeCount = allocationList.where((item) => (item['seconds'] as int) > 0).length;

    String dominantCode = allocationList.isNotEmpty ? (allocationList.first['code'] as String) : 'General Study';
    int dominantPct = allocationList.isNotEmpty ? (allocationList.first['pct'] as int) : 0;

    return Container(
      height: 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUni ? 'Course Allocation' : 'Subject Allocation',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUni ? 'Distribution across enrolled modules' : 'Distribution across enrolled subjects',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  '$activeCount ${isUni ? "Courses" : "Subjects"} Active',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 190,
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(140, 140),
                        painter: _DonutChartPainter(
                          values: allocationList.isNotEmpty && totalSec > 0
                              ? allocationList.map((e) => (e['seconds'] as int).toDouble()).toList()
                              : const [1.0],
                          colors: allocationList.isNotEmpty && totalSec > 0
                              ? allocationList.map((e) => e['color'] as Color).toList()
                              : [colors.surfaceBorder],
                          trackColor: colors.recessed,
                          strokeWidth: 14,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            focusTimeStr,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'FOCUSED',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 190,
                    child: allocationList.isEmpty || totalSec == 0
                        ? Center(
                            child: Text(
                              isUni
                                  ? 'No enrolled courses or focus sessions logged yet.'
                                  : 'No enrolled subjects or focus sessions logged yet.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          )
                        : Scrollbar(
                            thumbVisibility: false,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(right: 4),
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              itemCount: allocationList.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final item = allocationList[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: colors.recessed,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: colors.surfaceBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: item['color'] as Color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['code'] as String,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.plusJakartaSans(
                                                color: colors.textPrimary,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              item['title'] as String,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.plusJakartaSans(
                                                color: colors.textMuted,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${item['pct']}%',
                                            style: GoogleFonts.jetBrainsMono(
                                              color: item['color'] as Color,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            item['hoursStr'] as String,
                                            style: GoogleFonts.jetBrainsMono(
                                              color: colors.textMuted,
                                              fontSize: 9.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.psychology_rounded, size: 14, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Primary Discipline: $dominantCode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Dominant: $dominantPct%',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCircadianRhythmCard(ChondrobinduThemeColors colors, List<StudySession> sessions) {
    final circadianData = _computeCircadianData(sessions, _currentAnchorDate);
    final List<StudySession> daySessions = circadianData['daySessions'] as List<StudySession>;
    final String peakWindow = circadianData['peakWindow'] as String;

    return Container(
      height: 270,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Circadian Focus Rhythm',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chronological time blocks logged across diurnal cycles (00:00 – 24:00)',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bedtime_rounded, size: 14, color: colors.secondary),
                    const SizedBox(width: 6),
                    Text(
                      'Peak Flow: $peakWindow',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'].map((h) {
              return Text(
                h,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 9.5,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 4),

          Container(
            height: 38,
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (width <= 0 || width.isNaN || width.isInfinite) {
                  return const SizedBox();
                }
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(7, (_) => Container(width: 1, color: colors.surfaceBorder.withValues(alpha: 0.5))),
                      ),
                    ),
                    if (daySessions.isEmpty)
                      Center(
                        child: Text(
                          'No focus blocks logged on ${DateFormat('d MMM yyyy').format(_currentAnchorDate)}.',
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      )
                    else
                      ...daySessions.map((s) {
                        final startM = (s.startedAt.hour * 60 + s.startedAt.minute).clamp(0, 1440);
                        final durM = math.max(15, (s.durationSeconds / 60).round());
                        final left = safeRatio(startM, 1440.0) * width;
                        final safeBlockWidth = math.min(width, math.max(20.0, safeRatio(durM, 1440.0) * width));
                        final maxLeft = math.max(0.0, width - safeBlockWidth);
                        final safeLeft = (left.isNaN || left.isInfinite) ? 0.0 : left.clamp(0.0, maxLeft);

                        Color blockColor;
                        if (s.startedAt.hour < 12) {
                          blockColor = colors.success;
                        } else if (s.startedAt.hour < 18) {
                          blockColor = colors.secondary;
                        } else {
                          blockColor = colors.primary;
                        }

                        return Positioned(
                          left: safeLeft,
                          width: safeBlockWidth,
                          top: 4,
                          bottom: 4,
                          child: Tooltip(
                            message: '${s.cleanTitle}: ${DateFormat('HH:mm').format(s.startedAt)} - ${DateFormat('HH:mm').format(s.endedAt)} (${durM}m)',
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: blockColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                s.courseCode.isNotEmpty ? s.courseCode : 'FOCUS',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.jetBrainsMono(
                                  color: const Color(0xFF171C24),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _legendDot(colors.success, '09:00–12:00 Morning', colors),
                const SizedBox(width: 12),
                _legendDot(colors.secondary, '12:00–18:00 Afternoon', colors),
                const SizedBox(width: 12),
                _legendDot(colors.primary, '18:00–24:00 Night', colors),
              ],
            ),
          ),

          const SizedBox(height: 6),

          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology_rounded, size: 16, color: colors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Peak Cognitive Window: $peakWindow',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Deep Session Retention across diurnal cycle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color dotColor, String label, ChondrobinduThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: colors.textMuted,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopStudyRigorMatrixCard(
    ChondrobinduThemeColors colors,
    List<StudySession> recentSessions,
    List<dynamic> attendanceRecords,
    bool isUni, {
    int weeksCount = 12,
  }) {
    final matrixData = _computeRigorMatrixData(recentSessions, weeksCount);
    final List<List<Map<String, dynamic>>> grid = matrixData['grid'] as List<List<Map<String, dynamic>>>;
    final int activeDays = matrixData['activeDays'] as int;

    String attendanceStr = 'Academic Consistency';
    if (attendanceRecords.isNotEmpty) {
      int attended = 0;
      for (final r in attendanceRecords) {
        if (r is AttendanceRecord) {
          if (r.status == AttendanceStatus.attended) attended++;
        } else if (r is Map) {
          if (r['status'] == 'attended' || r['isPresent'] == true) attended++;
        }
      }
      final pct = (safeRatio(attended, attendanceRecords.length) * 100).toStringAsFixed(1);
      attendanceStr = '$pct% Attendance Logged';
    }

    final dayLabels = ['S', 'S', 'M', 'T', 'W', 'T', 'F'];

    return Container(
      height: 270,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Study Rigor Matrix',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '12-Week Academic Consistency Calendar',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  'Weeks W01 – W12',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: dayLabels.map((lbl) {
                  return Container(
                    height: 14,
                    margin: const EdgeInsets.only(bottom: 2),
                    alignment: Alignment.center,
                    child: Text(
                      lbl,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: List.generate(7, (rowIdx) {
                    final rowDays = grid[rowIdx];
                    return Container(
                      height: 14,
                      margin: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: rowDays.map((cell) {
                          final int intensity = cell['intensity'] as int;
                          final double hrs = cell['hours'] as double;
                          final DateTime date = cell['date'] as DateTime;

                          Color cellColor;
                          switch (intensity) {
                            case 1:
                              cellColor = colors.primary.withValues(alpha: 0.35);
                              break;
                            case 2:
                              cellColor = colors.primary;
                              break;
                            case 3:
                              cellColor = colors.secondary;
                              break;
                            case 0:
                            default:
                              cellColor = colors.recessed;
                              break;
                          }

                          return Expanded(
                            child: Tooltip(
                              message: '${DateFormat('EEE, d MMM').format(date)}: ${hrs.toStringAsFixed(1)}h',
                              child: Container(
                                height: 14,
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                decoration: BoxDecoration(
                                  color: cellColor,
                                  borderRadius: BorderRadius.circular(2.5),
                                  border: intensity == 0
                                      ? Border.all(color: colors.surfaceBorder.withValues(alpha: 0.5))
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weeks W01 – W12',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 9.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Less', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9)),
                  const SizedBox(width: 4),
                  _matrixCell(colors.recessed, border: colors.surfaceBorder),
                  _matrixCell(colors.primary.withValues(alpha: 0.35)),
                  _matrixCell(colors.primary),
                  _matrixCell(colors.secondary),
                  const SizedBox(width: 4),
                  Text('More', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 6),

          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '$activeDays Total Active Days',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    attendanceStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _matrixCell(Color color, {Color? border}) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: border != null ? Border.all(color: border) : null,
      ),
    );
  }

  Widget _buildScholarOperationalStamp(ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.architecture_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ATELIER SPECIFICATION: CHONDROBINDU CORE 2.4 — FORMAL PROOF & REASONING SYSTEM',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 10.5,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'SESSION ENGINE: DETERMINISTIC REAL-TIME SYNC',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Icon(Icons.architecture_rounded, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ATELIER SPECIFICATION: CHONDROBINDU CORE 2.4 — FORMAL PROOF & REASONING SYSTEM',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'SESSION ENGINE: DETERMINISTIC REAL-TIME SYNC',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE-NATIVE ACADEMIC INSIGHTS SUITE
  // ---------------------------------------------------------------------------

  Widget _buildMobileInsightsScreen(BuildContext context) {
    final colors = AppColors.of(context);
    final sessionsAsync = ref.watch(studySessionsRangeStreamProvider(DateRangeParam(_rangeStart, _rangeEnd)));
    final sessions = deduplicateSessions(sessionsAsync.value ?? []);
    final recentSessionsAsync = ref.watch(recentStudySessionsStreamProvider);
    final recentSessions = deduplicateSessions(recentSessionsAsync.value ?? []);
    final profile = ref.watch(liveUserProfileProvider).value ?? ref.watch(userProfileProvider);
    final isUni = profile?.isUniversityStudent == true || profile?.institutionType == InstitutionType.university;
    final effectiveCategoryTab = (isUni && _desktopCategoryTab == 'Performance') ? 'Overview' : _desktopCategoryTab;

    final coursesAsync = ref.watch(coursesStreamProvider);
    final enrolledCourses = coursesAsync.value ?? [];
    final holidaySettings = ref.watch(holidaySettingsStreamProvider).valueOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMobileStatusPill(colors, profile, isUni, holidaySettings),

              const SizedBox(height: 12),

              _buildMobileSubNav(colors, isUni),

              const SizedBox(height: 12),

              _buildMobilePeriodSelectorAndStepper(colors, isUni),

              const SizedBox(height: 16),

              if (effectiveCategoryTab == 'Time') ...[
                _buildMobileTopKpis(colors, sessions, profile),
                const SizedBox(height: 16),
                _buildMobileCircadianRhythmCard(colors, sessions),
                const SizedBox(height: 16),
                _buildMobileWeeklyHistogram(colors, sessions, profile, recentSessions),
                const SizedBox(height: 16),
                _buildMobileStudyRigorMatrixCard(colors, recentSessions, isUni, weeksCount: 6),
              ] else if (effectiveCategoryTab == 'Subjects') ...[
                _buildMobileSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                const SizedBox(height: 16),
                _buildDesktopSubjectDeepDive(colors, sessions, enrolledCourses, isUni),
              ] else if (effectiveCategoryTab == 'Performance') ...[
                _buildExamPerformanceDeltas(ref, colors.surface, colors.secondary),
                const SizedBox(height: 16),
                _buildDesktopPerformanceLedger(colors),
              ] else if (effectiveCategoryTab == 'CGPA Forecaster') ...[
                _buildDesktopCgpaForecasterWorkspace(colors, isDesktop: false),
              ] else ...[
                // Default 'Overview'
                _buildMobileTopKpis(colors, sessions, profile),

                const SizedBox(height: 16),

                _buildMobileWeeklyHistogram(colors, sessions, profile, recentSessions),

                const SizedBox(height: 16),

                _buildMobileSubjectDistribution(colors, sessions, enrolledCourses, isUni),

                const SizedBox(height: 16),

                _buildMobileCircadianRhythmCard(colors, sessions),

                const SizedBox(height: 16),

                _buildMobileStudyRigorMatrixCard(colors, recentSessions, isUni, weeksCount: 6),

                const SizedBox(height: 16),

                _buildMobileReflectionNoteCard(colors),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStatusPill(
    ChondrobinduThemeColors colors,
    dynamic profile,
    bool isUni,
    HolidaySettings? holidaySettings,
  ) {
    String trackStr = 'UNIVERSITY TRACK';
    String termStr = profile?.term?.isNotEmpty == true ? 'TERM ${profile.term}' : 'TERM 24.2';
    String? weekStr;

    if (isUni) {
      if (holidaySettings?.semesterStart != null) {
        final start = holidaySettings!.semesterStart!;
        final diffDays = _currentAnchorDate.difference(DateTime(start.year, start.month, start.day)).inDays;
        if (diffDays >= 0) {
          final weekNum = (diffDays ~/ 7) + 1;
          weekStr = 'WEEK ${weekNum.toString().padLeft(2, '0')}';
        }
      }
    } else {
      if (profile?.institutionType == InstitutionType.college || profile?.isCollegeStudent == true) {
        trackStr = 'COLLEGE TRACK';
        termStr = 'HSC 2026';
      } else {
        trackStr = 'ADMISSION TRACK';
        termStr = 'ENGINEERING';
      }
    }

    final String pillText = weekStr != null
        ? '$trackStr • $termStr • $weekStr'
        : '$trackStr • $termStr';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    pillText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          DateFormat("MMM ''yy").format(DateTime.now()).toUpperCase(),
          style: GoogleFonts.jetBrainsMono(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileSubNav(ChondrobinduThemeColors colors, bool isUni) {
    final categories = isUni
        ? ['Overview', 'Time', 'Subjects', 'CGPA Forecaster']
        : ['Overview', 'Time', 'Subjects', 'Performance'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((cat) {
          final active = _desktopCategoryTab == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              onTap: () {
                SafeHaptics.selectionClick();
                setState(() => _desktopCategoryTab = cat);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? colors.primary : colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: active ? colors.primary : colors.surfaceBorder),
                ),
                child: Text(
                  cat,
                  style: GoogleFonts.plusJakartaSans(
                    color: active ? const Color(0xFF171C24) : colors.textMuted,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobilePeriodSelectorAndStepper(ChondrobinduThemeColors colors, bool isUni) {
    final periods = [
      (InsightPeriod.day, 'Day'),
      (InsightPeriod.week, 'Week'),
      (InsightPeriod.month, 'Month'),
      (InsightPeriod.trend, 'Trend'),
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            children: periods.map((p) {
              final active = _selectedPeriod == p.$1;
              return Expanded(
                child: InkWell(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    setState(() => _selectedPeriod = p.$1);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? colors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: active ? Border.all(color: colors.surfaceBorder) : null,
                    ),
                    child: Text(
                      p.$2,
                      style: GoogleFonts.plusJakartaSans(
                        color: active ? colors.primary : colors.textMuted,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      color: _canStepBack ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _canStepBack ? () => _stepDateRange(-1) : null,
                    ),
                    Flexible(
                      child: InkWell(
                        onTap: _selectedPeriod == InsightPeriod.trend
                            ? () => _showTrendRangeDialog(context, colors, isUni)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _dateRangeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: colors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (_selectedPeriod == InsightPeriod.trend) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.tune_rounded, size: 12, color: colors.secondary),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      color: _canStepForward ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _canStepForward ? () => _stepDateRange(1) : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _jumpToCurrentRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restore_rounded, size: 13, color: colors.secondary),
                    const SizedBox(width: 4),
                    Text(
                      _quickJumpLabel,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileTopKpis(ChondrobinduThemeColors colors, List<StudySession> sessions, dynamic profile) {
    final int totalSec = _computeTotalFocusSeconds(sessions);
    final String focusTimeStr = _formatFocusDuration(totalSec);
    final String sessionCountStr = '${sessions.length}';
    final String sessionSubtitle = sessions.isNotEmpty ? '▲ High consistency' : '0 sessions recorded';

    final int maxSec = _computeMaxSessionSeconds(sessions);
    final String maxSessionStr = maxSec > 0
        ? (maxSec >= 3600 ? '${maxSec ~/ 3600}h ${(maxSec % 3600) ~/ 60}m' : '${maxSec ~/ 60}m')
        : '0m';
    final String longestCourse = _computeLongestSessionCourse(sessions);

    final int daysCount = (_rangeEnd.difference(_rangeStart).inDays + 1).clamp(1, 365);
    final int avgDailySec = _computeAvgDailyFocusSeconds(sessions, daysCount);
    final String avgDailyStr = avgDailySec > 0
        ? (avgDailySec >= 3600 ? '${avgDailySec ~/ 3600}h ${(avgDailySec % 3600) ~/ 60}m' : '${avgDailySec ~/ 60}m')
        : '0m';
    final double dailyGoalHours = (profile?.dailyFocusGoalHours != null && profile!.dailyFocusGoalHours > 0)
        ? profile.dailyFocusGoalHours
        : 1.0;
    final int targetPct = (safeRatio(avgDailySec, dailyGoalHours * 3600.0) * 100).round();

    final int streakDays = profile?.streakDays ?? 0;
    final String streakSubtitle = '$streakDays-day streak active';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'TOTAL FOCUS',
                value: focusTimeStr,
                badge: streakSubtitle,
                badgeColor: colors.secondary,
                icon: Icons.local_fire_department_rounded,
                iconColor: colors.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'SESSIONS',
                value: sessionCountStr,
                badge: sessionSubtitle,
                badgeColor: sessions.isNotEmpty ? colors.success : colors.textMuted,
                icon: Icons.adjust_rounded,
                iconColor: colors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'LONGEST SESSION',
                value: maxSessionStr,
                badge: longestCourse,
                badgeColor: colors.primary,
                icon: Icons.bolt_rounded,
                iconColor: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'AVG DAILY FOCUS',
                value: avgDailyStr,
                badge: '$targetPct% of ${dailyGoalHours.toStringAsFixed(1)}h goal ✎',
                badgeColor: colors.textMuted,
                icon: Icons.schedule_rounded,
                iconColor: colors.primary,
                onTap: () => _showEditDailyGoalDialog(context, colors, dailyGoalHours),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mobileKpiCard({
    required ChondrobinduThemeColors colors,
    required String title,
    required String value,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Icon(icon, color: iconColor, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: badgeColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.edit_rounded, size: 11, color: colors.secondary),
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: cardContent,
      );
    }
    return cardContent;
  }

  Widget _buildMobileWeeklyHistogram(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    dynamic profile, [
    List<StudySession>? recentSessions,
  ]) {
    final buckets = _computeFocusDistributionData(sessions, recentSessions);
    double peakVal = 0.0;
    String peakDay = 'None';
    for (final b in buckets) {
      final hrs = b.hours;
      if (!hrs.isNaN && hrs > peakVal) {
        peakVal = hrs;
        peakDay = b.label;
      }
    }

    final double dailyGoalHours = (profile?.dailyFocusGoalHours != null && profile!.dailyFocusGoalHours > 0)
        ? profile.dailyFocusGoalHours
        : 1.0;

    double? chartGoalLine;
    String goalLineLabel = '';

    switch (_selectedPeriod) {
      case InsightPeriod.day:
        chartGoalLine = null; // Hide in day mode
        break;
      case InsightPeriod.week:
        chartGoalLine = dailyGoalHours;
        goalLineLabel = 'GOAL (${dailyGoalHours.toStringAsFixed(1)}h)';
        break;
      case InsightPeriod.month:
        chartGoalLine = dailyGoalHours * 7.0;
        goalLineLabel = 'GOAL (${chartGoalLine.toStringAsFixed(1)}h/wk)';
        break;
      case InsightPeriod.trend:
        final daysInTrend = (_rangeEnd.difference(_rangeStart).inDays + 1).clamp(1, 1000);
        if (daysInTrend <= 14) {
          chartGoalLine = dailyGoalHours;
          goalLineLabel = 'GOAL (${dailyGoalHours.toStringAsFixed(1)}h)';
        } else if (daysInTrend <= 90) {
          chartGoalLine = dailyGoalHours * 7.0;
          goalLineLabel = 'GOAL (${chartGoalLine.toStringAsFixed(1)}h/wk)';
        } else {
          chartGoalLine = dailyGoalHours * 30.0;
          goalLineLabel = 'GOAL (${chartGoalLine.toStringAsFixed(1)}h/mo)';
        }
        break;
    }

    final FocusChartScale scale = FocusChartScale.compute(peakVal, chartGoalLine ?? 0.0);
    final double maxY = scale.maxY;

    final headerTitle = _selectedPeriod == InsightPeriod.day
        ? 'DAY FOCUS TIME'
        : (_selectedPeriod == InsightPeriod.month
            ? 'MONTH FOCUS TIME'
            : (_selectedPeriod == InsightPeriod.trend
                ? 'TREND FOCUS TIME'
                : 'Weekly Focus Distribution'));

    const double mobilePlotHeight = 150.0;
    const double baselineBottom = 22.0;
    const double topPadding = 24.0;
    const double chartPlotHeight = mobilePlotHeight - baselineBottom - topPadding; // 104.0 px

    final int count = buckets.length;
    final double barColWidth = count <= 6 ? 34.0 : (count <= 8 ? 26.0 : (count <= 14 ? 18.0 : 14.0));
    final double barWidth = count <= 6 ? 26.0 : (count <= 8 ? 20.0 : (count <= 14 ? 13.0 : 10.0));
    final double valFontSize = count <= 6 ? 9.5 : (count <= 8 ? 9.0 : 8.0);
    final double labelFontSize = count <= 6 ? 10.0 : (count <= 8 ? 9.5 : 8.5);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Chronological hours tracked',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  peakVal > 0 ? 'Peak: $peakDay (${peakVal.toStringAsFixed(1)}h)' : 'Peak: None',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No study sessions recorded for this period.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              height: mobilePlotHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Ticks & subtle grid lines
                  ...scale.ticks.map((tick) {
                    final double tickBottom = baselineBottom + (tick / maxY).clamp(0.0, 1.0) * chartPlotHeight;
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: tickBottom,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${tick.toStringAsFixed(1)}h',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: colors.surfaceBorder.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Dashed GOAL TARGET line (hidden on Day mode)
                  if (chartGoalLine != null)
                    Positioned(
                      left: 34,
                      right: 0,
                      bottom: baselineBottom + (chartGoalLine / maxY).clamp(0.0, 1.0) * chartPlotHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          CustomPaint(
                            size: const Size(double.infinity, 1),
                            painter: _DashedLinePainter(colors.secondary.withValues(alpha: 0.7)),
                          ),
                          Positioned(
                            right: 0,
                            top: -12,
                            child: InkWell(
                              onTap: () => _showEditDailyGoalDialog(context, colors, dailyGoalHours),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      goalLineLabel,
                                      style: GoogleFonts.jetBrainsMono(
                                        color: colors.secondary,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(Icons.edit_rounded, size: 8, color: colors.secondary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Bars (anchored to baseline)
                  Positioned(
                    left: 34,
                    right: 8,
                    bottom: baselineBottom,
                    top: 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: buckets.map((b) {
                        final double hrs = b.hours;
                        final bool isPeak = peakVal > 0 && hrs == peakVal;
                        final double barHeight = hrs > 0
                            ? ((hrs / maxY).clamp(0.0, 1.0) * chartPlotHeight).clamp(4.0, chartPlotHeight)
                            : 0.0;

                        return SizedBox(
                          width: barColWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (hrs > 0)
                                Text(
                                  '${hrs.toStringAsFixed(1)}h',
                                  maxLines: 1,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: isPeak ? colors.secondary : colors.primary,
                                    fontSize: valFontSize,
                                    fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                )
                              else
                                const SizedBox(height: 12),
                              const SizedBox(height: 2),
                              Container(
                                width: barWidth,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isPeak ? colors.secondary : colors.primary.withValues(alpha: 0.65),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Period labels (below baseline)
                  Positioned(
                    left: 34,
                    right: 8,
                    bottom: 0,
                    height: baselineBottom,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: buckets.map((b) {
                        final double hrs = b.hours;
                        final bool isPeak = peakVal > 0 && hrs == peakVal;
                        return SizedBox(
                          width: barColWidth,
                          child: Center(
                            child: Text(
                              b.label,
                              style: GoogleFonts.jetBrainsMono(
                                color: isPeak ? colors.textPrimary : colors.textMuted,
                                fontSize: labelFontSize,
                                fontWeight: isPeak ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileSubjectDistribution(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    List<dynamic> enrolledCourses,
    bool isUni,
  ) {
    final allocationList = _computeSubjectAllocationData(sessions, enrolledCourses);
    final totalSec = allocationList.fold<int>(0, (acc, item) => acc + (item['seconds'] as int));
    final focusTimeStr = _formatFocusDuration(totalSec);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Subject Allocation',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isUni ? 'Active enrolled modules' : 'Active enrolled subjects',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  '100% AUDITED',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Centered Donut Graphic
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(150, 150),
                    painter: _DonutChartPainter(
                      values: allocationList.map((e) => (e['seconds'] as int).toDouble()).toList(),
                      colors: allocationList.map((e) => e['color'] as Color).toList(),
                      trackColor: colors.recessed,
                      strokeWidth: 15,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        focusTimeStr,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'TOTAL FOCUS',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Stacked Course Breakdown Cards
          Column(
            children: allocationList.take(4).map((item) {
              return _buildCourseLegendItem(colors, item);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCircadianRhythmCard(ChondrobinduThemeColors colors, List<StudySession> sessions) {
    final circadianData = _computeCircadianData(sessions, _currentAnchorDate);
    final List<StudySession> daySessions = circadianData['daySessions'] as List<StudySession>;
    final String peakWindow = circadianData['peakWindow'] as String;
    final double morningHrs = circadianData['morningHours'] as double;
    final double middayHrs = circadianData['middayHours'] as double;
    final double nightHrs = circadianData['nightHours'] as double;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '24-Hour Diurnal Rhythm',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Peak: $peakWindow',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['00:00', '06:00', '12:00', '18:00', '24:00'].map((h) {
              return Text(
                h,
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5),
              );
            }).toList(),
          ),

          const SizedBox(height: 6),

          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (width <= 0 || width.isNaN || width.isInfinite) {
                return const SizedBox(height: 38);
              }
              return Container(
                height: 38,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (daySessions.isEmpty)
                      Center(
                        child: Text(
                          'No focus blocks logged today.',
                          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11),
                        ),
                      )
                    else
                      ...daySessions.map((s) {
                        final startM = (s.startedAt.hour * 60 + s.startedAt.minute).clamp(0, 1440);
                        final durM = math.max(15, (s.durationSeconds / 60).round());
                        final left = safeRatio(startM, 1440.0) * width;
                        final safeBlockWidth = math.min(width, math.max(16.0, safeRatio(durM, 1440.0) * width));
                        final maxLeft = math.max(0.0, width - safeBlockWidth);
                        final safeLeft = (left.isNaN || left.isInfinite) ? 0.0 : left.clamp(0.0, maxLeft);

                        Color blockColor;
                        if (s.startedAt.hour < 12) {
                          blockColor = colors.success;
                        } else if (s.startedAt.hour < 18) {
                          blockColor = colors.secondary;
                        } else {
                          blockColor = colors.primary;
                        }

                        return Positioned(
                          left: safeLeft,
                          width: safeBlockWidth,
                          top: 4,
                          bottom: 4,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: blockColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              s.courseCode.isNotEmpty ? s.courseCode : 'F',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                color: const Color(0xFF171C24),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          // Diurnal Split Badges from Stitch Mobile Spec
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Morning (${morningHrs.toStringAsFixed(1)}h)',
                style: GoogleFonts.jetBrainsMono(color: colors.success, fontSize: 10),
              ),
              Text(
                'Midday (${middayHrs.toStringAsFixed(1)}h)',
                style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 10),
              ),
              Text(
                'Night Flow (${nightHrs.toStringAsFixed(1)}h)',
                style: GoogleFonts.jetBrainsMono(color: colors.primary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileStudyRigorMatrixCard(
    ChondrobinduThemeColors colors,
    List<StudySession> recentSessions,
    bool isUni, {
    int weeksCount = 6,
  }) {
    final matrixData = _computeRigorMatrixData(recentSessions, weeksCount);
    final List<List<Map<String, dynamic>>> grid = matrixData['grid'] as List<List<Map<String, dynamic>>>;
    final dayLabels = ['S', 'S', 'M', 'T', 'W', 'T', 'F'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '6-Week Density Matrix',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Text('Less', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5)),
                  const SizedBox(width: 4),
                  _matrixCell(colors.recessed, border: colors.surfaceBorder),
                  _matrixCell(colors.primary.withValues(alpha: 0.35)),
                  _matrixCell(colors.primary),
                  _matrixCell(colors.secondary),
                  const SizedBox(width: 4),
                  Text('Peak', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              children: [
                Column(
                  children: dayLabels.map((lbl) {
                    return Container(
                      height: 12,
                      margin: const EdgeInsets.only(bottom: 4),
                      alignment: Alignment.center,
                      child: Text(
                        lbl,
                        style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: List.generate(7, (rowIdx) {
                      final rowDays = grid[rowIdx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Row(
                          children: rowDays.map((cell) {
                            final int intensity = cell['intensity'] as int;
                            Color cellColor;
                            switch (intensity) {
                              case 1:
                                cellColor = colors.primary.withValues(alpha: 0.35);
                                break;
                              case 2:
                                cellColor = colors.primary;
                                break;
                              case 3:
                                cellColor = colors.secondary;
                                break;
                              case 0:
                              default:
                                cellColor = colors.surface;
                                break;
                            }
                            return Expanded(
                              child: Container(
                                height: 12,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: cellColor,
                                  borderRadius: BorderRadius.circular(2),
                                  border: intensity == 0 ? Border.all(color: colors.surfaceBorder.withValues(alpha: 0.5)) : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileReflectionNoteCard(ChondrobinduThemeColors colors) {
    final journalAsync = ref.watch(journalStreamProvider);
    final entries = journalAsync.value ?? [];
    final latest = entries.isNotEmpty ? entries.first : null;

    final String quote = latest != null && latest.content.isNotEmpty
        ? (latest.content.length > 140 ? '${latest.content.substring(0, 140)}...' : latest.content)
        : 'Regular academic focus logging builds high retention and cognitive momentum. Review challenging problem sets during peak diurnal focus windows.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.psychology_rounded, size: 18, color: colors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Scholar's Weekly Note",
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  quote,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DETAILED SUB-TABS (SUBJECT DEEP DIVE, PERFORMANCE LEDGER, CGPA FORECASTER)
  // ---------------------------------------------------------------------------

  Widget _buildDesktopSubjectDeepDive(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    List<dynamic> enrolledCourses,
    bool isUni,
  ) {
    return Container(
      height: 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isUni ? 'Course Focus Breakdown' : 'Subject Focus Breakdown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${enrolledCourses.length} Enrolled',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (enrolledCourses.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No enrolled courses found for this term.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: enrolledCourses.length,
                separatorBuilder: (_, __) => Divider(color: colors.surfaceBorder, height: 16),
                itemBuilder: (context, index) {
                final course = enrolledCourses[index];
                final code = (course.code as String? ?? '').isNotEmpty ? (course.code as String) : (course.title as String? ?? '');
                final title = course.title as String? ?? '';
                final courseSessions = sessions.where((s) =>
                    (s.courseCode.isNotEmpty && s.courseCode.toLowerCase() == code.toLowerCase()) ||
                    s.courseId == course.id).toList();
                final int totalSec = courseSessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
                final String timeStr = _formatFocusDuration(totalSec);

                return Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _parseCourseColor(course.colorHex as String?) ?? colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            code,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${courseSessions.length} sessions',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      timeStr,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopPerformanceLedger(ChondrobinduThemeColors colors) {
    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = examsAsync.value ?? [];
    final assessmentsAsync = ref.watch(upcomingAssessmentsStreamProvider);
    final upcomingAssessments = assessmentsAsync.value ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Assessment Performance Ledger',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${allExams.length} Total Exams',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (allExams.isEmpty && upcomingAssessments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No assessment records found.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                ),
              ),
            )
          else ...[
            ...allExams.take(5).map((exam) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _ledgerRow(
                  colors: colors,
                  title: exam.examName,
                  date: DateFormat('d MMM yyyy').format(exam.date),
                  score: '${exam.scorePercentage.toStringAsFixed(1)}%',
                  isPass: exam.scorePercentage >= 50.0,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _ledgerRow({
    required ChondrobinduThemeColors colors,
    required String title,
    required String date,
    required String score,
    required bool isPass,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            score,
            style: GoogleFonts.jetBrainsMono(
              color: isPass ? colors.success : colors.secondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCgpaForecasterWorkspace(ChondrobinduThemeColors colors, {bool isDesktop = true}) {
    final profileAsync = ref.watch(liveUserProfileProvider);
    final fallbackProfile = ref.watch(userProfileProvider);
    final profile = profileAsync.value ?? fallbackProfile;
    final enrolledCourses = ref.watch(coursesStreamProvider).valueOrNull ?? [];

    return CgpaForecasterWorkspace(
      courses: enrolledCourses,
      profile: profile,
      isDesktop: isDesktop,
      onNavigateToCourses: () {
        setState(() {
          _desktopCategoryTab = 'Subjects';
        });
      },
    );
  }



  Widget _buildExamPerformanceDeltas(WidgetRef ref, Color cardColor, Color accentColor) {
    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = examsAsync.asData?.value ?? [];

    final completedExams = allExams
        .where((e) => (e.isCompleted && !e.isAbsent) || e.marksObtained > 0)
        .toList();

    completedExams.sort((a, b) => a.date.compareTo(b.date));

    final latestExam = completedExams.isNotEmpty ? completedExams.last : null;
    final previousExam = completedExams.length > 1 ? completedExams[completedExams.length - 2] : latestExam;

    final latestScore = latestExam?.scorePercentage ?? 0.0;
    final previousScore = previousExam?.scorePercentage ?? latestScore;
    final marksDelta = latestScore - previousScore;

    final latestRank = latestExam?.meritPosition ?? 0;
    final previousRank = previousExam?.meritPosition ?? latestRank;
    final rankDelta = previousRank - latestRank;

    const emeraldColor = Color(0xFF4E9F72);
    const roseColor = Color(0xFFC88256);

    final marksDeltaColor = marksDelta >= 0 ? emeraldColor : roseColor;
    final rankDeltaColor = rankDelta >= 0 ? emeraldColor : roseColor;

    final formattedMarksDelta = marksDelta >= 0
        ? '+${marksDelta.toStringAsFixed(1)}%'
        : '-${marksDelta.abs().toStringAsFixed(1)}%';

    final formattedRankDelta = rankDelta > 0
        ? '▲ +$rankDelta'
        : (rankDelta < 0 ? '▼ ${rankDelta.abs()}' : '— 0');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E3846)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.trending_up_rounded, color: Color(0xFFC88256), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Performance Trends',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFEDEAE0),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${completedExams.length} Exams Logged',
                style: const TextStyle(color: Color(0xFF8B95A5), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (completedExams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  'Log exam scores in the Exams tab to view performance trends.',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF8B95A5), fontSize: 12.5),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B222C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E3846)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Latest Score',
                          style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${latestScore.toStringAsFixed(1)}%',
                          style: const TextStyle(color: Color(0xFFEDEAE0), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (completedExams.length > 1)
                          Text(
                            formattedMarksDelta,
                            style: TextStyle(color: marksDeltaColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                          )
                        else
                          const Text('Baseline Exam', style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B222C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E3846)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Merit Rank',
                          style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          latestRank > 0 ? '#$latestRank' : 'N/A',
                          style: const TextStyle(color: Color(0xFFEDEAE0), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (completedExams.length > 1)
                          Text(
                            formattedRankDelta,
                            style: TextStyle(color: rankDeltaColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                          )
                        else
                          const Text('Standard Rank', style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color? _parseCourseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    }
    return null;
  }

  Widget _buildCourseLegendItem(ChondrobinduThemeColors colors, Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.recessed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.surfaceBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: item['color'] as Color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['code'] as String,
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item['pct']}%',
                  style: GoogleFonts.jetBrainsMono(
                    color: item['color'] as Color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  item['hoursStr'] as String,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double startX = 0.0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(math.min(startX + dashWidth, size.width), 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// SVG-COMPLIANT MULTI-SEGMENT DONUT CHART PAINTER
// ---------------------------------------------------------------------------

class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color trackColor;
  final double strokeWidth;

  const _DonutChartPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
    this.strokeWidth = 14.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final stroke = strokeWidth > 0 ? strokeWidth : 1.0;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    if (radius <= 0 || radius.isNaN || radius.isInfinite) return;

    final center = Offset(size.width / 2, size.height / 2);

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final total = values.fold<double>(0.0, (a, b) => a + (b.isNaN || b.isInfinite ? 0.0 : b));
    if (total <= 0 || total.isNaN || total.isInfinite) return;

    double startAngle = -math.pi / 2; // -90 deg (top)
    for (int i = 0; i < values.length; i++) {
      final val = values[i];
      if (val.isNaN || val.isInfinite || val <= 0) continue;
      final sweepAngle = safeRatio(val, total) * 2 * math.pi;
      if (sweepAngle <= 0 || sweepAngle.isNaN || sweepAngle.isInfinite) continue;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors || oldDelegate.trackColor != trackColor;
  }
}
