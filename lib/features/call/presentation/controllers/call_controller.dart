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

  // StreamSubscription for the answer subscription
  StreamSubscription<SessionDescriptionModel?>? _answerSubscription;
  // StreamSubscription for the remote candidate subscription
  StreamSubscription<List<RTCIceCandidate>>? _remoteCandidateSubscription;
  // State for the call controller
  final CallControllerState _state = CallControllerState();

  // List of pending remote candidates
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  // Set of added candidate keys
  final Set<String> _addedCandidateKeys = <String>{};


// These are the getters for the call controller state are get the changes from the state
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
    // Run the guarded action
    await _runGuarded( () async {
      // Reset the session
      await _resetSession();
      // Prepare the connection
      await _prepareConnection(role: CallRole.caller);
      // Start the remote candidates subscription

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

// Update the offer means when the offer is created and set the local description then firestore update the offer with the offer sdp and type=offer
      await _signalingRepository.updateOffer(
        roomId: provisionalRoomId,
        offer: SessionDescriptionModel(
          type: offer.type ?? 'offer',
          sdp: offer.sdp ?? '',
        ),
      );
// Watch the answer from the room means when the answer is received from the remote peer
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
    // Run the guarded action
    await _runGuarded(() async {
      // Reset the session
      await _resetSession();
      _roomId = roomId;
      _state.activeRoomId = roomId;

      // Prepare the connection means when the connection is prepared then the connection is created and the local stream is added to the peer connection
      await _prepareConnection(role: CallRole.callee);

      // Start the remote candidates subscription means when the remote candidates are subscribed then the remote candidates are added to the peer connection
      await _startRemoteCandidatesSubscription(CallRole.callee);

      // Wait for the valid offer means when the offer is valid then the offer is set to the remote description
      final offer = await _waitForValidOffer(roomId);
      if (offer == null) {
        throw Exception(
          'Room offer is not ready yet. Try again in 1-2 seconds.',
        );
      }

// Set the remote description means when the remote description is set then the remote description is set to the peer connection
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer.sdp, offer.type),
      );
      _hasRemoteDescription = true;

      // Callee replies with SDP answer after applying remote offer.
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

// Set the answer means when the answer is set in the firestore in same room id then the answer is set to the peer connection
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

  // Wait for the valid offer means when the offer is valid then the offer is set to the remote description
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
    // Create the peer connection
    _peerConnection =
        await createPeerConnection(RtcCallConfig.peerConnectionConfiguration());
    // Get the local stream
    _localStream = await navigator.mediaDevices.getUserMedia(
      RtcCallConfig.mediaConstraints,
    );
    // Set the local stream to the local renderer
    localRenderer.srcObject = _localStream;
    // Apply the media track states
    _applyMediaTrackStates();
    // Notify listeners to update the UI
    notifyListeners();
    // Add the tracks to the peer connection-tracks means media tracks like audio and video

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
// On track means when the remote stream is added to the peer connection
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        notifyListeners();
      }
    };
// On connection state means when the connection state is changed
    _peerConnection!.onConnectionState = (state) {
      _state.peerConnectionState = state.name;
      notifyListeners();
    };
// On ice connection state means when the ice connection state is changed
    _peerConnection!.onIceConnectionState = (state) {
      _state.iceConnectionState = state.name;
      notifyListeners();
    };
// On ice gathering state means when the ice gathering state is changed
    _peerConnection!.onIceGatheringState = (state) {
      _state.iceGatheringState = state.name;
      notifyListeners();
    };
// On ice candidate means when the ice candidate is added to the peer connection
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
// Flush the pending candidates means when the remote candidate is added to the peer connection
  Future<void> _flushPendingCandidates() async {
    for (final candidate in _pendingRemoteCandidates) {
      // The key is the candidate id
      final key =
          '${candidate.candidate}|${candidate.sdpMid}|${candidate.sdpMLineIndex}';
      if (_addedCandidateKeys.contains(key)) continue;
      await _peerConnection?.addCandidate(candidate);
      _addedCandidateKeys.add(key);
    }
    _pendingRemoteCandidates.clear();
  }

// Reset the session means when the call is ended
  Future<void> _resetSession() async {  
    // Cancel the answer subscription
    await _answerSubscription?.cancel();
    // Cancel the remote candidate subscription
    await _remoteCandidateSubscription?.cancel();
    // Set the answer subscription to null
    _answerSubscription = null;
    // Set the remote candidate subscription to null
    _remoteCandidateSubscription = null;

    // Stop the local stream tracks
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
    // Apply the media track states
    MediaTrackHelper.applyLocalTrackState(
      // The local stream
      stream: _localStream,
      // The state of the microphone
      isMicMuted: _state.isMicMuted,
      // The state of the camera
      isCameraOff: _state.isCameraOff,
    );
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    try {
      _state.isLoading = true;
      _state.errorMessage = null;
      notifyListeners(); // Notify listeners to update the UI
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
