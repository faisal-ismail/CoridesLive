import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

class AudioHandler {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSubscription;
  
  bool _isInit = false;

  Future<void> init() async {
    if (_isInit) return;
    FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
    FlutterPcmSound.start();
    _isInit = true;
  }

  Future<void> startRecording(Function(Uint8List) onData) async {
    if (await _recorder.hasPermission()) {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ));

      _recordSubscription = stream.listen((data) {
        onData(data);
      });
    }
  }

  void stopRecording() {
    _recorder.stop();
    _recordSubscription?.cancel();
  }

  void feedAudio(Uint8List bytes) {
    if (!_isInit) return;
    // Gemini returns 24kHz PCM 16-bit mono
    final samples = Int16List.view(bytes.buffer);
    FlutterPcmSound.feed(PcmArrayInt16.fromList(samples));
  }

  void clearBuffer() {
    // Re-setup clears the current buffer
    FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
    FlutterPcmSound.start();
  }

  double calculateRMS(Uint8List data) {
    if (data.isEmpty) return 0.0;
    double sum = 0;
    for (int i = 0; i < data.length; i += 2) {
      if (i + 1 < data.length) {
        int sample = (data[i + 1] << 8) | data[i];
        if (sample > 32767) sample -= 65536;
        sum += sample * sample;
      }
    }
    double rms = sqrt(sum / (data.length / 2));
    return (rms / 3000).clamp(0.0, 1.0);
  }

  void dispose() {
    _recorder.dispose();
    _recordSubscription?.cancel();
    // In flutter_pcm_sound 3.x, explicit stop is not available or handled internally.
  }
}
