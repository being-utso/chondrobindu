import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Supported Academic Institution Tracks
enum InstitutionType {
  university,
  college;

  String get displayName => this == InstitutionType.university ? 'University / Engineering' : 'College / Higher Secondary';

  static InstitutionType fromString(String? val) {
    if (val == null) return InstitutionType.university;
    final normalized = val.toLowerCase().trim();
    if (normalized == 'college' || normalized == 'hsc' || normalized == 'higher_secondary') {
      return InstitutionType.college;
    }
    return InstitutionType.university;
  }
}

/// Unified UserProfile Model supporting both University and College (Higher Secondary) student profiles.
class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String photoUrl;
  final InstitutionType institutionType;

  // University Fields (nullable if college)
  final String? department;   // e.g., "EEE", "CSE"
  final String? level;        // e.g., "Level 2"
  final String? term;         // e.g., "Term 1"
  final String? universityName;

  // College Fields (nullable if university)
  final String? collegeClass; // e.g., "Class 11", "Class 12"
  final String? academicGroup;// e.g., "Science", "Commerce", "Humanities"
  final String? rollNumber;
  final String college;

  // Common Academic & Metric Fields
  final String batch;         // e.g., "2025" or "HSC 2026"
  final double targetGpa;     // 3.75 for uni, 5.00 for college
  final int streakDays;
  final DateTime? lastStudiedAt;
  final DateTime createdAt;

  // Additional Profile & App Settings
  final String fullName;
  final String nickname;
  final String username;
  final String phone;
  final String district;
  final String primaryTarget;
  final String secondaryTarget;
  final bool isOnboarded;
  final int todaysFocusMinutes;
  final int totalFocusMinutes;
  final int targetFocusMinutes;
  final String scratchpadText;
  final String? targetEventName;
  final DateTime? targetEventDate;
  final String? pinnedExamId;
  final String? pinnedHomeExamId;
  final List<String> customTimerSubjects;
  final bool isLoaded;

  final bool? _isUniversityStudent;
  final String? _major;
  final String? _hscBatch;
  final String? _hscGroup;

  const UserProfile({
    this.uid = '',
    this.email = '',
    this.displayName = 'Student',
    this.photoUrl = '',
    this.institutionType = InstitutionType.university,
    this.department,
    this.level,
    this.term,
    this.universityName,
    this.collegeClass,
    this.academicGroup,
    this.rollNumber,
    this.college = '',
    this.batch = '2025',
    this.targetGpa = 3.75,
    this.streakDays = 0,
    this.lastStudiedAt,
    DateTime? createdAt,
    this.fullName = 'Student',
    this.nickname = 'Student',
    this.username = 'student',
    this.phone = '',
    this.district = 'Dhaka',
    this.primaryTarget = 'Engineering (BUET, CKRUET)',
    this.secondaryTarget = 'None',
    this.isOnboarded = false,
    this.todaysFocusMinutes = 0,
    this.totalFocusMinutes = 0,
    this.targetFocusMinutes = 240,
    this.scratchpadText = '',
    this.targetEventName,
    this.targetEventDate,
    this.pinnedExamId,
    this.pinnedHomeExamId,
    this.customTimerSubjects = const [],
    this.isLoaded = false,
    bool? isUniversityStudent,
    String? major,
    String? hscBatch,
    String? hscGroup,
    String? profileImageUrl,
  })  : _isUniversityStudent = isUniversityStudent,
        _major = major,
        _hscBatch = hscBatch,
        _hscGroup = hscGroup,
        createdAt = createdAt ?? const _DefaultDateTime();

  // Compatibility Getters
  bool get isUniversityStudent {
    if (_isUniversityStudent != null) return _isUniversityStudent!;
    if (primaryTarget == 'HSC Candidate / Board Exam') return false;
    return institutionType == InstitutionType.university;
  }
  String? get major => _major ?? department;
  String get hscBatch => (_hscBatch != null && _hscBatch!.isNotEmpty) ? _hscBatch! : batch;
  String get hscGroup => (_hscGroup != null && _hscGroup!.isNotEmpty) ? _hscGroup! : (academicGroup ?? '');
  String? get profileImageUrl => photoUrl.isNotEmpty ? photoUrl : null;
  String get collegeName => college;
  bool get isAdmissionCandidate => !isUniversityStudent && primaryTarget != 'HSC Candidate / Board Exam';

  String get profileSubtitle {
    if (isUniversityStudent) {
      final parts = <String>[];
      if (universityName != null && universityName!.isNotEmpty) {
        parts.add(universityName!);
      }
      final dep = department ?? major;
      if (dep != null && dep.isNotEmpty) {
        parts.add(dep);
      }
      final lvl = level != null && level!.isNotEmpty
          ? (level!.startsWith('Level') ? level! : 'Level $level')
          : null;
      final trm = term != null && term!.isNotEmpty
          ? (term!.startsWith('Term') ? term! : 'Term $term')
          : null;
      if (lvl != null && trm != null) {
        parts.add('$lvl - $trm');
      } else if (lvl != null) {
        parts.add(lvl);
      } else if (trm != null) {
        parts.add(trm);
      }
      return parts.join(' • ');
    } else {
      final parts = <String>[];
      final b = (hscBatch.isNotEmpty)
          ? (hscBatch.contains('Batch') ? hscBatch : '$hscBatch Batch')
          : (batch.isNotEmpty ? (batch.contains('Batch') ? batch : '$batch Batch') : null);
      if (b != null) parts.add(b);
      if (primaryTarget.isNotEmpty) parts.add(primaryTarget);
      return parts.join(' • ');
    }
  }

  bool get isProfileComplete {
    if (!isOnboarded) return false;
    final hasName = displayName.trim().isNotEmpty || fullName.trim().isNotEmpty;
    if (!hasName) return false;
    if (isUniversityStudent) {
      final hasUni = universityName?.trim().isNotEmpty ?? false;
      final hasDept = (department?.trim().isNotEmpty ?? false) || (major?.trim().isNotEmpty ?? false);
      return hasUni || hasDept;
    } else {
      return college.trim().isNotEmpty && primaryTarget.trim().isNotEmpty;
    }
  }

  static const defaultProfile = UserProfile(
    uid: '',
    email: '',
    displayName: '',
    photoUrl: '',
    institutionType: InstitutionType.college,
    department: null,
    level: null,
    term: null,
    universityName: null,
    collegeClass: null,
    academicGroup: 'Science',
    rollNumber: null,
    college: '',
    batch: '2025',
    targetGpa: 3.75,
    streakDays: 0,
    fullName: '',
    nickname: '',
    username: '',
    phone: '',
    district: '',
    primaryTarget: 'Engineering',
    secondaryTarget: '',
    isOnboarded: false,
    todaysFocusMinutes: 0,
    totalFocusMinutes: 0,
    targetFocusMinutes: 240,
    scratchpadText: '',
    customTimerSubjects: [],
    isLoaded: false,
    isUniversityStudent: false,
  );

  /// Factory constructor parsing from Firestore DocumentSnapshot safely
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserProfile.fromMap(data, doc.id);
  }

  /// Factory constructor parsing from Map safely with zero null crashes
  factory UserProfile.fromMap(Map<String, dynamic>? map, [String? docId]) {
    if (map == null) {
      if (docId == null || docId.isEmpty) {
        return defaultProfile;
      }
      return defaultProfile.copyWith(uid: docId, isLoaded: true);
    }
    if (map.isEmpty) {
      return defaultProfile.copyWith(
        uid: docId ?? '',
        isLoaded: true,
        primaryTarget: 'Engineering',
        hscBatch: '2025',
        hscGroup: 'Science',
      );
    }

    final dName = map['displayName'] as String? ??
        map['fullName'] as String? ??
        map['nickname'] as String? ??
        map['name'] as String? ??
        '';

    final email = map['email'] as String? ?? '';
    final photo = map['photoUrl'] as String? ??
        map['photoURL'] as String? ??
        map['profileImageUrl'] as String? ??
        map['profile_image_url'] as String? ??
        '';

    // Track resolution
    InstitutionType track = InstitutionType.university;
    if (map['isUniversityStudent'] == false) {
      track = InstitutionType.college;
    } else if (map['isUniversityStudent'] == true) {
      track = InstitutionType.university;
    } else if (map['institutionType'] != null) {
      track = InstitutionType.fromString(map['institutionType'] as String?);
    } else if (map['college'] != null || map['hscBatch'] != null || map['hsc_batch'] != null) {
      track = InstitutionType.college;
    }

    final dept = map['department'] as String? ?? map['major'] as String?;
    final lvl = map['level'] as String?;
    final trm = map['term'] as String?;
    final uniName = map['universityName'] as String? ?? map['university_name'] as String?;

    final cClass = map['collegeClass'] as String? ?? map['college_class'] as String? ?? (track == InstitutionType.college ? lvl : null);
    final aGroup = map['academicGroup'] as String? ?? map['academic_group'] as String? ?? map['hscGroup'] as String? ?? map['hsc_group'] as String?;
    final rNum = map['rollNumber'] as String? ?? map['roll_number'] as String?;
    final col = map['college'] as String? ?? map['collegeName'] as String? ?? map['college_name'] as String? ?? '';

    final batchVal = map['batch'] as String? ?? map['hscBatch'] as String? ?? map['hsc_batch'] as String? ?? '2025';
    final gpaVal = (map['targetGpa'] as num?)?.toDouble() ??
        (map['target_gpa'] as num?)?.toDouble() ??
        (track == InstitutionType.college ? 5.00 : 3.75);

    DateTime? lastStudied;
    final rawLast = map['lastStudiedAt'] ?? map['last_studied_at'];
    if (rawLast != null) {
      if (rawLast is Timestamp) {
        lastStudied = rawLast.toDate();
      } else if (rawLast is String) {
        lastStudied = DateTime.tryParse(rawLast);
      }
    }

    DateTime? created;
    final rawCreated = map['createdAt'] ?? map['created_at'];
    if (rawCreated != null) {
      if (rawCreated is Timestamp) {
        created = rawCreated.toDate();
      } else if (rawCreated is String) {
        created = DateTime.tryParse(rawCreated);
      }
    }

    DateTime? targetDate;
    final rawTargetDate = map['targetEventDate'] ?? map['target_event_date'];
    if (rawTargetDate != null) {
      if (rawTargetDate is Timestamp) {
        targetDate = rawTargetDate.toDate();
      } else if (rawTargetDate is String) {
        targetDate = DateTime.tryParse(rawTargetDate);
      }
    }

    final fullName = map['fullName'] as String? ?? map['full_name'] as String? ?? map['name'] as String? ?? dName;
    final nickname = map['nickname'] as String? ?? dName;
    final username = map['username'] as String? ?? '';
    final phone = map['phone'] as String? ?? '';
    final district = map['district'] as String? ?? '';
    final primaryTarget = map['primaryTarget'] as String? ??
        map['primary_target'] as String? ??
        map['target_goal'] as String? ??
        (track == InstitutionType.university ? 'Engineering (BUET, CKRUET)' : 'Engineering');
    final secondaryTarget = map['secondaryTarget'] as String? ?? map['secondary_target'] as String? ?? 'None';
    final isOnboarded = map['isOnboarded'] as bool? ?? map['is_onboarded'] as bool? ?? false;

    return UserProfile(
      uid: docId ?? map['uid'] as String? ?? '',
      email: email,
      displayName: dName.isNotEmpty ? dName : fullName,
      photoUrl: photo,
      institutionType: track,
      department: dept,
      level: lvl,
      term: trm,
      universityName: uniName,
      collegeClass: cClass,
      academicGroup: aGroup ?? 'Science',
      rollNumber: rNum,
      college: col,
      batch: batchVal,
      targetGpa: gpaVal,
      streakDays: (map['streakDays'] as num?)?.toInt() ?? (map['streak_days'] as num?)?.toInt() ?? 0,
      lastStudiedAt: lastStudied,
      createdAt: created ?? DateTime(2026, 1, 1),
      fullName: fullName,
      nickname: nickname,
      username: username,
      phone: phone,
      district: district,
      primaryTarget: primaryTarget,
      secondaryTarget: secondaryTarget,
      isOnboarded: isOnboarded,
      todaysFocusMinutes: (map['todaysFocusMinutes'] as num?)?.toInt() ?? (map['todays_focus_minutes'] as num?)?.toInt() ?? 0,
      totalFocusMinutes: (map['totalFocusMinutes'] as num?)?.toInt() ?? (map['total_focus_minutes'] as num?)?.toInt() ?? 0,
      targetFocusMinutes: (map['targetFocusMinutes'] as num?)?.toInt() ?? (map['target_focus_minutes'] as num?)?.toInt() ?? 240,
      scratchpadText: map['scratchpadText'] as String? ?? map['scratchpad_text'] as String? ?? '',
      targetEventName: map['targetEventName'] as String? ?? map['target_event_name'] as String?,
      targetEventDate: targetDate,
      pinnedExamId: map['pinnedExamId'] as String? ?? map['pinned_exam_id'] as String?,
      pinnedHomeExamId: map['pinnedHomeExamId'] as String? ?? map['pinned_home_exam_id'] as String?,
      customTimerSubjects: (map['customTimerSubjects'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          (map['custom_timer_subjects'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      isLoaded: true,
      isUniversityStudent: map['isUniversityStudent'] as bool? ?? (track == InstitutionType.university),
      major: dept,
      hscBatch: batchVal,
      hscGroup: aGroup ?? 'Science',
      profileImageUrl: photo.isNotEmpty ? photo : null,
    );
  }

  factory UserProfile.fromFirebaseUser(User user) {
    return UserProfile(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? (user.email != null && user.email!.contains('@') ? user.email!.split('@').first : 'Student'),
      photoUrl: user.photoURL ?? '',
      institutionType: InstitutionType.university,
      department: 'Engineering',
      batch: '2025',
      targetGpa: 3.75,
      createdAt: DateTime.now(),
      isLoaded: true,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'photo_url': photoUrl,
      'institutionType': institutionType.name,
      'department': department,
      'major': major,
      'level': level,
      'term': term,
      'universityName': universityName,
      'university_name': universityName,
      'collegeClass': collegeClass,
      'college_class': collegeClass,
      'academicGroup': academicGroup,
      'academic_group': academicGroup,
      'rollNumber': rollNumber,
      'roll_number': rollNumber,
      'college': college,
      'collegeName': college,
      'college_name': college,
      'batch': batch,
      'hscBatch': hscBatch,
      'hsc_batch': hscBatch,
      'hscGroup': hscGroup,
      'hsc_group': hscGroup,
      'targetGpa': targetGpa,
      'target_gpa': targetGpa,
      'streakDays': streakDays,
      'streak_days': streakDays,
      'lastStudiedAt': lastStudiedAt != null ? Timestamp.fromDate(lastStudiedAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt is _DefaultDateTime ? DateTime(2026, 1, 1) : createdAt),
      'fullName': fullName,
      'full_name': fullName,
      'nickname': nickname,
      'username': username,
      'phone': phone,
      'district': district,
      'primaryTarget': primaryTarget,
      'primary_target': primaryTarget,
      'secondaryTarget': secondaryTarget,
      'secondary_target': secondaryTarget,
      'isOnboarded': isOnboarded,
      'is_onboarded': isOnboarded,
      'todaysFocusMinutes': todaysFocusMinutes,
      'todays_focus_minutes': todaysFocusMinutes,
      'totalFocusMinutes': totalFocusMinutes,
      'total_focus_minutes': totalFocusMinutes,
      'targetFocusMinutes': targetFocusMinutes,
      'target_focus_minutes': targetFocusMinutes,
      'scratchpadText': scratchpadText,
      'scratchpad_text': scratchpadText,
      'targetEventName': targetEventName,
      'target_event_name': targetEventName,
      'targetEventDate': targetEventDate != null ? Timestamp.fromDate(targetEventDate!) : null,
      'target_event_date': targetEventDate != null ? Timestamp.fromDate(targetEventDate!) : null,
      'pinnedExamId': pinnedExamId,
      'pinned_exam_id': pinnedExamId,
      'pinnedHomeExamId': pinnedHomeExamId,
      'pinned_home_exam_id': pinnedHomeExamId,
      'customTimerSubjects': customTimerSubjects,
      'custom_timer_subjects': customTimerSubjects,
      'isUniversityStudent': isUniversityStudent,
      'is_university_student': isUniversityStudent,
      'profileImageUrl': profileImageUrl,
      'profile_image_url': profileImageUrl,
      'isLoaded': isLoaded,
      'is_loaded': isLoaded,
    };
  }

  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    InstitutionType? institutionType,
    String? department,
    String? level,
    String? term,
    String? universityName,
    String? collegeClass,
    String? academicGroup,
    String? rollNumber,
    String? college,
    String? batch,
    double? targetGpa,
    int? streakDays,
    DateTime? lastStudiedAt,
    DateTime? createdAt,
    String? fullName,
    String? nickname,
    String? username,
    String? phone,
    String? district,
    String? primaryTarget,
    String? secondaryTarget,
    bool? isOnboarded,
    int? todaysFocusMinutes,
    int? totalFocusMinutes,
    int? targetFocusMinutes,
    String? scratchpadText,
    String? targetEventName,
    DateTime? targetEventDate,
    String? pinnedExamId,
    String? pinnedHomeExamId,
    bool clearPinnedExamId = false,
    bool clearPinnedHomeExamId = false,
    List<String>? customTimerSubjects,
    bool? isLoaded,
    bool? isUniversityStudent,
    String? major,
    String? hscBatch,
    String? hscGroup,
    String? profileImageUrl,
  }) {
    final track = institutionType ??
        (isUniversityStudent != null
            ? (isUniversityStudent ? InstitutionType.university : InstitutionType.college)
            : this.institutionType);

    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? profileImageUrl ?? this.photoUrl,
      institutionType: track,
      department: department ?? major ?? this.department,
      level: level ?? this.level,
      term: term ?? this.term,
      universityName: universityName ?? this.universityName,
      collegeClass: collegeClass ?? this.collegeClass,
      academicGroup: academicGroup ?? hscGroup ?? this.academicGroup,
      rollNumber: rollNumber ?? this.rollNumber,
      college: college ?? this.college,
      batch: batch ?? hscBatch ?? this.batch,
      targetGpa: targetGpa ?? this.targetGpa,
      streakDays: streakDays ?? this.streakDays,
      lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
      createdAt: createdAt ?? this.createdAt,
      fullName: fullName ?? this.fullName,
      nickname: nickname ?? this.nickname,
      username: username ?? this.username,
      phone: phone ?? this.phone,
      district: district ?? this.district,
      primaryTarget: primaryTarget ?? this.primaryTarget,
      secondaryTarget: secondaryTarget ?? this.secondaryTarget,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      todaysFocusMinutes: todaysFocusMinutes ?? this.todaysFocusMinutes,
      totalFocusMinutes: totalFocusMinutes ?? this.totalFocusMinutes,
      targetFocusMinutes: targetFocusMinutes ?? this.targetFocusMinutes,
      scratchpadText: scratchpadText ?? this.scratchpadText,
      targetEventName: targetEventName ?? this.targetEventName,
      targetEventDate: targetEventDate ?? this.targetEventDate,
      pinnedExamId: clearPinnedExamId ? null : (pinnedExamId ?? this.pinnedExamId),
      pinnedHomeExamId: clearPinnedHomeExamId ? null : (pinnedHomeExamId ?? this.pinnedHomeExamId),
      customTimerSubjects: customTimerSubjects ?? this.customTimerSubjects,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();
  static final DateTime _epoch = DateTime(2026, 1, 1);

  @override
  bool isBefore(DateTime other) => _epoch.isBefore(other);
  @override
  bool isAfter(DateTime other) => _epoch.isAfter(other);
  @override
  bool isAtSameMomentAs(DateTime other) => _epoch.isAtSameMomentAs(other);
  @override
  int compareTo(DateTime other) => _epoch.compareTo(other);
  @override
  int get millisecondsSinceEpoch => _epoch.millisecondsSinceEpoch;
  @override
  int get microsecondsSinceEpoch => _epoch.microsecondsSinceEpoch;
  @override
  String get timeZoneName => _epoch.timeZoneName;
  @override
  Duration get timeZoneOffset => _epoch.timeZoneOffset;
  @override
  DateTime add(Duration duration) => _epoch.add(duration);
  @override
  DateTime subtract(Duration duration) => _epoch.subtract(duration);
  @override
  Duration difference(DateTime other) => _epoch.difference(other);
  @override
  String toIso8601String() => _epoch.toIso8601String();
  @override
  DateTime toLocal() => _epoch.toLocal();
  @override
  DateTime toUtc() => _epoch.toUtc();
  @override
  int get year => _epoch.year;
  @override
  int get month => _epoch.month;
  @override
  int get day => _epoch.day;
  @override
  int get hour => _epoch.hour;
  @override
  int get minute => _epoch.minute;
  @override
  int get second => _epoch.second;
  @override
  int get millisecond => _epoch.millisecond;
  @override
  int get microsecond => _epoch.microsecond;
  @override
  int get weekday => _epoch.weekday;
  @override
  bool get isUtc => _epoch.isUtc;
  @override
  String toString() => _epoch.toString();
  @override
  dynamic noSuchMethod(Invocation invocation) => _epoch;
}
