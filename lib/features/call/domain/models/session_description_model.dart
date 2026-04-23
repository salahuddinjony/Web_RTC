class SessionDescriptionModel {
  // Constructor for creating a new SessionDescriptionModel
  const SessionDescriptionModel({
    required this.type,
    required this.sdp,
  });

  // The type of the session description (e.g. 'offer', 'answer')
  final String type;

  // The SDP (Session Description Protocol) of the session description
  final String sdp;

  // Convert the SessionDescriptionModel to a map
  Map<String, dynamic> toMap() => {'type': type, 'sdp': sdp};

  // Create a SessionDescriptionModel from a map
  factory SessionDescriptionModel.fromMap(Map<String, dynamic> map) {
    return SessionDescriptionModel(
      type: map['type'] as String? ?? '',
      sdp: map['sdp'] as String? ?? '',
    );
  }
}
