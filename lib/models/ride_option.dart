enum PaymentMethod {
  cash,
  card,
  wallet,
}

class RideOption {
  static const String currencyCode = 'SSP';
  static const int fareRounding = 500;

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

  String get estimatedFareLabel =>
      '${formatAmount(estimatedFare)} $currencyCode';

  String get minimumFareLabel => '${formatAmount(minimumFare)} $currencyCode';

  String get baseFareLabel => '${formatAmount(baseFare)} $currencyCode';

  String get perMinuteLabel => '${formatAmount(perMinute)} $currencyCode/min';

  String get perKilometerLabel =>
      '${formatAmount(perKilometer)} $currencyCode/km';

  int calculateFare({
    required double distanceKilometers,
    required double durationMinutes,
  }) {
    final double safeDistance =
        distanceKilometers < 0 ? 0.0 : distanceKilometers;
    final double safeDuration = durationMinutes < 0 ? 0.0 : durationMinutes;

    final double calculatedFare =
        baseFare + (safeDistance * perKilometer) + (safeDuration * perMinute);

    final int roundedFare =
        (calculatedFare / fareRounding).ceil() * fareRounding;

    return roundedFare < minimumFare ? minimumFare : roundedFare;
  }

  static String formatAmount(int amount) {
    final String digits = amount.abs().toString();
    final StringBuffer formatted = StringBuffer();

    for (int index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        formatted.write(',');
      }

      formatted.write(digits[index]);
    }

    return amount < 0 ? '-$formatted' : formatted.toString();
  }

  static const List<RideOption> options = <RideOption>[
    RideOption(
      id: 'boda',
      name: 'Alpha Boda',
      description: 'Fast and affordable for one passenger',
      assetPath: 'assets/images/vehicles/alpha_boda.png',
      seats: 1,
      estimatedFare: 10500,
      minimumFare: 4000,
      baseFare: 2500,
      perMinute: 200,
      perKilometer: 1500,
    ),
    RideOption(
      id: 'rickshaw',
      name: 'Alpha Rickshaw',
      description: 'Practical city rides for small groups',
      assetPath: 'assets/images/vehicles/alpha_rickshaw.png',
      seats: 3,
      estimatedFare: 14000,
      minimumFare: 6000,
      baseFare: 3500,
      perMinute: 250,
      perKilometer: 2100,
    ),
    RideOption(
      id: 'standard',
      name: 'Alpha Standard',
      description: 'Affordable everyday car rides',
      assetPath: 'assets/images/vehicles/alpha_standard.png',
      seats: 4,
      estimatedFare: 24000,
      minimumFare: 10000,
      baseFare: 6000,
      perMinute: 450,
      perKilometer: 3600,
    ),
    RideOption(
      id: 'comfort',
      name: 'Alpha Comfort',
      description: 'Extra comfort and newer cars',
      assetPath: 'assets/images/vehicles/alpha_comfort.png',
      seats: 4,
      estimatedFare: 30000,
      minimumFare: 12000,
      baseFare: 7500,
      perMinute: 500,
      perKilometer: 4600,
    ),
    RideOption(
      id: 'ev',
      name: 'Alpha EV',
      description: 'A quiet, lower-emission ride',
      assetPath: 'assets/images/vehicles/alpha_ev.png',
      seats: 4,
      estimatedFare: 32000,
      minimumFare: 13000,
      baseFare: 8000,
      perMinute: 500,
      perKilometer: 5000,
      isElectric: true,
    ),
    RideOption(
      id: 'premium',
      name: 'Alpha Premium',
      description: 'Luxury vehicles and top drivers',
      assetPath: 'assets/images/vehicles/alpha_premium.png',
      seats: 5,
      estimatedFare: 42000,
      minimumFare: 18000,
      baseFare: 11000,
      perMinute: 700,
      perKilometer: 6350,
    ),
  ];
}
