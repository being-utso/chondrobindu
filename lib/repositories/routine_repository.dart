import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/routine_slot_model.dart';

class RoutineRepository {
  final FirebaseFirestore? _firestore;

  RoutineRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  CollectionReference<Map<String, dynamic>>? _slotsRef(String uid) =>
      _firestore?.collection('users').doc(uid).collection('routine');

  Stream<List<RoutineSlot>> watchWeeklyRoutine(String uid) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    return _slotsRef(uid)!.snapshots().map((snapshot) {
      final slots = snapshot.docs.map((doc) => RoutineSlot.fromFirestore(doc)).toList();
      slots.sort((a, b) {
        final dComp = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (dComp != 0) return dComp;
        return a.startTime.compareTo(b.startTime);
      });
      return slots;
    });
  }

  Stream<List<RoutineSlot>> watchDailyAgenda(String uid, DateTime date) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    final dayOfWeek = date.weekday; // 1 = Monday ... 7 = Sunday
    return _slotsRef(uid)!
        .where('dayOfWeek', isEqualTo: dayOfWeek)
        .snapshots()
        .map((snapshot) {
      final slots = snapshot.docs
          .map((doc) => RoutineSlot.fromFirestore(doc))
          .where((slot) {
            // Filter out slots where effectiveUntil is before date
            if (slot.effectiveUntil != null && date.isAfter(slot.effectiveUntil!)) {
              return false;
            }
            // Filter out slots where effectiveFrom is after date
            if (slot.effectiveFrom != null && date.isBefore(slot.effectiveFrom!)) {
              return false;
            }
            return true;
          })
          .toList();

      slots.sort((a, b) => a.startTime.compareTo(b.startTime));
      return slots;
    });
  }

  Future<void> addRoutineSlot(String uid, RoutineSlot slot) async {
    if (_firestore == null || uid.isEmpty) return;
    await _slotsRef(uid)!.doc(slot.id).set(slot.toMap(), SetOptions(merge: true));
  }

  Future<void> removeRoutineSlot(String uid, String slotId) async {
    if (_firestore == null || uid.isEmpty || slotId.isEmpty) return;
    await _slotsRef(uid)!.doc(slotId).delete();
  }
}
