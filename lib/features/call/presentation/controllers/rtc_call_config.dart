class RtcCallConfig {
  RtcCallConfig._();

  static const String _turnUrl = String.fromEnvironment(
    'TURN_URL',
    defaultValue: 'turn:openrelay.metered.ca:80',
  );
  static const String _turnUsername = String.fromEnvironment(
    'TURN_USERNAME',
    defaultValue: 'openrelayproject',
  );
  static const String _turnCredential = String.fromEnvironment(
    'TURN_CREDENTIAL',
    defaultValue: 'openrelayproject',
  );

  static bool get isTurnConfigured => _turnUrl.isNotEmpty;

  static Map<String, dynamic> peerConnectionConfiguration() {
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];

    final turnUrls = <String>{
      _turnUrl,
      'turn:openrelay.metered.ca:443',
      'turn:openrelay.metered.ca:443?transport=tcp',
    }.where((url) => url.isNotEmpty).toList();

    if (turnUrls.isNotEmpty) {
      iceServers.add({
        'urls': turnUrls,
        'username': _turnUsername,
        'credential': _turnCredential,
      });
    }

    return {'iceServers': iceServers};
  }

  static const Map<String, dynamic> mediaConstraints = {
    'audio': true,
    'video': {
      'facingMode': 'user',
      'width': {'ideal': 1280},
      'height': {'ideal': 720},
      'frameRate': {'ideal': 30},
    },
  };
}
