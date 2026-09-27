import 'place.dart';

double _d(dynamic v) => v == null ? double.nan : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

class CurrentWeather {
  final DateTime time;
  final double temp, feelsLike, humidity, precipitation, pressure, windSpeed, windDir, windGusts, cloudCover, uv;
  final int code;
  final bool isDay;

  CurrentWeather({required this.time, required this.temp, required this.feelsLike, required this.humidity, required this.precipitation,
      required this.pressure, required this.windSpeed, required this.windDir, required this.windGusts, required this.cloudCover,
      required this.uv, required this.code, required this.isDay});

  CurrentWeather.fromJson(Map<String, dynamic> j)
      : time = DateTime.parse(j['time'] as String),
        temp = _d(j['temperature_2m']),
        feelsLike = _d(j['apparent_temperature']),
        humidity = _d(j['relative_humidity_2m']),
        precipitation = _d(j['precipitation']),
        pressure = _d(j['pressure_msl']),
        windSpeed = _d(j['wind_speed_10m']),
        windDir = _d(j['wind_direction_10m']),
        windGusts = _d(j['wind_gusts_10m']),
        cloudCover = _d(j['cloud_cover']),
        uv = _d(j['uv_index']),
        code = _i(j['weather_code']),
        isDay = _i(j['is_day']) == 1;
}

class HourPoint {
  final DateTime time;
  final double temp, precipProb, precip, windSpeed, windDir;
  final int code;
  final bool isDay;
  HourPoint(this.time, this.temp, this.code, this.isDay, this.precipProb, this.precip, this.windSpeed, this.windDir);
}

class DayPoint {
  final DateTime date;
  final int code;
  final double tMax, tMin, uvMax, precipSum, precipProbMax, windMax, windDir;
  final DateTime? sunrise, sunset;
  DayPoint(this.date, this.code, this.tMax, this.tMin, this.sunrise, this.sunset, this.uvMax, this.precipSum,
      this.precipProbMax, this.windMax, this.windDir);
}

/// Full forecast as returned by the Open-Meteo forecast API (metric units).
class Forecast {
  final Place place;
  final String timezone;
  final String tzAbbrev;
  final CurrentWeather current;
  final List<HourPoint> hourly;
  final List<DayPoint> daily;
  final DateTime fetchedAt;
  final String source;

  Forecast({required this.place, required this.timezone, required this.tzAbbrev, required this.current, required this.hourly, required this.daily,
      this.source = 'Open-Meteo.com (CC BY 4.0)'})
      : fetchedAt = DateTime.now();

  factory Forecast.fromJson(Place place, Map<String, dynamic> j) {
    final h = j['hourly'] as Map<String, dynamic>;
    final ht = (h['time'] as List).cast<String>();
    final hourly = <HourPoint>[
      for (var k = 0; k < ht.length; k++)
        HourPoint(
          DateTime.parse(ht[k]),
          _d(h['temperature_2m'][k]),
          _i(h['weather_code'][k]),
          _i(h['is_day'][k]) == 1,
          _d(h['precipitation_probability'][k]),
          _d(h['precipitation'][k]),
          _d(h['wind_speed_10m'][k]),
          _d(h['wind_direction_10m'][k]),
        ),
    ];
    final d = j['daily'] as Map<String, dynamic>;
    final dt = (d['time'] as List).cast<String>();
    DateTime? p(dynamic v) => v == null ? null : DateTime.tryParse(v as String);
    final daily = <DayPoint>[
      for (var k = 0; k < dt.length; k++)
        DayPoint(
          DateTime.parse(dt[k]),
          _i(d['weather_code'][k]),
          _d(d['temperature_2m_max'][k]),
          _d(d['temperature_2m_min'][k]),
          p(d['sunrise'][k]),
          p(d['sunset'][k]),
          _d(d['uv_index_max'][k]),
          _d(d['precipitation_sum'][k]),
          _d(d['precipitation_probability_max'][k]),
          _d(d['wind_speed_10m_max'][k]),
          _d(d['wind_direction_10m_dominant'][k]),
        ),
    ];
    return Forecast(
      place: place,
      timezone: j['timezone'] as String? ?? '',
      tzAbbrev: '${j['timezone'] ?? ''} (${j['timezone_abbreviation'] ?? ''})',
      current: CurrentWeather.fromJson(j['current'] as Map<String, dynamic>),
      hourly: hourly,
      daily: daily,
    );
  }
}

/// A sampled grid point for the temperature / wind map layers.
class GridPoint {
  final double lat, lon, temp, windSpeed, windDir;
  final int code;
  GridPoint(this.lat, this.lon, this.temp, this.windSpeed, this.windDir, this.code);
}

class WeatherAlert {
  final String title, description, severity, source;
  final String? link;
  final DateTime? expires;
  WeatherAlert({required this.title, required this.description, required this.severity, required this.source, this.link, this.expires});
}

extension NumFmt on double {
  /// Rounded integer as text, or an en dash when the value is missing (NaN).
  String get r => isNaN || isInfinite ? '–' : round().toString();
  String f1() => isNaN || isInfinite ? '–' : toStringAsFixed(1);
}
