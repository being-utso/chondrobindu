import 'dart:math' as math;

/// ClientIdentity provides a unique client instance ID per app launch
/// and RFC 4122 v4 UUID generation for idempotent cross-device synchronization.
class ClientIdentity {
  ClientIdentity._();

  /// Unique client identifier generated once per application session/process
  static final String instanceId = _generateUuidV4();

  /// Generates a new RFC 4122 compliant UUID v4 string for deterministic session keys
  static String newSessionId() => _generateUuidV4();

  static String _generateUuidV4() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 10
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
