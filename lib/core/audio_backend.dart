import 'package:flutter/foundation.dart';
import 'models.dart';

abstract class AudioBackend extends ChangeNotifier {
  String? get lastError;
  bool get isPlaying;
  bool get isBuffering;
  Duration get position;
  Duration get duration;
  double get volume;
  List<double> get eqFrequencies;
  ValueListenable<List<double>> get spectrum;
  Stream<void> get completed;
  Future<void> initialize();
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  void setVolume(double volume);
  void setEqualizer(bool enabled, List<double> gainsDb);
  void setVisualizationEnabled(bool enabled);
}
