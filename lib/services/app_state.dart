import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/forecast.dart';
import '../models/place.dart';
import 'api.dart';

/// App-wide state: selected place, forecast, units, favourites, tab.
class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;

  bool fahrenheit = false;
  bool mph = false;
  List<Place> favourites = [];

  Place? place;
  bool placeIsMyLocation = false;
  Forecast? forecast;
  List<WeatherAlert> alerts = const [];
  bool loading = false;
  String? error;

  LatLng? myLocation;
  String? locationError;
  bool locating = false;

  int tab = 0;
  LatLng? mapFocus; // requested map centre (e.g. after search)

  Future<void> init() async {
    // Deep links: ?tab=weather|map|news
    final t = Uri.base.queryParameters['tab'];
    if (t != null) tab = const {'weather': 0, 'map': 1, 'news': 2}[t] ?? 0;
    _prefs = await SharedPreferences.getInstance();
    fahrenheit = _prefs!.getBool('fahrenheit') ?? false;
    mph = _prefs!.getBool('mph') ?? false;
    final favs = _prefs!.getString('favourites');
    if (favs != null) {
      try {
        favourites = (jsonDecode(favs) as List).map((e) => Place.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    Place? last;
    final lastJson = _prefs!.getString('lastPlace');
    if (lastJson != null) {
      try {
        last = Place.fromJson(jsonDecode(lastJson) as Map<String, dynamic>);
      } catch (_) {}
    }
    notifyListeners();
    // Show something immediately, then try geolocation.
    unawaited(selectPlace(last ?? Place.london, remember: false));
    unawaited(useMyLocation(silent: true));
  }

  Future<void> useMyLocation({bool silent = false}) async {
    locating = true;
    locationError = null;
    notifyListeners();
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      myLocation = LatLng(pos.latitude, pos.longitude);
      locating = false;
      notifyListeners();
      final p = await WeatherApi.reverse(pos.latitude, pos.longitude);
      await selectPlace(p, myLocation: true);
    } catch (e) {
      locating = false;
      locationError = 'Location unavailable – showing ${place?.name ?? 'London'}';
      if (!silent) notifyListeners();
      notifyListeners();
    }
  }

  Future<void> selectPlace(Place p, {bool remember = true, bool myLocation = false}) async {
    place = p;
    placeIsMyLocation = myLocation;
    loading = true;
    error = null;
    notifyListeners();
    if (remember) _prefs?.setString('lastPlace', jsonEncode(p.toJson()));
    try {
      final f = await WeatherApi.forecast(p);
      if (place?.key != p.key) return; // superseded
      forecast = f;
      alerts = await WeatherApi.usAlerts(p.lat, p.lon);
    } catch (e) {
      if (place?.key == p.key) error = e.toString();
    } finally {
      if (place?.key == p.key) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    if (place != null) await selectPlace(place!, remember: false, myLocation: placeIsMyLocation);
  }

  bool isFavourite(Place p) => favourites.any((f) => f.key == p.key);

  void toggleFavourite(Place p) {
    if (isFavourite(p)) {
      favourites.removeWhere((f) => f.key == p.key);
    } else {
      favourites.add(p);
    }
    _prefs?.setString('favourites', jsonEncode(favourites.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  void setFahrenheit(bool v) {
    fahrenheit = v;
    _prefs?.setBool('fahrenheit', v);
    notifyListeners();
  }

  void setMph(bool v) {
    mph = v;
    _prefs?.setBool('mph', v);
    notifyListeners();
  }

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  void showOnMap(Place p) {
    mapFocus = LatLng(p.lat, p.lon);
    goTab(1);
  }

  // ---------- formatting helpers ----------
  String temp(double c, {bool unit = false}) {
    if (c.isNaN) return '–';
    final v = fahrenheit ? c * 9 / 5 + 32 : c;
    return '${v.round()}°${unit ? (fahrenheit ? 'F' : 'C') : ''}';
  }

  String wind(double kmh) {
    if (kmh.isNaN) return '–';
    return mph ? '${(kmh / 1.609344).round()} mph' : '${kmh.round()} km/h';
  }
}
