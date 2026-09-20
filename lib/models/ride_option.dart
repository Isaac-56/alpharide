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
  final int? estimatedFare;
  final int minimumFare;
  final int baseFare;
  final int waitingPerMinute;
  final int perKilometer;
  final bool isElectric;
  final bool isCorporate;

  const RideOption({
    required this.id,
    required this.name,
    required this.description,
    required this.assetPath,
    required this.seats,
    this.estimatedFare,
    required this.minimumFare,
    required this.baseFare,
    required this.waitingPerMinute,
    required this.perKilometer,
    this.isElectric = false,
    this.isCorporate = false,
  });

  String get estimatedFareLabel => estimatedFare == null
      ? 'Fare after destination'
      : '${formatAmount(estimatedFare!)} $currencyCode';

  String get minimumFareLabel => '${formatAmount(minimumFare)} $currencyCode';

  String get baseFareLabel => '${formatAmount(baseFare)} $currencyCode';

  String get waitingPerMinuteLabel =>
      '${formatAmount(waitingPerMinute)} $currencyCode/min';

  String get perKilometerLabel =>
      '${formatAmount(perKilometer)} $currencyCode/km';

  int calculateFare({
    required double distanceKilometers,
  }) {
    final double safeDistance =
        distanceKilometers < 0 ? 0.0 : distanceKilometers;

    final double calculatedFare =
        baseFare + (safeDistance * perKilometer);

    final int roundedFare =
        (calculatedFare / fareRounding).ceil() * fareRounding;

    return roundedFare < minimumFare ? minimumFare : roundedFare;
  }

  RideOption withEstimatedFare(int fare) {
    if (fare <= 0) {
      throw ArgumentError.value(fare, 'fare', 'Fare must be positive.');
    }
    return RideOption(
      id: id,
      name: name,
      description: description,
      assetPath: assetPath,
      seats: seats,
      estimatedFare: fare,
      minimumFare: minimumFare,
      baseFare: baseFare,
      waitingPerMinute: waitingPerMinute,
      perKilometer: perKilometer,
      isElectric: isElectric,
      isCorporate: isCorporate,
    );
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
      minimumFare: 4000,
      baseFare: 2500,
      waitingPerMinute: 200,
      perKilometer: 1500,
    ),
    RideOption(
      id: 'rickshaw',
      name: 'Alpha Rickshaw',
      description: 'Practical city rides for small groups',
      assetPath: 'assets/images/vehicles/alpha_rickshaw.png',
      seats: 3,
      minimumFare: 6000,
      baseFare: 3500,
      waitingPerMinute: 250,
      perKilometer: 2100,
    ),
    RideOption(
      id: 'standard',
      name: 'Alpha Standard',
      description: 'Affordable everyday car rides',
      assetPath: 'assets/images/vehicles/alpha_standard.png',
      seats: 4,
      minimumFare: 10000,
      baseFare: 6000,
      waitingPerMinute: 450,
      perKilometer: 3600,
    ),
    RideOption(
      id: 'comfort',
      name: 'Alpha Comfort',
      description: 'Extra comfort and newer cars',
      assetPath: 'assets/images/vehicles/alpha_comfort.png',
      seats: 4,
      minimumFare: 12000,
      baseFare: 7500,
      waitingPerMinute: 500,
      perKilometer: 4600,
    ),
    RideOption(
      id: 'ev',
      name: 'Alpha EV',
      description: 'A quiet, lower-emission ride',
      assetPath: 'assets/images/vehicles/alpha_ev.png',
      seats: 4,
      minimumFare: 13000,
      baseFare: 8000,
      waitingPerMinute: 500,
      perKilometer: 5000,
      isElectric: true,
    ),
    RideOption(
      id: 'premium',
      name: 'Alpha Premium',
      description: 'Luxury vehicles and top drivers',
      assetPath: 'assets/images/vehicles/alpha_premium.png',
      seats: 5,
      minimumFare: 18000,
      baseFare: 11000,
      waitingPerMinute: 700,
      perKilometer: 6350,
    ),
    RideOption(
      id: 'corporate',
      name: 'Alpha Corporate',
      description: 'Executive rides for business and hotel transfers',
      assetPath: 'assets/images/vehicles/alpha_corporate.png',
      seats: 4,
      minimumFare: 20000,
      baseFare: 12000,
      waitingPerMinute: 750,
      perKilometer: 7500,
      isCorporate: true,
    ),
  ];
}