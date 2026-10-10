import 'package:cloud_firestore/cloud_firestore.dart';

const Set<String> passengerHistoryStatuses = <String>{
  'completed',
  'cancelled',
  'expired',
};

Map<String, dynamic>? liveRideToOrderHistory({
  required String rideId,
  required Map<String, dynamic> data,
}) {
  final String status = data['status']?.toString().trim().toLowerCase() ?? '';
  if (!passengerHistoryStatuses.contains(status)) return null;

  final Map<String, dynamic> pickup = _stringMap(data['pickup']);
  final Map<String, dynamic> destination = _stringMap(data['destination']);
  final int? estimatedFare = _integer(data['estimatedFare']);
  final int? finalFare = _integer(data['finalFare']);
  final Timestamp? activityAt = _firstTimestamp(<Object?>[
    data['completedAt'],
    data['cancelledAt'],
    data['expiredAt'],
    data['updatedAt'],
    data['requestedAt'],
  ]);

  return <String, dynamic>{
    'id': rideId,
    'status': status,
    'fare': finalFare ?? estimatedFare,
    'currencyCode': data['currencyCode']?.toString() ?? 'SSP',
    'pickupAddress': pickup['address']?.toString() ?? '',
    'destinationAddress': destination['address']?.toString() ?? '',
    'rideOptionId': data['rideOptionId']?.toString() ?? '',
    'paymentMethod': data['paymentMethod']?.toString() ?? '',
    'createdAt': activityAt,
  };
}

List<Map<String, dynamic>> sortRideHistoryNewestFirst(
  Iterable<Map<String, dynamic>> rides,
) {
  final List<Map<String, dynamic>> result = rides.toList(growable: false);
  result.sort((Map<String, dynamic> first, Map<String, dynamic> second) {
    final Timestamp? firstTime = first['createdAt'] as Timestamp?;
    final Timestamp? secondTime = second['createdAt'] as Timestamp?;
    final int firstMs = firstTime?.millisecondsSinceEpoch ?? 0;
    final int secondMs = secondTime?.millisecondsSinceEpoch ?? 0;
    return secondMs.compareTo(firstMs);
  });
  return result;
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

Timestamp? _firstTimestamp(Iterable<Object?> values) {
  for (final Object? value in values) {
    if (value is Timestamp) return value;
  }
  return null;
}
