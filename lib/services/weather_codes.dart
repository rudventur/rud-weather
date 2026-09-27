import 'package:flutter/material.dart';

/// WMO weather interpretation codes (as used by Open-Meteo).
class WeatherCode {
  static String describe(int code) => switch (code) {
        0 => 'Clear sky',
        1 => 'Mainly clear',
        2 => 'Partly cloudy',
        3 => 'Overcast',
        45 => 'Fog',
        48 => 'Depositing rime fog',
        51 => 'Light drizzle',
        53 => 'Drizzle',
        55 => 'Dense drizzle',
        56 => 'Light freezing drizzle',
        57 => 'Freezing drizzle',
        61 => 'Slight rain',
        63 => 'Rain',
        65 => 'Heavy rain',
        66 => 'Light freezing rain',
        67 => 'Freezing rain',
        71 => 'Slight snow',
        73 => 'Snow',
        75 => 'Heavy snow',
        77 => 'Snow grains',
        80 => 'Light showers',
        81 => 'Showers',
        82 => 'Violent showers',
        85 => 'Snow showers',
        86 => 'Heavy snow showers',
        95 => 'Thunderstorm',
        96 => 'Thunderstorm, hail',
        99 => 'Thunderstorm, heavy hail',
        _ => 'Unknown',
      };

  static IconData icon(int code, {bool isDay = true}) {
    if (code == 0) return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
    if (code == 1 || code == 2) return isDay ? Icons.wb_cloudy_outlined : Icons.nights_stay_rounded;
    if (code == 3) return Icons.cloud_rounded;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 51 && code <= 57) return Icons.grain_rounded;
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return Icons.water_drop_rounded;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return Icons.ac_unit_rounded;
    if (code >= 95) return Icons.thunderstorm_rounded;
    return Icons.help_outline;
  }

  static Color color(int code, {bool isDay = true}) {
    if (code == 0) return isDay ? const Color(0xFFFFB300) : const Color(0xFF9FA8DA);
    if (code == 1 || code == 2) return isDay ? const Color(0xFFFFCA28) : const Color(0xFF9FA8DA);
    if (code == 3 || code == 45 || code == 48) return const Color(0xFF90A4AE);
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return const Color(0xFF42A5F5);
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return const Color(0xFF80DEEA);
    if (code >= 95) return const Color(0xFF7E57C2);
    return Colors.grey;
  }

  /// Background gradient for the hero card.
  static List<Color> gradient(int code, bool isDay) {
    if (!isDay) return const [Color(0xFF1A237E), Color(0xFF0D1333)];
    if (code <= 1) return const [Color(0xFF42A5F5), Color(0xFF1565C0)];
    if (code <= 3 || code == 45 || code == 48) return const [Color(0xFF78909C), Color(0xFF37474F)];
    if (code >= 95) return const [Color(0xFF5E35B1), Color(0xFF263238)];
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return const [Color(0xFF90CAF9), Color(0xFF546E7A)];
    return const [Color(0xFF5C6BC0), Color(0xFF283593)];
  }
}

String compassPoint(double deg) {
  if (deg.isNaN) return '–';
  const pts = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
  return pts[((deg % 360) / 22.5).round() % 16];
}

String uvCategory(double uv) {
  if (uv.isNaN) return '';
  if (uv < 3) return 'Low';
  if (uv < 6) return 'Moderate';
  if (uv < 8) return 'High';
  if (uv < 11) return 'Very high';
  return 'Extreme';
}

/// Temperature colour scale (°C) shared by the map layer and legend.
const tempStops = <(double, Color)>[
  (-30, Color(0xFF6A1B9A)),
  (-15, Color(0xFF3949AB)),
  (-5, Color(0xFF1E88E5)),
  (0, Color(0xFF4FC3F7)),
  (5, Color(0xFF4DB6AC)),
  (10, Color(0xFF81C784)),
  (15, Color(0xFFD4E157)),
  (20, Color(0xFFFFEE58)),
  (25, Color(0xFFFFA726)),
  (30, Color(0xFFF4511E)),
  (35, Color(0xFFC62828)),
  (45, Color(0xFF880E4F)),
];

/// Wind speed colour scale (km/h).
const windStops = <(double, Color)>[
  (0, Color(0xFFB3E5FC)),
  (10, Color(0xFF4FC3F7)),
  (20, Color(0xFF26A69A)),
  (30, Color(0xFF9CCC65)),
  (40, Color(0xFFFFEE58)),
  (55, Color(0xFFFFA726)),
  (75, Color(0xFFE53935)),
  (100, Color(0xFF8E24AA)),
];

Color scaleColor(List<(double, Color)> stops, double v) {
  if (v.isNaN) return Colors.transparent;
  if (v <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    if (v <= stops[i].$1) {
      final t = (v - stops[i - 1].$1) / (stops[i].$1 - stops[i - 1].$1);
      return Color.lerp(stops[i - 1].$2, stops[i].$2, t)!;
    }
  }
  return stops.last.$2;
}
