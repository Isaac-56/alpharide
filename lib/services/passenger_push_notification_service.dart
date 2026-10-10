import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_alerts.dart';

class PassengerPushNotificationService {
  static final PassengerPushNotificationService instance =
      PassengerPushNotificationService();
  StreamSubscription<User?>? _auth;
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _messages;
  Future<void> _authWork = Future<void>.value();
  String? _uid;
  String? _token;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'africa-south1',
  );

  void bindAuthentication() {
    if (kIsWeb || _auth != null || _messages != null) return;
    _messages = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (_uid == null || FirebaseAuth.instance.currentUser?.uid != _uid)
        return;
      unawaited(
        NotificationAlerts.show(
          eventId:
              message.data['eventId'] ??
              message.messageId ??
              'update:${message.sentTime}',
          title: message.notification?.title ?? 'Alpha Ride update',
          body: message.notification?.body ?? '',
          urgent: message.data['type'] == 'ride_update',
        ),
      );
    });
    _auth = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _uid = user?.uid;
      _authWork = _authWork.then((_) => _setUser(user)).catchError((
        Object error,
      ) {
        debugPrint('Unable to update passenger notifications: $error');
      });
    });
  }

  Future<void> _setUser(User? user) async {
    if (FirebaseAuth.instance.currentUser?.uid != user?.uid) return;
    await _tokens?.cancel();
    _tokens = null;
    if (user == null) {
      // Remove the installation token so a signed-out phone receives no private updates.
      _token = null;
      await FirebaseMessaging.instance.deleteToken().catchError((Object error) {
        debugPrint('Unable to remove passenger push token: $error');
      });
      return;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      final NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied ||
          _uid != user.uid)
        return;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      final String? token = await messaging.getToken();
      if (token != null) await _register(user.uid, token);
      if (_uid != user.uid) return;
      _tokens = messaging.onTokenRefresh.listen((String token) {
        unawaited(
          _register(user.uid, token).catchError((Object error) {
            debugPrint('Unable to refresh passenger notifications: $error');
          }),
        );
      });
    } on Object catch (error) {
      debugPrint('Unable to enable passenger notifications: $error');
    }
  }

  Future<void> _register(String uid, String token) async {
    if (_uid != uid ||
        FirebaseAuth.instance.currentUser?.uid != uid ||
        _token == token)
      return;
    await _functions.httpsCallable('registerPassengerPushToken').call<void>(
      <String, dynamic>{'token': token},
    );
    if (_uid == uid) _token = token;
  }
}
