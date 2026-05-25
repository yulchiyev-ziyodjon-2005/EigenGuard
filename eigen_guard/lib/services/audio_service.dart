import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';

/// AudioService — Sanoat muhitida mikrofon orqali tovush (PCM) yozib olish
/// C++ FftProcessor ga spektral tahlil qilish uchun yuboriladi
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSub;
  bool _isRecording = false;

  // Real vaqt kadrlar - Uint8List kabi oqimni tarqatuvchi listener
  Function(Uint8List)? onAudioFrame;

  Future<void> initialize() async {
    final status = await _recorder.hasPermission();
    if (!status) {
      throw FileSystemException("Mikrofon uchun huquq berilmadi!");
    }
  }

  Future<void> startStream({required Function(Uint8List) onFrameData}) async {
    if (_isRecording) return;

    onAudioFrame = onFrameData;

    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      ));

      _audioStreamSub = stream.listen((data) {
        if (onAudioFrame != null) {
          onAudioFrame!(data);
        }
      });

      _isRecording = true;
    } catch (e) {
      throw Exception('Audio stream boshlash xatosi: $e');
    }
  }

  Future<void> stopStream() async {
    if (!_isRecording) return;

    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    await _recorder.stop();
    _isRecording = false;
    onAudioFrame = null;
  }

  void dispose() {
    stopStream();
    _recorder.dispose();
  }
}
