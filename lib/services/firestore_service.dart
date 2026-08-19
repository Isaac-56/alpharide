import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final CollectionReference<Map<String, dynamic>> _users =
      FirebaseFirestore.instance.collection('users');

  User _requireUser() {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('A signed-in user is required for private data.');
    }

    return user;
  }

  DocumentReference<Map<String, dynamic>> userReference(
    String _,
  ) {
    return _users.doc(_requireUser().uid);
  }

  Future<bool> checkUserExists(
    String phoneNumber,
  ) async {
    try {
      final User user = _requireUser();
      final DocumentReference<Map<String, dynamic>> currentReference =
          _users.doc(user.uid);
      final DocumentSnapshot<Map<String, dynamic>> currentSnapshot =
          await currentReference.get();

      if (currentSnapshot.exists) {
        return true;
      }

      final String legacyKey = phoneNumber.trim();

      if (legacyKey.isEmpty || legacyKey == user.uid) {
        return false;
      }

      final DocumentReference<Map<String, dynamic>> legacyReference =
          _users.doc(legacyKey);
      final DocumentSnapshot<Map<String, dynamic>> legacySnapshot =
          await legacyReference.get();

      if (!legacySnapshot.exists) {
        return false;
      }

      await currentReference.set(
        <String, dynamic>{
          ...?legacySnapshot.data(),
          'uid': user.uid,
          'phoneNumber': user.phoneNumber ?? legacyKey,
          'migratedFromPhoneKey': legacyKey,
          'migratedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await _migrateKnownSubcollections(
        legacyReference,
        currentReference,
      );

      return true;
    } catch (error) {
      debugPrint('Unable to check whether the user exists: $error');
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
      final User user = _requireUser();

      await _users.doc(user.uid).set(
        <String, dynamic>{
          'uid': user.uid,
          'phoneNumber': user.phoneNumber ?? phoneNumber,
          'name': name.trim(),
          'photoUrl': photoUrl,
          'referralCode': referralCode?.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error) {
      debugPrint('Unable to save the user profile: $error');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUser(
    String phoneNumber,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await userReference(phoneNumber).get();

      return snapshot.data();
    } catch (error) {
      debugPrint('Unable to retrieve the user profile: $error');
      rethrow;
    }
  }

  Stream<Map<String, dynamic>?> watchUser(
    String phoneNumber,
  ) {
    return userReference(phoneNumber).snapshots().map(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) => snapshot.data(),
        );
  }

  Future<void> updateUserProfile(
    String phoneNumber, {
    required String name,
    String? email,
    String? emergencyPhone,
    String? photoUrl,
  }) async {
    final User user = _requireUser();

    await userReference(phoneNumber).set(
      <String, dynamic>{
        'uid': user.uid,
        'phoneNumber': user.phoneNumber ?? phoneNumber,
        'name': name.trim(),
        'email': email?.trim(),
        'emergencyPhone': emergencyPhone?.trim(),
        if (photoUrl != null) 'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteUserProfile(
    String phoneNumber,
  ) async {
    await userReference(phoneNumber).delete();
  }

  Future<void> submitFeedback({
    required String phoneNumber,
    required String topic,
    required String message,
  }) async {
    final User user = _requireUser();

    await _firestore.collection('app_feedback').add(
      <String, dynamic>{
        'userId': user.uid,
        'phoneNumber': user.phoneNumber ?? phoneNumber,
        'topic': topic,
        'message': message.trim(),
        'platform': 'passenger',
        'status': 'new',
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Stream<List<Map<String, dynamic>>> watchSavedPlaces(
    String phoneNumber,
  ) {
    return userReference(phoneNumber)
        .collection('saved_places')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_documentsToMaps);
  }

  Future<void> addSavedPlace(
    String phoneNumber, {
    required String label,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    await userReference(phoneNumber).collection('saved_places').add(
      <String, dynamic>{
        'label': label.trim(),
        'address': address.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> deleteSavedPlace(
    String phoneNumber,
    String placeId,
  ) async {
    await userReference(phoneNumber)
        .collection('saved_places')
        .doc(placeId)
        .delete();
  }

  Stream<List<Map<String, dynamic>>> watchNotifications(
    String phoneNumber,
  ) {
    return userReference(phoneNumber)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_documentsToMaps);
  }

  Future<void> markNotificationRead(
    String phoneNumber,
    String notificationId,
  ) async {
    await userReference(phoneNumber)
        .collection('notifications')
        .doc(notificationId)
        .set(
      <String, dynamic>{
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<List<Map<String, dynamic>>> watchOrders(
    String phoneNumber,
  ) {
    return userReference(phoneNumber)
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_documentsToMaps);
  }

  Stream<List<Map<String, dynamic>>> watchWalletTransactions(
    String phoneNumber,
  ) {
    return userReference(phoneNumber)
        .collection('wallet_transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_documentsToMaps);
  }

  Future<void> _migrateKnownSubcollections(
    DocumentReference<Map<String, dynamic>> legacyReference,
    DocumentReference<Map<String, dynamic>> currentReference,
  ) async {
    const List<String> subcollections = <String>[
      'saved_places',
      'notifications',
      'orders',
      'wallet_transactions',
    ];

    for (final String subcollection in subcollections) {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await legacyReference.collection(subcollection).get();

      for (final QueryDocumentSnapshot<Map<String, dynamic>> document
          in snapshot.docs) {
        await currentReference.collection(subcollection).doc(document.id).set(
              document.data(),
              SetOptions(merge: true),
            );
      }
    }
  }

  List<Map<String, dynamic>> _documentsToMaps(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map(
      (QueryDocumentSnapshot<Map<String, dynamic>> document) {
        return <String, dynamic>{
          'id': document.id,
          ...document.data(),
        };
      },
    ).toList(growable: false);
  }
}
