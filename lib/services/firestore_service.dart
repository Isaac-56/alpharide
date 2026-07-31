import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final CollectionReference<Map<String, dynamic>> _users =
      FirebaseFirestore.instance.collection('users');

  Future<bool> checkUserExists(
    String phoneNumber,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _users.doc(phoneNumber).get();

      return snapshot.exists;
    } catch (error) {
      debugPrint(
        'Unable to check whether the user exists: $error',
      );

      rethrow;
    }
  }

  Future<void> addUser(
    String phoneNumber,
    String name, {
    String? photoUrl,
    String? referralCode,
  }) async {
    try {
      await _users.doc(phoneNumber).set(
        {
          'phoneNumber': phoneNumber,
          'name': name.trim(),
          'photoUrl': photoUrl,
          'referralCode': referralCode?.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error) {
      debugPrint(
        'Unable to save the user profile: $error',
      );

      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUser(
    String phoneNumber,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _users.doc(phoneNumber).get();

      return snapshot.data();
    } catch (error) {
      debugPrint(
        'Unable to retrieve the user profile: $error',
      );

      rethrow;
    }
  }
}
