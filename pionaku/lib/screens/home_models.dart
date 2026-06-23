/// Home header / KPI context (optional override; defaults match session).
class HomeUserInfo {
  const HomeUserInfo({
    this.displayName = 'admin',
    this.role = 'Admin',
    this.airportCode = 'YIA',
    this.airportName = 'Concordia',
  });

  final String displayName;
  final String role;
  final String airportCode;
  final String airportName;

  String get roleAtAirport => '$role · $airportCode / $airportName';
}

enum KpiTrend { up, down, flat }

class HomeInsightFlightRoute {
  const HomeInsightFlightRoute({
    required this.flight,
    required this.passengers,
    required this.route,
    required this.changePercent,
  });
  final String flight;
  final int passengers;
  final String route;
  final double changePercent;
}

class HomeInsightScanPoint {
  const HomeInsightScanPoint({
    required this.scanPoint,
    required this.passengers,
    required this.percent,
    required this.workloadLabel,
  });
  final String scanPoint;
  final int passengers;
  final double percent;
  final String workloadLabel;
}

class HomeInsightHourlyFlowPoint {
  const HomeInsightHourlyFlowPoint({
    required this.hourLabel,
    required this.passengers,
  });
  final String hourLabel;
  final int passengers;
}
