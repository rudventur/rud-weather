import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/forecast.dart';
import '../models/place.dart';
import '../services/api.dart';
import '../services/app_state.dart';
import '../services/weather_codes.dart';
import 'search_page.dart';

const _ua = 'io.github.rudventur.rud_weather';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  bool _ready = false;
  LatLng? _pendingFocus;

  // Layers
  bool radarOn = true, satOn = false, tempOn = false, windOn = false;
  double opacity = 0.7;

  // RainViewer
  RainViewerData? _rv;
  String? _rvError;
  int _frame = 0;
  bool _playing = false;
  Timer? _anim, _rvRefresh;

  // Temperature / wind grid
  List<GridPoint> _grid = const [];
  List<(LatLng, LatLng)> _cells = const []; // (sw, ne) for each entry in _grid
  bool _gridLoading = false;
  String? _gridError;
  Timer? _gridDebounce;
  int _gridSeq = 0;

  // Tapped point
  LatLng? _tapped;
  Place? _tappedPlace;
  Forecast? _tappedForecast;
  bool _tappedLoading = false;
  String? _tappedError;
  int _tapSeq = 0;

  @override
  void initState() {
    super.initState();
    // Deep links: ?layers=radar,sat,temp,wind (default: radar)
    final l = Uri.base.queryParameters['layers'];
    if (l != null) {
      final set = l.split(',').map((e) => e.trim().toLowerCase()).toSet();
      radarOn = set.contains('radar');
      satOn = set.contains('sat');
      tempOn = set.contains('temp');
      windOn = set.contains('wind');
    }
    _loadRainViewer();
    _rvRefresh = Timer.periodic(const Duration(minutes: 5), (_) => _loadRainViewer());
  }

  @override
  void dispose() {
    _anim?.cancel();
    _rvRefresh?.cancel();
    _gridDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRainViewer() async {
    try {
      final rv = await RainViewerData.load();
      if (!mounted) return;
      setState(() {
        final wasLatest = _rv == null || _frame >= _latestPastIndex(_rv!);
        _rv = rv;
        _rvError = null;
        if (!_playing && wasLatest) _frame = _latestPastIndex(rv);
        _frame = _frame.clamp(0, math.max(0, rv.radar.length - 1));
      });
    } catch (e) {
      if (mounted) setState(() => _rvError = 'Radar unavailable: $e');
    }
  }

  int _latestPastIndex(RainViewerData rv) {
    final i = rv.radar.lastIndexWhere((f) => !f.nowcast);
    return i < 0 ? 0 : i;
  }

  void _togglePlay() {
    final rv = _rv;
    if (rv == null || rv.radar.length < 2) return;
    setState(() => _playing = !_playing);
    _anim?.cancel();
    if (_playing) {
      var hold = 0;
      _anim = Timer.periodic(const Duration(milliseconds: 600), (_) {
        if (!mounted) return;
        final len = _rv!.radar.length;
        if (_frame == len - 1 && hold < 2) {
          hold++; // linger on the latest frame
          return;
        }
        hold = 0;
        setState(() => _frame = (_frame + 1) % len);
      });
    }
  }

  // ---------------- grid layers ----------------
  void _scheduleGrid() {
    if (!(tempOn || windOn)) return;
    _gridDebounce?.cancel();
    _gridDebounce = Timer(const Duration(milliseconds: 700), _loadGrid);
  }

  Future<void> _loadGrid() async {
    if (!_ready || !(tempOn || windOn)) return;
    final cam = _map.camera;
    final b = cam.visibleBounds;
    final south = math.max(-80.0, b.south), north = math.min(80.0, b.north);
    var west = b.west, east = b.east;
    if (east - west > 360) {
      west = -180;
      east = 180;
    }
    final size = cam.nonRotatedSize;
    final landscape = size.width > size.height;
    final cols = landscape ? 8 : 5;
    final rows = (cols * size.height / math.max(1, size.width)).round().clamp(3, 9);
    final dLat = (north - south) / rows, dLon = (east - west) / cols;
    final pts = <(double, double)>[];
    final cells = <(LatLng, LatLng)>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final lat = south + dLat * (r + 0.5);
        var lon = west + dLon * (c + 0.5);
        cells.add((LatLng(south + dLat * r, west + dLon * c), LatLng(south + dLat * (r + 1), west + dLon * (c + 1))));
        lon = ((lon + 180) % 360 + 360) % 360 - 180;
        pts.add((lat, lon));
      }
    }
    final seq = ++_gridSeq;
    setState(() => _gridLoading = true);
    try {
      final g = await WeatherApi.grid(pts);
      if (!mounted || seq != _gridSeq) return;
      // Keep the cell that belongs to each returned point.
      final byKey = <String, (LatLng, LatLng)>{
        for (var k = 0; k < pts.length; k++) '${pts[k].$1.toStringAsFixed(2)},${pts[k].$2.toStringAsFixed(2)}': cells[k],
      };
      final keep = g.where((p) => byKey.containsKey('${p.lat.toStringAsFixed(2)},${p.lon.toStringAsFixed(2)}')).toList();
      setState(() {
        _grid = keep;
        _cells = [for (final p in keep) byKey['${p.lat.toStringAsFixed(2)},${p.lon.toStringAsFixed(2)}']!];
        _gridError = null;
      });
    } catch (e) {
      if (mounted && seq == _gridSeq) setState(() => _gridError = e.toString());
    } finally {
      if (mounted && seq == _gridSeq) setState(() => _gridLoading = false);
    }
  }

  // ---------------- tapping ----------------
  Future<void> _selectPoint(LatLng p, {Place? place}) async {
    final seq = ++_tapSeq;
    setState(() {
      _tapped = p;
      _tappedPlace = place ?? Place(name: Place.coordLabel(p.latitude, p.longitude), lat: p.latitude, lon: p.longitude);
      _tappedForecast = null;
      _tappedLoading = true;
      _tappedError = null;
    });
    if (place == null) {
      WeatherApi.reverse(p.latitude, p.longitude).then((pl) {
        if (mounted && seq == _tapSeq) setState(() => _tappedPlace = pl);
      });
    }
    try {
      final f = await WeatherApi.forecast(_tappedPlace!);
      if (mounted && seq == _tapSeq) setState(() => _tappedForecast = f);
    } catch (e) {
      if (mounted && seq == _tapSeq) setState(() => _tappedError = e.toString());
    } finally {
      if (mounted && seq == _tapSeq) setState(() => _tappedLoading = false);
    }
  }

  void _focus(LatLng p, [double zoom = 9]) {
    if (_ready) {
      _map.move(p, zoom);
    } else {
      _pendingFocus = p;
    }
  }

  Future<void> _search() async {
    final p = await SearchPage.open(context);
    if (p == null) return;
    final ll = LatLng(p.lat, p.lon);
    _focus(ll);
    _selectPoint(ll, place: p);
  }

  void _myLocation(AppState s) async {
    if (s.myLocation != null) {
      _focus(s.myLocation!, 10);
    } else {
      await s.useMyLocation();
      if (s.myLocation != null) {
        _focus(s.myLocation!, 10);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location unavailable (permission denied or not supported).')));
      }
    }
  }

  // ---------------- UI ----------------
  void _openLayers() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void upd(VoidCallback fn) {
          setState(fn);
          setSheet(() {});
        }

        final satAvailable = _rv?.satellite.isNotEmpty ?? false;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Weather layers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              SwitchListTile(
                secondary: const Icon(Icons.radar),
                title: const Text('Rain radar'),
                subtitle: Text(_rvError ?? 'RainViewer · past ~2 h, animated${(_rv?.radar.any((f) => f.nowcast) ?? false) ? ' + nowcast' : ''}'),
                value: radarOn,
                onChanged: (v) => upd(() => radarOn = v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.satellite_alt_outlined),
                title: const Text('Satellite infrared'),
                subtitle: Text(satAvailable ? 'RainViewer infrared clouds' : 'Not currently provided by the RainViewer free API'),
                value: satOn && satAvailable,
                onChanged: satAvailable ? (v) => upd(() => satOn = v) : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.thermostat),
                title: const Text('Temperature'),
                subtitle: const Text('Live Open-Meteo grid for the visible area'),
                value: tempOn,
                onChanged: (v) {
                  upd(() => tempOn = v);
                  if (v) _loadGrid();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.air),
                title: const Text('Wind'),
                subtitle: const Text('Speed & direction arrows (Open-Meteo)'),
                value: windOn,
                onChanged: (v) {
                  upd(() => windOn = v);
                  if (v) _loadGrid();
                },
              ),
              ListTile(
                leading: const Icon(Icons.opacity),
                title: const Text('Layer opacity'),
                subtitle: Slider(value: opacity, min: 0.2, max: 1, divisions: 8, label: '${(opacity * 100).round()}%', onChanged: (v) => upd(() => opacity = v)),
              ),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.mapFocus != null) {
      final f = s.mapFocus!;
      s.mapFocus = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(f, 9));
    }
    final scheme = Theme.of(context).colorScheme;
    final start = s.place == null ? const LatLng(51.5085, -0.1257) : LatLng(s.place!.lat, s.place!.lon);
    final rv = _rv;

    final overlays = <Widget>[];
    if (rv != null && satOn && rv.satellite.isNotEmpty) {
      final f = rv.satellite.last;
      overlays.add(Opacity(
        key: ValueKey('s${f.path}'),
        opacity: opacity,
        child: TileLayer(urlTemplate: rv.satelliteUrl(f), maxNativeZoom: 7, userAgentPackageName: _ua, tileDisplay: const TileDisplay.instantaneous()),
      ));
    }
    if (rv != null && radarOn && rv.radar.isNotEmpty) {
      final cur = rv.radar[_frame.clamp(0, rv.radar.length - 1)];
      final next = rv.radar[(_frame + 1) % rv.radar.length];
      overlays.add(Opacity(
        key: ValueKey('r${cur.path}'),
        opacity: opacity,
        child: TileLayer(urlTemplate: rv.radarUrl(cur), maxNativeZoom: 7, panBuffer: 0, userAgentPackageName: _ua, tileDisplay: const TileDisplay.instantaneous()),
      ));
      if (_playing && next.path != cur.path) {
        // Preload the next frame invisibly so playback does not flicker.
        overlays.add(Opacity(
          key: ValueKey('r${next.path}'),
          opacity: 0,
          child: TileLayer(urlTemplate: rv.radarUrl(next), maxNativeZoom: 7, panBuffer: 0, userAgentPackageName: _ua, tileDisplay: const TileDisplay.instantaneous()),
        ));
      }
    }

    final gridOn = (tempOn || windOn) && _grid.isNotEmpty && _cells.length >= _grid.length;

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: start,
            initialZoom: 6,
            minZoom: 2,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () {
              _ready = true;
              if (tempOn || windOn) _scheduleGrid();
              if (_pendingFocus != null) {
                _map.move(_pendingFocus!, 9);
                _pendingFocus = null;
              }
            },
            onTap: (_, p) => _selectPoint(p),
            onPositionChanged: (_, _) => _scheduleGrid(),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: _ua,
              maxNativeZoom: 19,
            ),
            ...overlays,
            if (gridOn)
              PolygonLayer(polygons: [
                for (var i = 0; i < _grid.length; i++)
                  Polygon(
                    points: [
                      _cells[i].$1,
                      LatLng(_cells[i].$2.latitude, _cells[i].$1.longitude),
                      _cells[i].$2,
                      LatLng(_cells[i].$1.latitude, _cells[i].$2.longitude),
                    ],
                    color: (tempOn ? scaleColor(tempStops, _grid[i].temp) : scaleColor(windStops, _grid[i].windSpeed))
                        .withValues(alpha: opacity * 0.6),
                    borderColor: Colors.white.withValues(alpha: 0.25),
                    borderStrokeWidth: 0.5,
                  ),
              ]),
            if (gridOn)
              MarkerLayer(markers: [
                for (var i = 0; i < _grid.length; i++)
                  Marker(
                    point: LatLng((_cells[i].$1.latitude + _cells[i].$2.latitude) / 2, (_cells[i].$1.longitude + _cells[i].$2.longitude) / 2),
                    width: 70,
                    height: 44,
                    child: _GridLabel(g: _grid[i], s: s, showTemp: tempOn, showWind: windOn),
                  ),
              ]),
            MarkerLayer(markers: [
              if (s.myLocation != null)
                Marker(
                  point: s.myLocation!,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                  ),
                ),
              if (_tapped != null)
                Marker(point: _tapped!, width: 40, height: 40, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
            ]),
          ],
        ),
        // Search bar
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          left: 12,
          right: 12,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(28),
                color: scheme.surface,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: _search,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.search),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Search place · tap map for weather', style: TextStyle(color: scheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                      if (_gridLoading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Right-side controls
        Positioned(
          right: 12,
          top: MediaQuery.paddingOf(context).top + 76,
          child: Column(children: [
            FloatingActionButton.small(heroTag: 'layers', tooltip: 'Layers', onPressed: _openLayers, child: const Icon(Icons.layers)),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'loc', tooltip: 'My location', onPressed: () => _myLocation(s), child: const Icon(Icons.my_location)),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'zin', tooltip: 'Zoom in', onPressed: () => _map.move(_map.camera.center, _map.camera.zoom + 1), child: const Icon(Icons.add)),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'zout', tooltip: 'Zoom out', onPressed: () => _map.move(_map.camera.center, _map.camera.zoom - 1), child: const Icon(Icons.remove)),
          ]),
        ),
        // Bottom panels
        Positioned(
          left: 8,
          right: 8,
          bottom: 24,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_gridError != null && (tempOn || windOn)) _infoChip(context, 'Grid layer: $_gridError'),
                _Legend(s: s, radar: radarOn && rv != null, temp: tempOn, wind: windOn && !tempOn),
                if (radarOn && rv != null && rv.radar.isNotEmpty) _timeline(context, rv),
                if (radarOn && _rvError != null) _infoChip(context, _rvError!),
                if (_tapped != null) _tappedCard(context, s),
              ]),
            ),
          ),
        ),
        // Attribution (always visible)
        Positioned(
          right: 4,
          bottom: 2,
          child: _Attribution(radar: radarOn || satOn, grid: tempOn || windOn),
        ),
      ]),
    );
  }

  Widget _infoChip(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Card(child: Padding(padding: const EdgeInsets.all(8), child: Text(text, style: const TextStyle(fontSize: 12)))),
      );

  Widget _timeline(BuildContext context, RainViewerData rv) {
    final f = rv.radar[_frame.clamp(0, rv.radar.length - 1)];
    final latest = rv.radar[_latestPastIndex(rv)].time;
    final diff = f.time.difference(latest).inMinutes;
    final rel = f.nowcast ? 'forecast +${diff}m' : (diff == 0 ? 'latest' : '${diff}m');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        elevation: 2,
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
          child: Row(children: [
            IconButton(icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle), iconSize: 32, tooltip: _playing ? 'Pause' : 'Play radar', onPressed: _togglePlay),
            Expanded(
              child: Slider(
                value: _frame.toDouble().clamp(0, (rv.radar.length - 1).toDouble()),
                min: 0,
                max: math.max(1, rv.radar.length - 1).toDouble(),
                divisions: math.max(1, rv.radar.length - 1),
                onChanged: (v) => setState(() => _frame = v.round()),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(DateFormat.Hm().format(f.time.toLocal()), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(rel, style: TextStyle(fontSize: 11, color: f.nowcast ? Colors.orange : Theme.of(context).colorScheme.outline)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _tappedCard(BuildContext context, AppState s) {
    final p = _tappedPlace!;
    final f = _tappedForecast;
    final c = f?.current;
    final today = (f?.daily.isNotEmpty ?? false) ? f!.daily.first : null;
    return Card(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16), overflow: TextOverflow.ellipsis),
                Text([p.subtitle, Place.coordLabel(p.lat, p.lon)].where((e) => e.isNotEmpty && e != p.name).join(' · '),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline), overflow: TextOverflow.ellipsis),
              ]),
            ),
            IconButton(
              icon: Icon(s.isFavourite(p) ? Icons.star : Icons.star_border, color: s.isFavourite(p) ? Colors.amber : null),
              tooltip: 'Save place',
              onPressed: () => s.toggleFavourite(p),
            ),
            IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => setState(() => _tapped = null)),
          ]),
          if (_tappedLoading) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          if (_tappedError != null) Text(_tappedError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (c != null)
            Row(children: [
              Icon(WeatherCode.icon(c.code, isDay: c.isDay), color: WeatherCode.color(c.code, isDay: c.isDay), size: 40),
              const SizedBox(width: 8),
              Text(s.temp(c.temp), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w400)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(WeatherCode.describe(c.code), style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    'Feels ${s.temp(c.feelsLike)} · ${s.wind(c.windSpeed)} ${compassPoint(c.windDir)} · ${c.humidity.r}%'
                    '${today != null ? '\nH ${s.temp(today.tMax)} L ${s.temp(today.tMin)} · rain ${today.precipProbMax.r}%' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ]),
              ),
              TextButton(
                onPressed: () {
                  s.selectPlace(p);
                  s.goTab(0);
                },
                child: const Text('Forecast'),
              ),
            ]),
        ]),
      ),
    );
  }
}

class _GridLabel extends StatelessWidget {
  final GridPoint g;
  final AppState s;
  final bool showTemp, showWind;
  const _GridLabel({required this.g, required this.s, required this.showTemp, required this.showWind});

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black87, blurRadius: 3)];
    final spd = s.mph ? (g.windSpeed / 1.609344).r : g.windSpeed.r;
    return IgnorePointer(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (showTemp) Text(s.temp(g.temp), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, shadows: shadow)),
        if (showWind)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.rotate(
              angle: (g.windDir + 180) * math.pi / 180,
              child: Icon(Icons.navigation, size: 16, color: showTemp ? Colors.white : scaleColor(windStops, g.windSpeed), shadows: shadow),
            ),
            Text(spd, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, shadows: shadow)),
          ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final AppState s;
  final bool radar, temp, wind;
  const _Legend({required this.s, required this.radar, required this.temp, required this.wind});

  Widget _bar(BuildContext context, String title, List<Color> colors, List<String> labels) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 62, child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 8, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), gradient: LinearGradient(colors: colors))),
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final l in labels) Text(l, style: const TextStyle(fontSize: 10))]),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (!radar && !temp && !wind) return const SizedBox();
    final rows = <Widget>[
      // Approximation of RainViewer's "Universal Blue" colour scheme (dBZ).
      if (radar)
        _bar(context, 'Rain', const [Color(0xFF9CE5FF), Color(0xFF4AB8F0), Color(0xFF0F6FC6), Color(0xFF0A3E8C), Color(0xFFFFE200), Color(0xFFFF8C00), Color(0xFFE40000), Color(0xFFC800C8)],
            const ['light', 'moderate', 'heavy', 'extreme']),
      if (temp)
        _bar(context, 'Temp', [for (final t in tempStops.skip(1).take(10)) t.$2],
            [for (final c in [-15.0, 0.0, 15.0, 30.0]) s.temp(c, unit: true)]),
      if (wind)
        _bar(context, 'Wind', [for (final t in windStops) t.$2], [s.wind(0), s.wind(30), s.wind(55), s.wind(100)]),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        elevation: 2,
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 4), child: Column(mainAxisSize: MainAxisSize.min, children: rows)),
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  final bool radar, grid;
  const _Attribution({required this.radar, required this.grid});

  @override
  Widget build(BuildContext context) {
    Widget link(String t, String url) => InkWell(
          onTap: () => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'),
          child: Text(t, style: const TextStyle(fontSize: 10, color: Color(0xFF0B57D0))),
        );
    const sep = Text(' · ', style: TextStyle(fontSize: 10, color: Colors.black54));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        link('© OpenStreetMap contributors', 'https://www.openstreetmap.org/copyright'),
        if (radar) ...[sep, link('RainViewer', 'https://www.rainviewer.com/')],
        sep,
        link('Open-Meteo', 'https://open-meteo.com/'),
        sep,
        link('MET Norway', 'https://api.met.no/'),
      ]),
    );
  }
}
