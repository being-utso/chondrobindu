import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_login_screen.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Complete Admin Dashboard Screen for Web & Desktop Navigation
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTabIndex = 0;

  Future<void> _handleSignOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    final isWideScreen = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: accentColor, size: 24),
            SizedBox(width: 10),
            Text(
              'Admin Control Center',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
            tooltip: 'Sign Out Admin',
            onPressed: _handleSignOut,
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            // Side NavigationRail for Desktop Web
            NavigationRail(
              backgroundColor: cardColor,
              selectedIndex: _selectedTabIndex,
              onDestinationSelected: (int index) {
                SafeHaptics.lightImpact();
                setState(() => _selectedTabIndex = index);
              },
              extended: isWideScreen,
              minExtendedWidth: 200,
              indicatorColor: accentColor.withValues(alpha: 0.2),
              selectedIconTheme: const IconThemeData(color: accentColor),
              selectedLabelTextStyle: const TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              unselectedIconTheme: IconThemeData(color: Colors.blueGrey.shade400),
              unselectedLabelTextStyle: TextStyle(
                color: Colors.blueGrey.shade400,
                fontSize: 13,
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  selectedIcon: Icon(Icons.fact_check_rounded),
                  label: Text('Syllabus Moderation'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.table_chart_outlined),
                  selectedIcon: Icon(Icons.table_chart_rounded),
                  label: Text('Grading Scales'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.analytics_outlined),
                  selectedIcon: Icon(Icons.analytics_rounded),
                  label: Text('System Metrics'),
                ),
              ],
            ),
            const VerticalDivider(width: 1, color: Color(0xFF382A24)),

            // Main Content Body based on selected tab
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: const [
                  _SyllabusModerationTab(),
                  _GradingScaleControlTab(),
                  _SystemMetricsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// TAB 1: SYLLABUS MODERATION
// ==========================================
class _SyllabusModerationTab extends StatelessWidget {
  const _SyllabusModerationTab();

  Future<void> _approveCourse(BuildContext context, String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('global_courses')
          .doc(docId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Text('Course $docId approved successfully!'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to approve course: $e'),
          ),
        );
      }
    }
  }

  Future<void> _rejectCourse(BuildContext context, String docId) async {
    try {
      await FirebaseFirestore.instance.collection('global_courses').doc(docId).delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF64748B),
            behavior: SnackBarBehavior.floating,
            content: Text('Course $docId rejected & deleted.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to delete course: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pending Syllabus Submissions',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Review user-submitted global course syllabi pending approval.',
            style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('global_courses')
                  .where('status', isEqualTo: 'pending')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: AppPreloader(size: 44));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading pending syllabi: ${snapshot.error}',
                      style: const TextStyle(color: Color(0xFFEF4444)),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              size: 48, color: Color(0xFF10B981)),
                          const SizedBox(height: 12),
                          const Text(
                            'No Pending Submissions',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All user-submitted syllabi have been moderated.',
                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(cardColor),
                      dataRowColor: WidgetStateProperty.all(const Color(0xFF110D0C)),
                      border: TableBorder.all(color: Colors.white.withValues(alpha: 0.08)),
                      columns: const [
                        DataColumn(
                          label: Text('Document ID',
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: Text('Course Code',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: Text('Course Name',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: Text('University',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: Text('Actions',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      rows: docs.map((doc) {
                        final data = doc.data();
                        final docId = doc.id;

                        return DataRow(
                          cells: [
                            DataCell(Text(docId, style: const TextStyle(color: Colors.white70))),
                            DataCell(Text(data['courseCode'] as String? ?? 'N/A',
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold))),
                            DataCell(Text(data['courseName'] as String? ?? 'N/A',
                                style: const TextStyle(color: Colors.white))),
                            DataCell(Text(data['universityName'] as String? ?? 'N/A',
                                style: const TextStyle(color: Colors.white70))),
                            DataCell(
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    onPressed: () => _approveCourse(context, docId),
                                    icon: const Icon(Icons.check_rounded, size: 16),
                                    label: const Text('Approve'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFEF4444),
                                      side: const BorderSide(color: Color(0xFFEF4444)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                    onPressed: () => _rejectCourse(context, docId),
                                    icon: const Icon(Icons.close_rounded, size: 16),
                                    label: const Text('Reject'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 2: GRADING SCALE CONTROL
// ==========================================
class _GradingScaleControlTab extends StatelessWidget {
  const _GradingScaleControlTab();

  Future<void> _deleteGradingScale(BuildContext context, String docId) async {
    try {
      await FirebaseFirestore.instance.collection('university_grading').doc(docId).delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF64748B),
            behavior: SnackBarBehavior.floating,
            content: Text('Grading scale for $docId deleted.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to delete grading scale: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'University Grading Scales',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage and clean up university-specific letter grade mappings.',
            style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('university_grading').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: AppPreloader(size: 44));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading grading scales: ${snapshot.error}',
                      style: const TextStyle(color: Color(0xFFEF4444)),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.table_chart_outlined,
                              size: 48, color: Color(0xFF64748B)),
                          const SizedBox(height: 12),
                          const Text(
                            'No Custom Grading Scales',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No custom university scales found in database.',
                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(cardColor),
                      dataRowColor: WidgetStateProperty.all(const Color(0xFF110D0C)),
                      border: TableBorder.all(color: Colors.white.withValues(alpha: 0.08)),
                      columns: const [
                        DataColumn(
                          label: Text('University Name',
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: Text('Grade Rows',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: Text('Actions',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      rows: docs.map((doc) {
                        final data = doc.data();
                        final docId = doc.id;
                        final rows = data['rows'] as List<dynamic>? ?? [];

                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                docId,
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataCell(
                              Text(
                                '${rows.length} Rows Defined',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Color(0xFFEF4444), size: 20),
                                tooltip: 'Delete Scale',
                                onPressed: () => _deleteGradingScale(context, docId),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 3: SYSTEM METRICS
// ==========================================
class _SystemMetricsTab extends StatelessWidget {
  const _SystemMetricsTab();

  Future<int> _fetchUniversityStudentsCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('isUniversityStudent', isEqualTo: true)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('Error fetching university students count: $e');
      return 0;
    }
  }

  Future<int> _fetchApprovedCoursesCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('global_courses')
          .where('status', isEqualTo: 'approved')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('Error fetching approved courses count: $e');
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);
    const successColor = Color(0xFF10B981);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Metrics & Analytics',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Live system count metrics across university students and global catalog.',
            style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
          ),
          const SizedBox(height: 24),

          Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              // Card 1: Total University Students
              Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: FutureBuilder<int>(
                  future: _fetchUniversityStudentsCount(),
                  builder: (context, snapshot) {
                    final countText =
                        snapshot.connectionState == ConnectionState.waiting ? '...' : '${snapshot.data ?? 0}';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.school_rounded, color: accentColor, size: 28),
                            ),
                            const Text(
                              'STUDENTS',
                              style: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          countText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total University Students Active',
                          style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12.5),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Card 2: Total Approved Global Courses
              Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: successColor.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: FutureBuilder<int>(
                  future: _fetchApprovedCoursesCount(),
                  builder: (context, snapshot) {
                    final countText =
                        snapshot.connectionState == ConnectionState.waiting ? '...' : '${snapshot.data ?? 0}';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: successColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.auto_stories_rounded, color: successColor, size: 28),
                            ),
                            const Text(
                              'CATALOG',
                              style: TextStyle(
                                color: successColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          countText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total Approved Global Courses',
                          style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12.5),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
