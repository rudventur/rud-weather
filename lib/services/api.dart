import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/forecast.dart';
import '../models/news.dart';
import '../models/place.dart';
import 'metno.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Thin clients for the key-free data sources used by the app.
class WeatherApi {
  WeatherApi._();
  static final _client = http.Client();

  static Future<dynamic> _getJson(Uri uri, {Duration timeout = const Duration(seconds: 20)}) async {
    final res = await _client.get(uri).timeout(timeout);
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw ApiException('Unexpected response (${res.statusCode}) from ${uri.host}');
    }
    if (res.statusCode != 200) {
      final reason = body is Map && body['reason'] != null ? body['reason'] : 'HTTP ${res.statusCode}';
      throw ApiException('${uri.host}: $reason');
    }
    if (body is Map && body['error'] == true) throw ApiException('${uri.host}: ${body['reason']}');
    return body;
  }

  // ---------------- Open-Meteo forecast ----------------
  static const _current = 'temperature_2m,apparent_temperature,relative_humidity_2m,is_day,precipitation,weather_code,'
      'pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,uv_index';
  static const _hourly = 'temperature_2m,weather_code,is_day,precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m';
  static const _daily = 'weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_sum,'
      'precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant';

  /// Open-Meteo first; falls back to MET Norway if Open-Meteo fails (rate limit, outage, network).
  static Future<Forecast> forecast(Place place) async {
    try {
      return await _openMeteo(place);
    } catch (e) {
      try {
        return await MetNoApi.forecast(place);
      } catch (_) {
        rethrow;
      }
    }
  }

  static Future<Forecast> _openMeteo(Place place) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': place.lat.toStringAsFixed(4),
      'longitude': place.lon.toStringAsFixed(4),
      'current': _current,
      'hourly': _hourly,
      'daily': _daily,
      'timezone': 'auto',
      'forecast_days': '7',
      'forecast_hours': '48',
    });
    final j = await _getJson(uri) as Map<String, dynamic>;
    return Forecast.fromJson(place, j);
  }

  /// Current temperature / wind for many points in one request.
  static Future<List<GridPoint>> grid(List<(double, double)> pts) async {
    if (pts.isEmpty) return const [];
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': pts.map((p) => p.$1.toStringAsFixed(2)).join(','),
      'longitude': pts.map((p) => p.$2.toStringAsFixed(2)).join(','),
      'current': 'temperature_2m,wind_speed_10m,wind_direction_10m,weather_code',
      'forecast_days': '1',
    });
    final body = await _getJson(uri);
    final list = body is List ? body : [body];
    final out = <GridPoint>[];
    for (var k = 0; k < list.length && k < pts.length; k++) {
      final c = (list[k] as Map<String, dynamic>)['current'] as Map<String, dynamic>?;
      if (c == null) continue;
      double d(String key) => (c[key] as num?)?.toDouble() ?? double.nan;
      out.add(GridPoint(pts[k].$1, pts[k].$2, d('temperature_2m'), d('wind_speed_10m'), d('wind_direction_10m'),
          (c['weather_code'] as num?)?.toInt() ?? 0));
    }
    return out;
  }

  // ---------------- Geocoding ----------------
  static Future<List<Place>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': q, 'count': '10', 'language': 'en', 'format': 'json'});
    final j = await _getJson(uri) as Map<String, dynamic>;
    final results = (j['results'] as List?) ?? const [];
    return results.map((r) {
      final m = r as Map<String, dynamic>;
      return Place(
        name: m['name'] as String,
        region: m['admin1'] as String?,
        country: m['country'] as String?,
        lat: (m['latitude'] as num).toDouble(),
        lon: (m['longitude'] as num).toDouble(),
      );
    }).toList();
  }

  /// Reverse geocoding via OpenStreetMap Nominatim (used sparingly: on explicit taps only).
  static Future<Place> reverse(double lat, double lon) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse',
          {'format': 'jsonv2', 'lat': '$lat', 'lon': '$lon', 'zoom': '10', 'accept-language': 'en'});
      final j = await _getJson(uri, timeout: const Duration(seconds: 8)) as Map<String, dynamic>;
      final a = (j['address'] as Map?)?.cast<String, dynamic>() ?? const {};
      final name = (a['city'] ?? a['town'] ?? a['village'] ?? a['municipality'] ?? a['hamlet'] ?? a['county'] ?? j['name']) as String?;
      if (name == null || name.isEmpty) throw ApiException('no name');
      return Place(name: name, region: (a['state'] ?? a['region']) as String?, country: a['country'] as String?, lat: lat, lon: lon);
    } catch (_) {
      return Place(name: Place.coordLabel(lat, lon), lat: lat, lon: lon);
    }
  }

  // ---------------- NWS alerts (United States only) ----------------
  static Future<List<WeatherAlert>> usAlerts(double lat, double lon) async {
    if (lat < 17 || lat > 72 || lon > -64 || lon < -180) return const [];
    try {
      final uri = Uri.https('api.weather.gov', '/alerts/active', {'point': '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}'});
      final j = await _getJson(uri, timeout: const Duration(seconds: 10)) as Map<String, dynamic>;
      return ((j['features'] as List?) ?? const []).map((f) {
        final p = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
        return WeatherAlert(
          title: (p['headline'] ?? p['event'] ?? 'Weather alert') as String,
          description: (p['description'] ?? '') as String,
          severity: (p['severity'] ?? 'Unknown') as String,
          source: 'US National Weather Service',
          expires: p['expires'] == null ? null : DateTime.tryParse(p['expires'] as String)?.toLocal(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  // ---------------- News (generated hourly by GitHub Actions) ----------------
  static Future<NewsFeed> news() async {
    final bust = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final uri = Uri.base.resolve('news.json').replace(queryParameters: {'t': '$bust'});
    final j = await _getJson(uri) as Map<String, dynamic>;
    return NewsFeed.fromJson(j);
  }
}

// ---------------- RainViewer ----------------
class RadarFrame {
  final DateTime time;
  final String path;
  final bool nowcast;
  RadarFrame(this.time, this.path, this.nowcast);
}

class RainViewerData {
  final String host;
  final List<RadarFrame> radar;
  final List<RadarFrame> satellite;
  RainViewerData(this.host, this.radar, this.satellite);

  /// Colour scheme 2 = "Universal Blue"; options 1_1 = smoothed, snow shown.
  String radarUrl(RadarFrame f) => '$host${f.path}/256/{z}/{x}/{y}/2/1_1.png';
  String satelliteUrl(RadarFrame f) => '$host${f.path}/256/{z}/{x}/{y}/0/0_0.png';

  static Future<RainViewerData> load() async {
    final j = await WeatherApi._getJson(Uri.https('api.rainviewer.com', '/public/weather-maps.json')) as Map<String, dynamic>;
    List<RadarFrame> frames(List? l, bool nowcast) => (l ?? const [])
        .map((e) => RadarFrame(
            DateTime.fromMillisecondsSinceEpoch(((e as Map)['time'] as num).toInt() * 1000), e['path'] as String, nowcast))
        .toList();
    final radar = j['radar'] as Map<String, dynamic>? ?? const {};
    final sat = j['satellite'] as Map<String, dynamic>? ?? const {};
    return RainViewerData(
      j['host'] as String? ?? 'https://tilecache.rainviewer.com',
      [...frames(radar['past'] as List?, false), ...frames(radar['nowcast'] as List?, true)],
      frames(sat['infrared'] as List?, false),
    );
  }
}
