// this class is used to store the state of the call controller its work like a state management system which is used to store the state of the call controller
class CallControllerState {
  bool isLoading = false;
  String? activeRoomId;
  String? errorMessage;
  bool isMicMuted = true;
  bool isCameraOff = false;
  String peerConnectionState = 'idle';
  String iceConnectionState = 'new';
  String iceGatheringState = 'new';

  void resetSessionState() {
    activeRoomId = null;
    errorMessage = null;
    isMicMuted = true;
    isCameraOff = false;
    peerConnectionState = 'idle';
    iceConnectionState = 'new';
    iceGatheringState = 'new';
  }
}
