import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Major app sections supported by contextual coach-mark onboarding tours
enum TourSection {
  syllabus('syllabus', 'Course Syllabus'),
  planner('planner', 'Academic Planner'),
  timer('timer', 'Focus Timer'),
  timeline('timeline', 'Study Timeline');

  final String id;
  final String label;
  const TourSection(this.id, this.label);

  /// Standard SharedPreferences storage key: e.g. 'syllabus_tour_seen'
  String get prefKey => '${id}_tour_seen';

  static TourSection? fromId(String id) {
    if (id == 'insights') return TourSection.timeline;
    for (final s in TourSection.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Service managing per-section onboarding tour state.
/// Stores seen state locally in SharedPreferences for immediate, zero-latency checks,
/// with an asynchronous best-effort mirror to Firestore (users/{uid}/settings/tours).
class TourService {
  static final TourService _instance = TourService._internal();
  factory TourService() => _instance;
  TourService._internal();

  static const String _legacyPrefPrefix = 'chondrobindu_tour_seen_';

  /// In-memory cache for fast synchronous checks once loaded
  final Map<TourSection, bool> _cache = {};
  bool _initialized = false;

  /// Active tour lock state to prevent overlapping tours across screens/tabs
  bool isTourActive = false;
  TourSection? activeSection;
  VoidCallback? _activeDismissCallback;

  /// Clear in-memory cache (e.g. on logout)
  void clearCache() {
    _cache.clear();
    _initialized = false;
    isTourActive = false;
    activeSection = null;
    _activeDismissCallback = null;
  }

  /// Register that a tour has started with an optional dismiss callback
  void startTour(TourSection section, [VoidCallback? dismissCallback]) {
    isTourActive = true;
    activeSection = section;
    _activeDismissCallback = dismissCallback;
  }

  /// Dismiss the currently active tour immediately (e.g. on tab switch)
  void dismissActiveTour() {
    if (isTourActive) {
      try {
        _activeDismissCallback?.call();
      } catch (e) {
        debugPrint('[TourService] Error dismissing active tour: $e');
      }
    }
    isTourActive = false;
    activeSection = null;
    _activeDismissCallback = null;
  }

  /// Mark the tour as finished/inactive
  void endTour(TourSection section) {
    if (activeSection == section) {
      isTourActive = false;
      activeSection = null;
      _activeDismissCallback = null;
    }
  }

  /// Initialize local cache from SharedPreferences
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final section in TourSection.values) {
        final key = section.prefKey;
        final legacyKey = '$_legacyPrefPrefix${section.id}';
        var val = prefs.getBool(key) ?? prefs.getBool(legacyKey);
        if (val == null && section == TourSection.timeline) {
          val = prefs.getBool('insights_tour_seen');
        }
        _cache[section] = val ?? false;
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[TourService] Error initializing preferences: $e');
      _initialized = true;
    }
  }

  /// Synchronous quick-check if initialized, fallback to false
  bool isTourSeenSync(TourSection section) {
    return _cache[section] ?? false;
  }

  /// Check whether a given section's tour has already been seen (local SharedPreferences)
  Future<bool> hasSeenTour(TourSection section) async {
    if (_initialized && _cache.containsKey(section)) {
      return _cache[section]!;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = section.prefKey;
      final legacyKey = '$_legacyPrefPrefix${section.id}';
      var seen = prefs.getBool(key) ?? prefs.getBool(legacyKey);
      if (seen == null && section == TourSection.timeline) {
        seen = prefs.getBool('insights_tour_seen');
      }
      final result = seen ?? false;
      _cache[section] = result;
      return result;
    } catch (e) {
      debugPrint('[TourService] Error reading tour seen flag for ${section.id}: $e');
      return _cache[section] ?? false;
    }
  }

  /// Mark a section's tour as seen locally and asynchronously mirror to Firestore
  Future<void> markTourSeen(TourSection section) async {
    endTour(section);
    _cache[section] = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(section.prefKey, true);
      if (section == TourSection.timeline) {
        await prefs.setBool('insights_tour_seen', true);
      }
    } catch (e) {
      debugPrint('[TourService] Error saving tour seen locally: $e');
    }

    // Mirror to Firestore (best-effort, non-blocking)
    _mirrorToFirestore(section, true);
  }

  /// Reset a specific section's tour so it will trigger on the next visit
  Future<void> resetTour(TourSection section) async {
    _cache[section] = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(section.prefKey, false);
      await prefs.remove('$_legacyPrefPrefix${section.id}');
      if (section == TourSection.timeline) {
        await prefs.setBool('insights_tour_seen', false);
      }
    } catch (e) {
      debugPrint('[TourService] Error resetting tour locally: $e');
    }

    // Mirror to Firestore (best-effort, non-blocking)
    _mirrorToFirestore(section, false);
  }

  /// Strictly initialize all tour sections to false (unseen) for a newly registered user
  Future<void> initializeForNewUser(String uid) async {
    for (final section in TourSection.values) {
      _cache[section] = false;
    }
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      for (final section in TourSection.values) {
        await prefs.setBool(section.prefKey, false);
        await prefs.remove('$_legacyPrefPrefix${section.id}');
      }
      await prefs.setBool('insights_tour_seen', false);
    } catch (e) {
      debugPrint('[TourService] Error writing new user flags locally: $e');
    }

    try {
      final Map<String, dynamic> initialMap = {
        'syllabus': false,
        'planner': false,
        'timer': false,
        'timeline': false,
        'insights': false,
      };
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('tours')
          .set({
        'tours_seen': initialMap,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[TourService] Error saving new user tour flags to Firestore: $e');
    }
  }

  /// Reset all section tours (for testing or full app replay)
  Future<void> resetAllTours() async {
    for (final section in TourSection.values) {
      _cache[section] = false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final section in TourSection.values) {
        await prefs.setBool(section.prefKey, false);
        await prefs.remove('$_legacyPrefPrefix${section.id}');
      }
      await prefs.setBool('insights_tour_seen', false);
    } catch (e) {
      debugPrint('[TourService] Error resetting all tours locally: $e');
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final Map<String, dynamic> resetMap = {};
        for (final section in TourSection.values) {
          resetMap['tours_seen.${section.id}'] = false;
        }
        resetMap['tours_seen.insights'] = false;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('tours')
            .set(resetMap, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[TourService] Error resetting tours in Firestore: $e');
      }
    }
  }

  /// Synchronize tour state from Firestore to local cache on user sign-in.
  /// Remote Firestore is authoritative so a new user logging into a device with
  /// prior local preferences does not get marked as having seen tours.
  Future<void> syncFromFirestore([String? userId]) async {
    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('tours')
          .get();

      if (doc.exists) {
        final data = doc.data();
        final toursSeen = data?['tours_seen'] as Map<String, dynamic>?;
        if (toursSeen != null) {
          final prefs = await SharedPreferences.getInstance();
          for (final section in TourSection.values) {
            final remoteSeen = toursSeen[section.id] as bool? ??
                (section == TourSection.timeline ? toursSeen['insights'] as bool? : null);
            if (remoteSeen != null) {
              final key = section.prefKey;
              _cache[section] = remoteSeen;
              await prefs.setBool(key, remoteSeen);
              if (section == TourSection.timeline) {
                await prefs.setBool('insights_tour_seen', remoteSeen);
              }
            }
          }
          _initialized = true;
        }
      } else {
        // Document does not exist yet (e.g. brand new user)
        await initializeForNewUser(uid);
      }
    } catch (e) {
      debugPrint('[TourService] Error syncing tour flags from Firestore: $e');
    }
  }

  /// Internal non-blocking Firestore mirror
  void _mirrorToFirestore(TourSection section, bool seen) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final Map<String, dynamic> updateMap = {
      'tours_seen.${section.id}': seen,
    };
    if (section == TourSection.timeline) {
      updateMap['tours_seen.insights'] = seen;
    }
    updateMap['lastUpdated'] = FieldValue.serverTimestamp();

    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('tours')
        .set(updateMap, SetOptions(merge: true))
        .catchError((err) {
      debugPrint('[TourService] Failed to mirror tour state to Firestore: $err');
    });
  }
}
