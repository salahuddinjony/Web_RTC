import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../data/signaling_repository.dart';
import '../../domain/models/call_role.dart';
import '../../domain/models/session_description_model.dart';
import 'call_controller_state.dart';
import 'media_track_helper.dart';
import 'rtc_call_config.dart';

class CallController extends ChangeNotifier {
  CallController({SignalingRepository? signalingRepository})
      : _signalingRepository = signalingRepository ?? SignalingRepository() {
    localRenderer.initialize();
    remoteRenderer.initialize();
  }

  final SignalingRepository _signalingRepository;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  String? _roomId;
  bool _hasRemoteDescription = false;

  StreamSubscription<SessionDescriptionModel?>? _answerSubscription;
  StreamSubscription<List<RTCIceCandidate>>? _remoteCandidateSubscription;
  final CallControllerState _state = CallControllerState();

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  final Set<String> _addedCandidateKeys = <String>{};

  bool get isLoading => _state.isLoading;
  String? get activeRoomId => _state.activeRoomId;
  String? get errorMessage => _state.errorMessage;
  bool get isMicMuted => _state.isMicMuted;
  bool get isCameraOff => _state.isCameraOff;
  String get peerConnectionState => _state.peerConnectionState;
  String get iceConnectionState => _state.iceConnectionState;
  String get iceGatheringState => _state.iceGatheringState;
  bool get isTurnConfigured => RtcCallConfig.isTurnConfigured;

  Future<void> createRoom() async {
    await _runGuarded(() async {
      await _resetSession();
      await _prepareConnection(role: CallRole.caller);

      // Create room ID first so early ICE candidates are not dropped.
      final provisionalRoomId = await _signalingRepository.createRoom(
        const SessionDescriptionModel(type: 'offer', sdp: ''),
      );
      _roomId = provisionalRoomId;
      _state.activeRoomId = provisionalRoomId;
      await _startRemoteCandidatesSubscription(CallRole.caller);

      // Caller creates SDP offer and updates the room document.
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      await _signalingRepository.updateOffer(
        roomId: provisionalRoomId,
        offer: SessionDescriptionModel(
          type: offer.type ?? 'offer',
          sdp: offer.sdp ?? '',
        ),
      );

      _answerSubscription?.cancel();
      _answerSubscription =
          _signalingRepository.watchAnswer(provisionalRoomId).listen((answer) async {
        if (answer == null || _hasRemoteDescription) return;
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(answer.sdp, answer.type),
        );
        _hasRemoteDescription = true;
        await _flushPendingCandidates();
      });
    });
  }

  Future<void> joinRoom(String roomId) async {
    await _runGuarded(() async {
      await _resetSession();
      _roomId = roomId;
      _state.activeRoomId = roomId;
      await _prepareConnection(role: CallRole.callee);
      await _startRemoteCandidatesSubscription(CallRole.callee);

      final offer = await _waitForValidOffer(roomId);
      if (offer == null) {
        throw Exception(
          'Room offer is not ready yet. Try again in 1-2 seconds.',
        );
      }

      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer.sdp, offer.type),
      );
      _hasRemoteDescription = true;

      // Callee replies with SDP answer after applying remote offer.
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await _signalingRepository.setAnswer(
        roomId: roomId,
        answer: SessionDescriptionModel(
          type: answer.type ?? 'answer',
          sdp: answer.sdp ?? '',
        ),
      );
      await _flushPendingCandidates();
    });
  }

  Future<SessionDescriptionModel?> _waitForValidOffer(String roomId) async {
    // The caller may create the room document before writing the final offer SDP.
    // Retry briefly so callee does not attempt setRemoteDescription with empty SDP.
    for (var attempt = 0; attempt < 12; attempt++) {
      final offer = await _signalingRepository.getOffer(roomId);
      if (offer != null && offer.sdp.trim().isNotEmpty) {
        return offer;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<void> hangUp() async {
    final roomToDelete = _roomId;
    await _resetSession();
    if (roomToDelete != null) {
      await _signalingRepository.deleteRoom(roomToDelete);
    }
  }

  Future<void> toggleMic() async {
    _state.isMicMuted = !_state.isMicMuted;
    _applyMediaTrackStates();
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    _state.isCameraOff = !_state.isCameraOff;
    _applyMediaTrackStates();
    notifyListeners();
  }

  Future<void> _prepareConnection({required CallRole role}) async {
    _peerConnection =
        await createPeerConnection(RtcCallConfig.peerConnectionConfiguration());
    _localStream = await navigator.mediaDevices.getUserMedia(
      RtcCallConfig.mediaConstraints,
    );
    localRenderer.srcObject = _localStream;
    _applyMediaTrackStates();

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        notifyListeners();
      }
    };

    _peerConnection!.onConnectionState = (state) {
      _state.peerConnectionState = state.name;
      notifyListeners();
    };

    _peerConnection!.onIceConnectionState = (state) {
      _state.iceConnectionState = state.name;
      notifyListeners();
    };

    _peerConnection!.onIceGatheringState = (state) {
      _state.iceGatheringState = state.name;
      notifyListeners();
    };

    _peerConnection!.onIceCandidate = (candidate) async {
      final room = _roomId;
      if (room == null || candidate.candidate == null) return;
      await _signalingRepository.addIceCandidate(
        roomId: room,
        role: role,
        candidate: candidate,
      );
    };
  }

  Future<void> _startRemoteCandidatesSubscription(CallRole role) async {
    final room = _roomId;
    if (room == null) return;

    await _remoteCandidateSubscription?.cancel();
    _remoteCandidateSubscription = _signalingRepository
        .watchRemoteCandidates(roomId: room, role: role)
        .listen((candidates) async {
      for (final candidate in candidates) {
        final key =
            '${candidate.candidate}|${candidate.sdpMid}|${candidate.sdpMLineIndex}';
        if (_addedCandidateKeys.contains(key)) continue;

        if (_hasRemoteDescription) {
          await _peerConnection?.addCandidate(candidate);
          _addedCandidateKeys.add(key);
        } else {
          _pendingRemoteCandidates.add(candidate);
        }
      }
    });
  }

  Future<void> _flushPendingCandidates() async {
    for (final candidate in _pendingRemoteCandidates) {
      final key =
          '${candidate.candidate}|${candidate.sdpMid}|${candidate.sdpMLineIndex}';
      if (_addedCandidateKeys.contains(key)) continue;
      await _peerConnection?.addCandidate(candidate);
      _addedCandidateKeys.add(key);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> _resetSession() async {
    await _answerSubscription?.cancel();
    await _remoteCandidateSubscription?.cancel();
    _answerSubscription = null;
    _remoteCandidateSubscription = null;

    for (final track in _localStream?.getTracks() ?? []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _peerConnection = null;

    remoteRenderer.srcObject = null;
    localRenderer.srcObject = null;

    _pendingRemoteCandidates.clear();
    _addedCandidateKeys.clear();
    _hasRemoteDescription = false;
    _roomId = null;
    _state.resetSessionState();
    notifyListeners();
  }

  void _applyMediaTrackStates() {
    MediaTrackHelper.applyLocalTrackState(
      stream: _localStream,
      isMicMuted: _state.isMicMuted,
      isCameraOff: _state.isCameraOff,
    );
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      _state.isLoading = true;
      _state.errorMessage = null;
      notifyListeners();
      await action();
    } catch (error) {
      _state.errorMessage = error.toString();
      if (kDebugMode) {
        // ignore: avoid_print
        print(_state.errorMessage);
      }
      notifyListeners();
    } finally {
      _state.isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _answerSubscription?.cancel();
    _remoteCandidateSubscription?.cancel();
    localRenderer.dispose();
    remoteRenderer.dispose();
    _peerConnection?.dispose();
    _localStream?.dispose();
    super.dispose();
  }
}
