import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One audible alert per event, including duplicate push/live-feed deliveries.
class NotificationAlerts {
  static const MethodChannel _channel = MethodChannel('alpha/notifications');
  static final Set<String> _delivered = <String>{};

  static Future<void> show({
    required String eventId,
    required String title,
    required String body,
    bool urgent = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!_delivered.add(eventId)) return;
    if (_delivered.length > 200) _delivered.remove(_delivered.first);
    try {
      await _channel.invokeMethod<void>('show', <String, Object>{
        'eventId': eventId,
        'title': title,
        'body': body,
        'urgent': urgent,
      });
    } on PlatformException catch (error) {
      _delivered.remove(eventId);
      debugPrint('Notification alert unavailable: ${error.code}');
    } on MissingPluginException {
      _delivered.remove(eventId);
    }
  }
}
