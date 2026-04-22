import 'package:flutter_webrtc/flutter_webrtc.dart';

class MediaTrackHelper {
  MediaTrackHelper._();

  static void applyLocalTrackState({
    required MediaStream? stream,
    required bool isMicMuted,
    required bool isCameraOff,
  }) {
    if (stream == null) return;

    for (final audioTrack in stream.getAudioTracks()) {
      audioTrack.enabled = !isMicMuted;
    }
    for (final videoTrack in stream.getVideoTracks()) {
      videoTrack.enabled = !isCameraOff;
    }
  }
}
