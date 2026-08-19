import 'address_model.dart';

class TripModel {
  final String id;
  final AddressModel pickup;
  final AddressModel destination;
  final String vehicleType;
  final double fare;
  final String paymentMethod;
  final String status;

  const TripModel({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.vehicleType,
    required this.fare,
    required this.paymentMethod,
    required this.status,
  });
}
