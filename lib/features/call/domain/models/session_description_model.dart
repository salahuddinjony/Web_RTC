class SessionDescriptionModel {
  const SessionDescriptionModel({
    required this.type,
    required this.sdp,
  });

  final String type;
  final String sdp;

  Map<String, dynamic> toMap() => {'type': type, 'sdp': sdp};

  factory SessionDescriptionModel.fromMap(Map<String, dynamic> map) {
    return SessionDescriptionModel(
      type: map['type'] as String? ?? '',
      sdp: map['sdp'] as String? ?? '',
    );
  }
}
