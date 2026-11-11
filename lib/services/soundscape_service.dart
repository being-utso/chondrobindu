import 'package:audioplayers/audioplayers.dart';

enum SoundscapeTrack {
  none,
  rainfall,
  heavyRain,
  brownNoise,
  cafeAmbiance,
  forestBirds,
}

class SoundscapeService {
  final AudioPlayer _player = AudioPlayer();
  SoundscapeTrack _current = SoundscapeTrack.none;
  double _volume = 0.65;

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
    } catch (_) {}
  }

  Future<void> play(SoundscapeTrack track) async {
    if (track == SoundscapeTrack.none) {
      await stop();
      return;
    }
    try {
      if (_current == track && isPlaying) return;
      await _player.stop();
      _current = track;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_volume);
      await _player.play(AssetSource(_assetPath(track)));
    } catch (e) {
      _current = SoundscapeTrack.none;
    }
  }

  Future<void> stop() async {
    _current = SoundscapeTrack.none;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> toggle(SoundscapeTrack track) async {
    if (_current == track && isPlaying) {
      await stop();
    } else {
      await play(track);
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
