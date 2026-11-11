import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

enum SoundscapeTrack {
  none,
  rainfall,
  heavyRain,
  brownNoise,
  cafeAmbiance,
  forestBirds,
}

/// Single persistent ambient audio controller across the entire app session.
/// Never instantiate multiple AudioPlayer instances or dispose mid-session.
class SoundscapeService {
  static final SoundscapeService _instance = SoundscapeService._internal();
  factory SoundscapeService() => _instance;
  static SoundscapeService get instance => _instance;

  final AudioPlayer _player = AudioPlayer();
  SoundscapeTrack _current = SoundscapeTrack.none;
  double _volume = 0.65;
  int _operationSequence = 0;
  bool _isInitialized = false;

  SoundscapeService._internal() {
    _init();
  }

  void _init() {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      _player.setReleaseMode(ReleaseMode.loop);
      _player.setVolume(_volume);
    } catch (e) {
      debugPrint('SoundscapeService _init notice: $e');
    }
  }

  bool get isPlaying => _current != SoundscapeTrack.none;
  SoundscapeTrack get currentTrack => _current;
  double get volume => _volume;

  static const List<String> allLabels = [
    'Rainfall',
    'Heavy Rain',
    'Brown Noise',
    'Cafe Ambiance',
    'Forest Birds',
  ];

  static String _assetPath(SoundscapeTrack track) => switch (track) {
        SoundscapeTrack.rainfall => 'noises/rain.mp3',
        SoundscapeTrack.heavyRain => 'noises/rain2.mp3',
        SoundscapeTrack.brownNoise => 'noises/wind.mp3',
        SoundscapeTrack.cafeAmbiance => 'noises/cafe.mp3',
        SoundscapeTrack.forestBirds => 'noises/birds.mp3',
        SoundscapeTrack.none => '',
      };

  static SoundscapeTrack fromLabel(String label) => switch (label) {
        'Rainfall' => SoundscapeTrack.rainfall,
        'Heavy Rain' => SoundscapeTrack.heavyRain,
        'Brown Noise' => SoundscapeTrack.brownNoise,
        'Cafe Ambiance' => SoundscapeTrack.cafeAmbiance,
        'Forest Birds' => SoundscapeTrack.forestBirds,
        _ => SoundscapeTrack.none,
      };

  static String toLabel(SoundscapeTrack track) => switch (track) {
        SoundscapeTrack.rainfall => 'Rainfall',
        SoundscapeTrack.heavyRain => 'Heavy Rain',
        SoundscapeTrack.brownNoise => 'Brown Noise',
        SoundscapeTrack.cafeAmbiance => 'Cafe Ambiance',
        SoundscapeTrack.forestBirds => 'Forest Birds',
        SoundscapeTrack.none => 'None',
      };

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    try {
      await _player.setVolume(_volume);
    } catch (e) {
      debugPrint('SoundscapeService setVolume error: $e');
    }
  }

  Future<void> play(SoundscapeTrack track) async {
    final seq = ++_operationSequence;
    if (track == SoundscapeTrack.none) {
      await stop();
      return;
    }

    _current = track;

    try {
      // 1. Stop any currently active audio
      await _player.stop();
      if (seq != _operationSequence) return;

      // 2. Configure infinite looping and volume
      await _player.setReleaseMode(ReleaseMode.loop);
      if (seq != _operationSequence) return;

      await _player.setVolume(_volume);
      if (seq != _operationSequence) return;

      // 3. Play new asset source (noises/filename.mp3 - audioplayers prepends assets/)
      await _player.play(AssetSource(_assetPath(track)));
    } catch (e, stack) {
      debugPrint("Soundscape error: $e");
      debugPrint(stack.toString());
      if (seq == _operationSequence) {
        // Fallback directly to play call
        try {
          await _player.play(AssetSource(_assetPath(track)), volume: _volume);
        } catch (e2, stack2) {
          debugPrint("Soundscape error: $e2");
          debugPrint(stack2.toString());
          _current = SoundscapeTrack.none;
        }
      }
    }
  }

  Future<void> stop() async {
    ++_operationSequence;
    _current = SoundscapeTrack.none;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('SoundscapeService stop error: $e');
    }
  }

  Future<void> toggle(SoundscapeTrack track) async {
    if (_current == track && isPlaying) {
      await stop();
    } else {
      await play(track);
    }
  }

  /// Only for overall application shutdown. Do NOT call from widget dispose.
  Future<void> dispose() async {
    try {
      _current = SoundscapeTrack.none;
      await _player.dispose();
    } catch (_) {}
  }
}
