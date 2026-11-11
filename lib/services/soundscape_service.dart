import 'package:audioplayers/audioplayers.dart';

enum SoundscapeTrack { none, rainfall, libraryHall, brownNoise }

class SoundscapeService {
  final AudioPlayer _player = AudioPlayer();
  SoundscapeTrack _current = SoundscapeTrack.none;

  bool get isPlaying => _current != SoundscapeTrack.none;
  SoundscapeTrack get currentTrack => _current;

  static String _assetPath(SoundscapeTrack track) => switch (track) {
        SoundscapeTrack.rainfall => 'noises/Rainfall.mp3',
        SoundscapeTrack.libraryHall => 'noises/Library_Hall.mp3',
        SoundscapeTrack.brownNoise => 'noises/Brown_Noise.mp3',
        SoundscapeTrack.none => '',
      };

  static SoundscapeTrack fromLabel(String label) => switch (label) {
        'Rainfall' => SoundscapeTrack.rainfall,
        'Library Hall' => SoundscapeTrack.libraryHall,
        'Brown Noise' => SoundscapeTrack.brownNoise,
        _ => SoundscapeTrack.none,
      };

  static String toLabel(SoundscapeTrack track) => switch (track) {
        SoundscapeTrack.rainfall => 'Rainfall',
        SoundscapeTrack.libraryHall => 'Library Hall',
        SoundscapeTrack.brownNoise => 'Brown Noise',
        SoundscapeTrack.none => 'None',
      };

  Future<void> play(SoundscapeTrack track) async {
    if (track == SoundscapeTrack.none) {
      await stop();
      return;
    }
    if (_current == track && isPlaying) return;
    await _player.stop();
    _current = track;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(0.65);
    await _player.play(AssetSource(_assetPath(track)));
  }

  Future<void> stop() async {
    _current = SoundscapeTrack.none;
    await _player.stop();
  }

  Future<void> toggle(SoundscapeTrack track) async {
    if (_current == track && isPlaying) {
      await stop();
    } else {
      await play(track);
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
