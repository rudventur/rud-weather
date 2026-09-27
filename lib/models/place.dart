/// A named geographic location.
class Place {
  final String name;
  final String? region;
  final String? country;
  final double lat;
  final double lon;

  const Place({required this.name, required this.lat, required this.lon, this.region, this.country});

  static const london = Place(name: 'London', region: 'England', country: 'United Kingdom', lat: 51.5085, lon: -0.1257);

  String get subtitle => [region, country].where((s) => s != null && s.isNotEmpty).join(', ');

  String get key => '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';

  Place copyWith({String? name, String? region, String? country}) =>
      Place(name: name ?? this.name, region: region ?? this.region, country: country ?? this.country, lat: lat, lon: lon);

  Map<String, dynamic> toJson() => {'name': name, 'region': region, 'country': country, 'lat': lat, 'lon': lon};

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        name: j['name'] as String? ?? 'Unknown',
        region: j['region'] as String?,
        country: j['country'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );

  static String coordLabel(double lat, double lon) =>
      '${lat.abs().toStringAsFixed(2)}°${lat >= 0 ? 'N' : 'S'}, ${lon.abs().toStringAsFixed(2)}°${lon >= 0 ? 'E' : 'W'}';
}
