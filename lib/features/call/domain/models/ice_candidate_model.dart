class IceCandidateModel {
  const IceCandidateModel({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  // This method is used to convert the IceCandidateModel to a map
  Map<String, dynamic> toMap() {
    return {
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
    };
  }

// This method is used to create a IceCandidateModel from a map
  factory IceCandidateModel.fromMap(Map<String, dynamic> map) {
    return IceCandidateModel(
      candidate: map['candidate'] as String? ?? '',
      sdpMid: map['sdpMid'] as String?,
      sdpMLineIndex: map['sdpMLineIndex'] as int?,
    );
  }
}
