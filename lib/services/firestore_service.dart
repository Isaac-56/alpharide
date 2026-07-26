import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<bool> checkUserExists(String phoneNumber) async {
    try {
      final userSnapshot = await _db.collection('users').doc(phoneNumber).get();
      return userSnapshot.exists;
    } catch (e) {
      print('Error checking if user exists: $e');
      return false;
    }
  }

  Future<void> addUser(String phoneNumber, String name, {String? photoUrl, String? referralCode}) async {
    try {
      await _db.collection('users').doc(phoneNumber).set({
        'phoneNumber': phoneNumber,
        'name': name,
        'photoUrl': photoUrl,
        'referralCode': referralCode,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error adding user: $e');
      throw e; // Re-throw the error to be caught in the calling function
    }
  }

  Future<Map<String, dynamic>?> getUser(String phoneNumber) async {
    try {
      final userSnapshot = await _db.collection('users').doc(phoneNumber).get();
      return userSnapshot.data();
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }
}