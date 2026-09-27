import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/forecast.dart';
import '../models/place.dart';

/// Fallback forecast source: MET Norway Locationforecast 2.0 (key-free, global, CORS enabled).
/// Used automatically when Open-Meteo is unavailable (e.g. its per-IP daily limit is reached).
class MetNoApi {
  static Future<Forecast> forecast(Place place) async {
    final uri = Uri.https('api.met.no', '/weatherapi/locationforecast/2.0/complete',
        {'lat': place.lat.toStringAsFixed(4), 'lon': place.lon.toStringAsFixed(4)});
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('api.met.no: HTTP ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final ts = ((j['properties'] as Map)['timeseries'] as List).cast<Map<String, dynamic>>();
    if (ts.isEmpty) throw Exception('api.met.no: empty forecast');

    double n(Map? m, String k) => (m?[k] as num?)?.toDouble() ?? double.nan;
    final now = DateTime.now().toUtc();

    // Parse entries.
    final entries = <_E>[];
    for (final t in ts) {
      final time = DateTime.parse(t['time'] as String);
      final data = t['data'] as Map<String, dynamic>;
      final inst = (data['instant'] as Map)['details'] as Map?;
      final n1 = data['next_1_hours'] as Map?;
      final n6 = data['next_6_hours'] as Map?;
      final n12 = data['next_12_hours'] as Map?;
      final sym1 = (n1?['summary'] as Map?)?['symbol_code'] as String?;
      final sym6 = (n6?['summary'] as Map?)?['symbol_code'] as String?;
      final sym12 = (n12?['summary'] as Map?)?['symbol_code'] as String?;
      entries.add(_E(
        time: time,
        temp: n(inst, 'air_temperature'),
        feels: n(inst, 'apparent_air_temperature'),
        humidity: n(inst, 'relative_humidity'),
        pressure: n(inst, 'air_pressure_at_sea_level'),
        wind: n(inst, 'wind_speed') * 3.6,
        gust: n(inst, 'wind_speed_of_gust') * 3.6,
        windDir: n(inst, 'wind_from_direction'),
        cloud: n(inst, 'cloud_area_fraction'),
        uv: n(inst, 'ultraviolet_index_clear_sky'),
        sym: sym1 ?? sym6 ?? sym12,
        sym6: sym6 ?? sym12 ?? sym1,
        hourly: n1 != null,
        precip1: n(n1?['details'] as Map?, 'precipitation_amount'),
        precip6: n(n6?['details'] as Map?, 'precipitation_amount'),
        prob1: n(n1?['details'] as Map?, 'probability_of_precipitation'),
        prob6: n(n6?['details'] as Map?, 'probability_of_precipitation'),
        tMax6: n(n6?['details'] as Map?, 'air_temperature_max'),
        tMin6: n(n6?['details'] as Map?, 'air_temperature_min'),
      ));
    }

    // Current = latest entry not in the future (or the first one).
    final cur = entries.lastWhere((e) => !e.time.isAfter(now), orElse: () => entries.first);
    final curSun = sunTimes(DateTime.now(), place.lat, place.lon);
    final curIsDay = _isDay(cur.sym, now, curSun);
    final current = CurrentWeather(
      time: cur.time.toLocal(),
      temp: cur.temp,
      feelsLike: cur.feels.isNaN ? cur.temp : cur.feels,
      humidity: cur.humidity,
      precipitation: cur.precip1.isNaN ? 0 : cur.precip1,
      pressure: cur.pressure,
      windSpeed: cur.wind,
      windDir: cur.windDir,
      windGusts: cur.gust,
      cloudCover: cur.cloud,
      uv: cur.uv,
      code: symbolToWmo(cur.sym),
      isDay: curIsDay,
    );

    // Hourly for 48 h from the current hour.
    final hourly = <HourPoint>[];
    for (final e in entries.where((e) => e.hourly && !e.time.isBefore(cur.time)).take(48)) {
      final local = e.time.toLocal();
      final sun = sunTimes(local, place.lat, place.lon);
      hourly.add(HourPoint(local, e.temp, symbolToWmo(e.sym), _isDay(e.sym, e.time, sun), e.prob1, e.precip1.isNaN ? 0 : e.precip1, e.wind, e.windDir));
    }

    // Daily aggregation by device-local date.
    final byDay = <DateTime, List<_E>>{};
    for (final e in entries) {
      final l = e.time.toLocal();
      byDay.putIfAbsent(DateTime(l.year, l.month, l.day), () => []).add(e);
    }
    final daily = <DayPoint>[];
    for (final day in byDay.keys.toList()..sort()) {
      if (daily.length >= 7) break;
      final es = byDay[day]!;
      double maxOf(Iterable<double> v) => v.where((x) => !x.isNaN).fold(double.nan, (a, b) => a.isNaN || b > a ? b : a);
      double minOf(Iterable<double> v) => v.where((x) => !x.isNaN).fold(double.nan, (a, b) => a.isNaN || b < a ? b : a);
      final tMax = maxOf([...es.map((e) => e.temp), ...es.map((e) => e.tMax6)]);
      final tMin = minOf([...es.map((e) => e.temp), ...es.map((e) => e.tMin6)]);
      var precip = 0.0;
      for (final e in es) {
        precip += e.hourly ? (e.precip1.isNaN ? 0 : e.precip1) : (e.precip6.isNaN ? 0 : e.precip6);
      }
      final noon = es.reduce((a, b) => (a.time.toLocal().hour - 12).abs() <= (b.time.toLocal().hour - 12).abs() ? a : b);
      final windiest = es.reduce((a, b) => (b.wind.isNaN ? -1 : b.wind) > (a.wind.isNaN ? -1 : a.wind) ? b : a);
      final sun = sunTimes(day, place.lat, place.lon);
      daily.add(DayPoint(
        day,
        symbolToWmo(noon.sym6 ?? noon.sym),
        tMax,
        tMin,
        sun.$1,
        sun.$2,
        maxOf(es.map((e) => e.uv)),
        precip,
        maxOf([...es.map((e) => e.prob1), ...es.map((e) => e.prob6)]),
        windiest.wind,
        windiest.windDir,
      ));
    }

    return Forecast(
      place: place,
      timezone: DateTime.now().timeZoneName,
      tzAbbrev: '${DateTime.now().timeZoneName}, your device',
      current: current,
      hourly: hourly,
      daily: daily,
      source: 'MET Norway (api.met.no, CC BY 4.0) – fallback',
    );
  }

  /// Current temperature / wind for grid points (fallback for the map layers).
  /// Requests run with limited concurrency to stay polite to api.met.no.
  static Future<List<GridPoint>> grid(List<(double, double)> pts) async {
    final out = List<GridPoint?>.filled(pts.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < pts.length) {
        final i = next++;
        try {
          final uri = Uri.https('api.met.no', '/weatherapi/locationforecast/2.0/compact',
              {'lat': pts[i].$1.toStringAsFixed(2), 'lon': pts[i].$2.toStringAsFixed(2)});
          final res = await http.get(uri).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) continue;
          final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final t = (((j['properties'] as Map)['timeseries'] as List).first as Map)['data'] as Map;
          final d = (t['instant'] as Map)['details'] as Map;
          final sym = ((t['next_1_hours'] as Map?)?['summary'] as Map?)?['symbol_code'] as String?;
          double n(String k) => (d[k] as num?)?.toDouble() ?? double.nan;
          out[i] = GridPoint(pts[i].$1, pts[i].$2, n('air_temperature'), n('wind_speed') * 3.6, n('wind_from_direction'), symbolToWmo(sym));
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(6, (_) => worker()));
    final res = out.whereType<GridPoint>().toList();
    if (res.isEmpty) throw Exception('api.met.no: no grid data');
    return res;
  }

  static bool _isDay(String? sym, DateTime utc, (DateTime?, DateTime?) sun) {
    if (sym != null && sym.endsWith('_night')) return false;
    if (sym != null && (sym.endsWith('_day') || sym.endsWith('_polartwilight'))) return true;
    if (sun.$1 == null || sun.$2 == null) return true;
    return utc.isAfter(sun.$1!.toUtc()) && utc.isBefore(sun.$2!.toUtc());
  }

  /// Maps MET Norway symbol codes to WMO weather codes used across the app.
  static int symbolToWmo(String? s) {
    if (s == null) return 3;
    final b = s.split('_').first;
    if (b.contains('thunder')) return 95;
    const m = {
      'clearsky': 0, 'fair': 1, 'partlycloudy': 2, 'cloudy': 3, 'fog': 45,
      'lightrain': 61, 'rain': 63, 'heavyrain': 65,
      'lightrainshowers': 80, 'rainshowers': 81, 'heavyrainshowers': 82,
      'lightsleet': 66, 'sleet': 67, 'heavysleet': 67, 'lightsleetshowers': 66, 'sleetshowers': 67, 'heavysleetshowers': 67,
      'lightsnow': 71, 'snow': 73, 'heavysnow': 75, 'lightsnowshowers': 85, 'snowshowers': 85, 'heavysnowshowers': 86,
    };
    return m[b] ?? 3;
  }
}

class _E {
  final DateTime time;
  final double temp, feels, humidity, pressure, wind, gust, windDir, cloud, uv, precip1, precip6, prob1, prob6, tMax6, tMin6;
  final String? sym, sym6;
  final bool hourly;
  _E({required this.time, required this.temp, required this.feels, required this.humidity, required this.pressure, required this.wind,
      required this.gust, required this.windDir, required this.cloud, required this.uv, required this.sym, required this.sym6,
      required this.hourly, required this.precip1, required this.precip6, required this.prob1, required this.prob6,
      required this.tMax6, required this.tMin6});
}

/// Sunrise / sunset (device-local DateTimes) for the calendar date of [day] using the NOAA
/// solar position approximation. Returns nulls during polar day / night.
(DateTime?, DateTime?) sunTimes(DateTime day, double lat, double lon) {
  final dateUtc = DateTime.utc(day.year, day.month, day.day);
  final n = dateUtc.difference(DateTime.utc(day.year, 1, 1)).inDays + 1;
  final gamma = 2 * math.pi / 365 * (n - 1);
  final eqTime = 229.18 * (0.000075 + 0.001868 * math.cos(gamma) - 0.032077 * math.sin(gamma) - 0.014615 * math.cos(2 * gamma) - 0.040849 * math.sin(2 * gamma));
  final decl = 0.006918 - 0.399912 * math.cos(gamma) + 0.070257 * math.sin(gamma) - 0.006758 * math.cos(2 * gamma) +
      0.000907 * math.sin(2 * gamma) - 0.002697 * math.cos(3 * gamma) + 0.00148 * math.sin(3 * gamma);
  final latR = lat * math.pi / 180;
  final cosH = (math.cos(90.833 * math.pi / 180) / (math.cos(latR) * math.cos(decl))) - math.tan(latR) * math.tan(decl);
  if (cosH.abs() > 1) return (null, null);
  final ha = math.acos(cosH) * 180 / math.pi;
  final riseMin = 720 - 4 * (lon + ha) - eqTime;
  final setMin = 720 - 4 * (lon - ha) - eqTime;
  DateTime at(double m) => dateUtc.add(Duration(seconds: (m * 60).round())).toLocal();
  return (at(riseMin), at(setMin));
}
