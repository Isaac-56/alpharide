enum PaymentMethod {
  cash,
  card,
  wallet,
}

class RideOption {
  final String id;
  final String name;
  final String description;
  final String assetPath;
  final int seats;
  final int estimatedFare;
  final int minimumFare;
  final int baseFare;
  final int perMinute;
  final int perKilometer;
  final bool isElectric;

  const RideOption({
    required this.id,
    required this.name,
    required this.description,
    required this.assetPath,
    required this.seats,
    required this.estimatedFare,
    required this.minimumFare,
    required this.baseFare,
    required this.perMinute,
    required this.perKilometer,
    this.isElectric = false,
  });

  static const List<RideOption> options = [
    RideOption(
      id: 'standard',
      name: 'Alpha Standard',
      description: 'Affordable everyday rides',
      assetPath: 'assets/images/vehicles/alpha_standard.png',
      seats: 4,
      estimatedFare: 520,
      minimumFare: 80,
      baseFare: 110,
      perMinute: 6,
      perKilometer: 24,
    ),
    RideOption(
      id: 'comfort',
      name: 'Alpha Comfort',
      description: 'Extra comfort and newer cars',
      assetPath: 'assets/images/vehicles/alpha_comfort.png',
      seats: 4,
      estimatedFare: 650,
      minimumFare: 100,
      baseFare: 145,
      perMinute: 7,
      perKilometer: 28,
    ),
    RideOption(
      id: 'ev',
      name: 'Alpha EV',
      description: 'A quiet, lower-emission ride',
      assetPath: 'assets/images/vehicles/alpha_ev.png',
      seats: 4,
      estimatedFare: 700,
      minimumFare: 110,
      baseFare: 155,
      perMinute: 7,
      perKilometer: 29,
      isElectric: true,
    ),
    RideOption(
      id: 'premium',
      name: 'Alpha Premium',
      description: 'Luxury vehicles and top drivers',
      assetPath: 'assets/images/vehicles/alpha_premium.png',
      seats: 5,
      estimatedFare: 940,
      minimumFare: 180,
      baseFare: 240,
      perMinute: 11,
      perKilometer: 40,
    ),
  ];
}
