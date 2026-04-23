import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../domain/models/call_role.dart';
import '../domain/models/ice_candidate_model.dart';
import '../domain/models/session_description_model.dart';

class SignalingRepository {
  SignalingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;


// Collection reference to the rooms collection
  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('rooms');

  Future<String> createRoom(SessionDescriptionModel offer) async {
    // Room document keeps offer/answer; sub-collections store ICE candidates.
    final roomRef = _rooms.doc();
    await roomRef.set({
      'createdAt': FieldValue.serverTimestamp(),
      'offer': offer.toMap(),
    });
    return roomRef.id;
  }

  Future<void> updateOffer({
    required String roomId,
    required SessionDescriptionModel offer,
  }) {
    return _rooms.doc(roomId).update({'offer': offer.toMap()});
  }

  Future<void> setAnswer({
    required String roomId,
    required SessionDescriptionModel answer,
  }) {
    return _rooms.doc(roomId).update({'answer': answer.toMap()});
  }
// Get the offer from the room
  Future<SessionDescriptionModel?> getOffer(String roomId) async {
    final snapshot = await _rooms.doc(roomId).get();
    final data = snapshot.data();
    if (data == null || data['offer'] == null) return null;
    return SessionDescriptionModel.fromMap(
      Map<String, dynamic>.from(data['offer'] as Map),
    );
  }

  // Watch the answer from the room
  Stream<SessionDescriptionModel?> watchAnswer(String roomId) {
    return _rooms.doc(roomId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null || data['answer'] == null) return null;
      return SessionDescriptionModel.fromMap(
        Map<String, dynamic>.from(data['answer'] as Map),
      );
    });
  }

// Add the ice candidate to the room
  Future<void> addIceCandidate({
    required String roomId,
    required CallRole role,
    required RTCIceCandidate candidate,
  }) {
    final collectionName =
        role == CallRole.caller ? 'callerCandidates' : 'calleeCandidates';
    final model = IceCandidateModel(
      candidate: candidate.candidate ?? '',
      sdpMid: candidate.sdpMid,
      sdpMLineIndex: candidate.sdpMLineIndex,
    );
    return _rooms.doc(roomId).collection(collectionName).add(model.toMap());
  }

  Stream<List<RTCIceCandidate>> watchRemoteCandidates({
    required String roomId,
    required CallRole role,
  }) {
    final collectionName =
        role == CallRole.caller ? 'calleeCandidates' : 'callerCandidates';
    return _rooms
        .doc(roomId)
        .collection(collectionName)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final model = IceCandidateModel.fromMap(doc.data());
        return RTCIceCandidate(
          model.candidate,
          model.sdpMid,
          model.sdpMLineIndex,
        );
      }).toList();
    });
  }

  Future<void> deleteRoom(String roomId) async {
    final roomRef = _rooms.doc(roomId);

    final callerCandidates = await roomRef.collection('callerCandidates').get();
    final calleeCandidates = await roomRef.collection('calleeCandidates').get();

    for (final doc in callerCandidates.docs) {
      await doc.reference.delete();
    }
    for (final doc in calleeCandidates.docs) {
      await doc.reference.delete();
    }
    await roomRef.delete();
  }
}
