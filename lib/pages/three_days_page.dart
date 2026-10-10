import 'dart:async';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:web/web.dart' as web;

import '../main.dart';
import '../models/forecast.dart';
import '../models/news.dart';
import '../services/api.dart';
import '../services/weather_codes.dart';
import 'news_page.dart' show openLink, timeAgo;

const _ua = 'com.rudventur.rud_weather';

/// Yesterday | Today | Tomorrow. Swipeable pages on phones, three columns on wide screens.
class ThreeDaysPage extends StatefulWidget {
  const ThreeDaysPage({super.key});
  @override
  State<ThreeDaysPage> createState() => _ThreeDaysPageState();
}

class _ThreeDaysPageState extends State<ThreeDaysPage> {
  final _pc = PageController(initialPage: 1);
  int _page = 1;
  static const _labels = ['Yesterday', 'Today', 'Tomorrow'];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tiles = const [YesterdayTile(), TodayTile(), TomorrowTile()];
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final header = Padding(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 16, 4),
        child: Row(children: [
          Icon(Icons.place, size: 18, color: scheme.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(s.place?.name ?? 'Locating…', style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
          ),
          if (s.loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          IconButton(tooltip: 'Refresh', onPressed: s.refresh, icon: const Icon(Icons.refresh)),
        ]),
      );
      if (wide) {
        return Column(children: [
          header,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _TileFrame(title: _labels[i], child: tiles[i])),
                ],
              ]),
            ),
          ),
        ]);
      }
      return Column(children: [
        header,
        // Day selector: labels double as dots
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (var i = 0; i < 3; i++) ButtonSegment(value: i, label: Text(_labels[i]))],
            selected: {_page},
            onSelectionChanged: (v) => _pc.animateToPage(v.first, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.fromLTRB(3, 8, 3, 6),
              width: i == _page ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(color: i == _page ? scheme.primary : scheme.outlineVariant, borderRadius: BorderRadius.circular(4)),
            ),
        ]),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            child: PageView(
              controller: _pc,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: _TileFrame(title: _labels[i], child: tiles[i])),
              ],
            ),
          ),
        ),
      ]);
    });
  }
}

class _TileFrame extends StatelessWidget {
  final String title;
  final Widget child;
  const _TileFrame({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Card(clipBehavior: Clip.antiAlias, child: child);
}

Widget _sectionTitle(BuildContext context, String t, {IconData? icon}) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6)],
        Expanded(child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
      ]),
    );

Widget _credit(BuildContext context, String text, String url) => InkWell(
      onTap: () => openLink(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
      ),
    );

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _Stat(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: t.labelSmall),
          Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _DayHero extends StatelessWidget {
  final int code;
  final String desc, hiLo, sub;
  const _DayHero({required this.code, required this.desc, required this.hiLo, required this.sub});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(children: [
        Icon(WeatherCode.icon(code), size: 52, color: WeatherCode.color(code)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hiLo, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(desc, style: t.titleSmall),
            Text(sub, style: t.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

// =====================================================================
// YESTERDAY
// =====================================================================
class YesterdayTile extends StatefulWidget {
  const YesterdayTile({super.key});
  @override
  State<YesterdayTile> createState() => _YesterdayTileState();
}

class _YesterdayTileState extends State<YesterdayTile> with AutomaticKeepAliveClientMixin {
  YesterdayWeather? _y;
  String? _err;
  String? _key;
  double _hour = 23; // UTC hour of the archive snapshot (at :55)

  @override
  bool get wantKeepAlive => true;

  void _load(double lat, double lon, String key) {
    _key = key;
    _y = null;
    _err = null;
    WeatherApi.yesterday(lat, lon).then((v) {
      if (mounted && _key == key) setState(() => _y = v);
    }).catchError((Object e) {
      if (mounted && _key == key) setState(() => _err = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = AppScope.of(context);
    final p = s.place;
    if (p != null && p.key != _key) _load(p.lat, p.lon, p.key);
    final yUtc = DateTime.now().toUtc().subtract(const Duration(days: 1));
    String two(int n) => n.toString().padLeft(2, '0');
    final h = _hour.round();
    final path = '${yUtc.year}/${two(yUtc.month)}/${two(yUtc.day)}/${two(h)}/55';
    final overlay = 'https://www.limaps.org/Maps/History/$path/image_b_earth.png';
    const bg = 'https://www.limaps.org/Maps/Backgrounds/map_00.png';
    final y = _y;
    return ListView(padding: const EdgeInsets.only(bottom: 12), children: [
      _sectionTitle(context, 'Global lightning · ${DateFormat('EEE d MMM').format(yUtc)}', icon: Icons.bolt),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 925 / 678,
            child: Stack(fit: StackFit.expand, children: [
              Image.network(bg, fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF2E6E9E))),
              Image.network(overlay, key: ValueKey(overlay), fit: BoxFit.cover, webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (_, _, _) => _ArchiveFallback(url: 'https://www.limaps.org/map-data-archive.html')),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        child: Row(children: [
          Text('${two(h)}:55 UTC', style: Theme.of(context).textTheme.labelMedium),
          Expanded(
            child: Slider(value: _hour, min: 1, max: 23, divisions: 11, label: '${two(h)}:55 UTC', onChanged: (v) => setState(() => _hour = v)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('Each snapshot shows strikes in the 2 hours before the time shown. Not a storm warning.',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      _credit(context, 'Lightning archive: Blitzortung.org / LiMAps, CC BY-SA 4.0', 'https://www.limaps.org/map-data-archive.html'),
      const Divider(height: 20),
      _sectionTitle(context, 'Yesterday in ${p?.name ?? '…'}', icon: Icons.history),
      if (_err != null)
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text('Yesterday\'s local weather isn\'t available right now (the backup forecast service has no history).',
              style: Theme.of(context).textTheme.bodyMedium),
        )
      else if (y == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else ...[
        _DayHero(
          code: y.code,
          desc: WeatherCode.describe(y.code),
          hiLo: '${s.temp(y.tMax)} / ${s.temp(y.tMin)}',
          sub: DateFormat('EEEE d MMMM').format(y.date),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            _Stat(Icons.water_drop_outlined, 'Rain total', '${y.precipSum.f1()} mm'),
            _Stat(Icons.air, 'Max wind', '${s.wind(y.windMax)} ${y.windDir.isNaN ? '' : compassPoint(y.windDir)}'),
            _Stat(Icons.storm_outlined, 'Gusts', s.wind(y.gustMax)),
            _Stat(Icons.wb_sunny_outlined, 'Sunshine', y.sunshineSec.isNaN ? '–' : '${(y.sunshineSec / 3600).f1()} h'),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Text('Source: Open-Meteo.com (model analysis)', style: Theme.of(context).textTheme.labelSmall),
        ),
      ],
    ]);
  }
}

class _ArchiveFallback extends StatelessWidget {
  final String url;
  const _ArchiveFallback({required this.url});
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () => openLink(url),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Archive image unavailable. Tap to open the LiMAps lightning archive.', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}

// =====================================================================
// TODAY
// =====================================================================
class TodayTile extends StatelessWidget {
  const TodayTile({super.key});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Split into thirds; if the tile is short, scroll with sensible minimum heights.
      final third = math.max(300.0, (c.maxHeight - 2) / 3);
      return ListView(padding: EdgeInsets.zero, children: [
        SizedBox(height: third, child: const _LiveLightning()),
        const Divider(height: 1),
        SizedBox(height: third, child: const _LocalRainClouds()),
        const Divider(height: 1),
        SizedBox(height: third, child: const _TopNews()),
      ]);
    });
  }
}

final _registered = <String>{};

class _LiveLightning extends StatelessWidget {
  const _LiveLightning();
  @override
  Widget build(BuildContext context) {
    final p = AppScope.of(context).place;
    final lat = (p?.lat ?? 51.5).toStringAsFixed(2), lon = (p?.lon ?? -0.13).toStringAsFixed(2);
    // Blitzortung's own embeddable public map (the same one LiMAps embeds). lightningmaps.org itself
    // sends X-Frame-Options: SAMEORIGIN, so it is linked rather than framed. No strike data is pulled into the app.
    final src = 'https://maps.blitzortung.org/index.html?Cookies=0&MenuDiv=0&InfoDiv=0&NavigationControl=1&GlobeControl=0'
        '&MapProjection=mercator&FullScreenControl=0&GeolocateControl=0&ScaleControl=0&MapInteractive=1'
        '&LinksCheckboxChecked=0&MapStyle=0#5/$lat/$lon';
    final viewType = 'bo-map-$lat-$lon';
    if (_registered.add(viewType)) {
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
        final f = web.document.createElement('iframe') as web.HTMLIFrameElement;
        f.src = src;
        f.style.border = '0';
        f.style.width = '100%';
        f.style.height = '100%';
        f.referrerPolicy = 'no-referrer';
        f.setAttribute('loading', 'lazy');
        f.title = 'Live lightning map';
        return f;
      });
    }
    final full = 'https://www.lightningmaps.org/#m=oss;t=3;s=0;o=0;b=;ts=0;y=$lat;x=$lon;z=6;d=2;dl=2;dc=0;';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _sectionTitle(context, 'Live lightning', icon: Icons.bolt)),
        TextButton.icon(onPressed: () => openLink(full), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Full map')),
        const SizedBox(width: 6),
      ]),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: HtmlElementView(key: ValueKey(viewType), viewType: viewType)),
        ),
      ),
      Row(children: [
        Expanded(child: _credit(context, 'Live lightning: Blitzortung.org / LightningMaps.org', 'https://www.lightningmaps.org/')),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Text('Not a storm warning', style: Theme.of(context).textTheme.labelSmall),
        ),
      ]),
    ]);
  }
}

class _LocalRainClouds extends StatefulWidget {
  const _LocalRainClouds();
  @override
  State<_LocalRainClouds> createState() => _LocalRainCloudsState();
}

class _LocalRainCloudsState extends State<_LocalRainClouds> {
  final _map = MapController();
  RainViewerData? _rv;
  List<(double, double, double)> _clouds = const [];
  double _step = 0.25;
  String? _key;
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadRadar();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _loadRadar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadRadar() async {
    try {
      final rv = await RainViewerData.load();
      if (mounted) setState(() => _rv = rv);
    } catch (_) {}
  }

  Future<void> _loadClouds(double lat, double lon, String key) async {
    const n = 5;
    const step = 0.25; // degrees, ~ map extent at zoom 7
    final pts = <(double, double)>[
      for (var r = 0; r < n; r++)
        for (var c = 0; c < n; c++) (lat + (r - n ~/ 2) * step * 0.8, lon + (c - n ~/ 2) * step * 1.3),
    ];
    try {
      final g = await WeatherApi.cloudGrid(pts);
      if (mounted && _key == key) {
        setState(() {
          _clouds = g;
          _step = step;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.place;
    final f = s.forecast;
    if (p != null && p.key != _key) {
      _key = p.key;
      _clouds = const [];
      _loadClouds(p.lat, p.lon, p.key);
      if (_ready) _map.move(LatLng(p.lat, p.lon), 7);
    }
    final rv = _rv;
    final past = rv?.radar.where((e) => !e.nowcast).toList() ?? const <RadarFrame>[];
    final frame = past.isEmpty ? null : past.last;
    final centre = LatLng(p?.lat ?? 51.5, p?.lon ?? -0.13);
    final cur = f?.current;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle(context, 'Rain & clouds now', icon: Icons.radar),
      if (cur != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Row(children: [
            Icon(WeatherCode.icon(cur.code, isDay: cur.isDay), color: WeatherCode.color(cur.code, isDay: cur.isDay), size: 32),
            const SizedBox(width: 8),
            Text(s.temp(cur.temp, unit: true), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${WeatherCode.describe(cur.code)} · feels ${s.temp(cur.feelsLike)} · clouds ${cur.cloudCover.r}% · ${s.wind(cur.windSpeed)}',
                  style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: centre,
                initialZoom: 7,
                minZoom: 3,
                maxZoom: 10,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom | InteractiveFlag.scrollWheelZoom),
                onMapReady: () => _ready = true,
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: _ua),
                PolygonLayer(polygons: [
                  for (final c in _clouds)
                    if (!c.$3.isNaN)
                      Polygon(
                        points: [
                          LatLng(c.$1 - _step * 0.4, c.$2 - _step * 0.65),
                          LatLng(c.$1 + _step * 0.4, c.$2 - _step * 0.65),
                          LatLng(c.$1 + _step * 0.4, c.$2 + _step * 0.65),
                          LatLng(c.$1 - _step * 0.4, c.$2 + _step * 0.65),
                        ],
                        color: Colors.blueGrey.shade100.withValues(alpha: c.$3 / 100 * 0.55),
                      ),
                ]),
                if (rv != null && frame != null)
                  Opacity(opacity: 0.8, child: TileLayer(urlTemplate: rv.radarUrl(frame), maxNativeZoom: 7, userAgentPackageName: _ua)),
                MarkerLayer(markers: [
                  Marker(point: centre, width: 18, height: 18,
                      child: Container(decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)))),
                ]),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: Text(
            'Radar${frame != null ? ' ${DateFormat.Hm().format(frame.time)}' : ''}: RainViewer · cloud cover: Open-Meteo · map © OpenStreetMap',
            style: t.labelSmall),
      ),
    ]);
  }
}

class _TopNews extends StatefulWidget {
  const _TopNews();
  @override
  State<_TopNews> createState() => _TopNewsState();
}

class _TopNewsState extends State<_TopNews> {
  NewsFeed? _feed;
  String? _err;

  @override
  void initState() {
    super.initState();
    WeatherApi.news().then((f) {
      if (mounted) setState(() => _feed = f);
    }).catchError((Object e) {
      if (mounted) setState(() => _err = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _feed?.items.take(5).toList() ?? const <NewsItem>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _sectionTitle(context, 'Top weather news', icon: Icons.public)),
        TextButton(onPressed: () => AppScope.read(context).goTab(3), child: const Text('All news')),
        const SizedBox(width: 6),
      ]),
      Expanded(
        child: _err != null
            ? Center(child: Text('News unavailable right now'))
            : _feed == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: EdgeInsets.zero, children: [
                    for (final n in items)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${n.source} · ${timeAgo(n.published)}'),
                        trailing: const Icon(Icons.open_in_new, size: 16),
                        onTap: () => openLink(n.link),
                      ),
                  ]),
      ),
    ]);
  }
}

// =====================================================================
// TOMORROW
// =====================================================================
class TomorrowTile extends StatelessWidget {
  const TomorrowTile({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final f = s.forecast;
    final t = Theme.of(context).textTheme;
    if (f == null) {
      return Center(child: s.error != null ? Text(s.error!) : const CircularProgressIndicator());
    }
    if (f.daily.length < 2) return const Center(child: Text('No forecast for tomorrow yet'));
    final d = f.daily[1];
    final hours = f.hourly
        .where((h) => h.time.year == d.date.year && h.time.month == d.date.month && h.time.day == d.date.day)
        .toList();
    final hm = DateFormat.Hm();
    return ListView(padding: const EdgeInsets.only(bottom: 12), children: [
      _sectionTitle(context, 'Tomorrow in ${f.place.name}', icon: Icons.event),
      _DayHero(
        code: d.code,
        desc: WeatherCode.describe(d.code),
        hiLo: '${s.temp(d.tMax)} / ${s.temp(d.tMin)}',
        sub: DateFormat('EEEE d MMMM').format(d.date),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          _Stat(Icons.umbrella_outlined, 'Rain chance', d.precipProbMax.isNaN ? '–' : '${d.precipProbMax.r}%'),
          _Stat(Icons.water_drop_outlined, 'Rain', '${d.precipSum.f1()} mm'),
          _Stat(Icons.air, 'Wind', '${s.wind(d.windMax)} ${d.windDir.isNaN ? '' : compassPoint(d.windDir)}'),
          _Stat(Icons.wb_twilight, 'Sunrise', d.sunrise == null ? '–' : hm.format(d.sunrise!)),
          _Stat(Icons.nights_stay_outlined, 'Sunset', d.sunset == null ? '–' : hm.format(d.sunset!)),
          if (!d.uvMax.isNaN) _Stat(Icons.light_mode_outlined, 'UV max', d.uvMax.r),
        ]),
      ),
      _sectionTitle(context, 'Hour by hour', icon: Icons.schedule),
      SizedBox(
        height: 112,
        child: hours.isEmpty
            ? const Center(child: Text('Hourly data not available'))
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: hours.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final h = hours[i];
                  return Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(DateFormat.H().format(h.time), style: t.labelSmall),
                      Icon(WeatherCode.icon(h.code, isDay: h.isDay), color: WeatherCode.color(h.code, isDay: h.isDay), size: 22),
                      Text(s.temp(h.temp), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(h.precipProb.isNaN ? '' : '${h.precipProb.r}%', style: t.labelSmall?.copyWith(color: Colors.blue)),
                    ]),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
        child: Text('Predictions may vary ;)', style: t.titleMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.primary)),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(14, 6, 14, 0), child: Text('Source: ${f.source}', style: t.labelSmall)),
    ]);
  }
}
