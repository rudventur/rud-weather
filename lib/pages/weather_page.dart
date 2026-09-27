import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/forecast.dart';
import '../services/app_state.dart';
import '../services/weather_codes.dart';
import 'search_page.dart';

class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final f = s.forecast;
    final place = s.place;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () async {
            final p = await SearchPage.open(context);
            if (p != null) s.selectPlace(p);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              const Icon(Icons.search, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Search city…', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor))),
            ]),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'My location',
            icon: s.locating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
            onPressed: s.locating ? null : () => s.useMyLocation(),
          ),
          PopupMenuButton<String>(
            tooltip: 'Units',
            icon: const Icon(Icons.tune),
            onSelected: (v) {
              if (v == 'c') s.setFahrenheit(false);
              if (v == 'f') s.setFahrenheit(true);
              if (v == 'k') s.setMph(false);
              if (v == 'm') s.setMph(true);
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'c', checked: !s.fahrenheit, child: const Text('Celsius (°C)')),
              CheckedPopupMenuItem(value: 'f', checked: s.fahrenheit, child: const Text('Fahrenheit (°F)')),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(value: 'k', checked: !s.mph, child: const Text('km/h')),
              CheckedPopupMenuItem(value: 'm', checked: s.mph, child: const Text('mph')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: LayoutBuilder(builder: (context, c) {
          final pad = c.maxWidth > 760 ? (c.maxWidth - 720) / 2 : 12.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (s.favourites.isNotEmpty) _FavouritesRow(s: s),
              if (s.locationError != null && !s.placeIsMyLocation)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(s.locationError!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                ),
              if (f == null && s.loading) const Padding(padding: EdgeInsets.all(64), child: Center(child: CircularProgressIndicator())),
              if (s.error != null) _ErrorCard(message: s.error!, onRetry: s.refresh),
              if (f != null && place != null) ...[
                _HeroCard(s: s, f: f),
                if (s.loading) const LinearProgressIndicator(minHeight: 2),
                for (final a in s.alerts) _AlertCard(a: a),
                const SizedBox(height: 12),
                _SectionTitle('Next 48 hours'),
                _HourlyStrip(s: s, f: f),
                const SizedBox(height: 12),
                _SectionTitle('Details'),
                _DetailsGrid(s: s, f: f),
                const SizedBox(height: 12),
                _SectionTitle('7-day forecast'),
                _DailyList(s: s, f: f),
                const SizedBox(height: 16),
                Text(
                  'Weather data: ${f.source} · Times: ${f.tzAbbrev}\n'
                  'Updated ${DateFormat.Hm().format(f.fetchedAt)} on your device',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );
}

class _FavouritesRow extends StatelessWidget {
  final AppState s;
  const _FavouritesRow({required this.s});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in s.favourites)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: ChoiceChip(
                showCheckmark: false,
                avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                label: Text(p.name),
                selected: s.place?.key == p.key,
                onSelected: (_) => s.selectPlace(p),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.cloud_off),
            const SizedBox(width: 12),
            Expanded(child: Text('Could not load the forecast.\n$message')),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

class _HeroCard extends StatelessWidget {
  final AppState s;
  final Forecast f;
  const _HeroCard({required this.s, required this.f});

  @override
  Widget build(BuildContext context) {
    final c = f.current;
    final today = f.daily.isNotEmpty ? f.daily.first : null;
    final place = s.place!;
    const white = Colors.white;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: WeatherCode.gradient(c.code, c.isDay), begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      child: DefaultTextStyle(
        style: const TextStyle(color: white),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (s.placeIsMyLocation) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.near_me, color: white, size: 18)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(place.name, style: const TextStyle(color: white, fontSize: 22, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                if (place.subtitle.isNotEmpty) Text(place.subtitle, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis),
              ]),
            ),
            IconButton(
              tooltip: s.isFavourite(place) ? 'Remove from saved' : 'Save place',
              icon: Icon(s.isFavourite(place) ? Icons.star : Icons.star_border, color: s.isFavourite(place) ? Colors.amber : white),
              onPressed: () => s.toggleFavourite(place),
            ),
            IconButton(tooltip: 'Show on map', icon: const Icon(Icons.map_outlined, color: white), onPressed: () => s.showOnMap(place)),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(s.temp(c.temp), style: const TextStyle(color: white, fontSize: 84, fontWeight: FontWeight.w300, height: 1)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(WeatherCode.icon(c.code, isDay: c.isDay), color: WeatherCode.color(c.code, isDay: c.isDay), size: 44),
                const SizedBox(height: 4),
                Text(WeatherCode.describe(c.code), style: const TextStyle(color: white, fontSize: 18, fontWeight: FontWeight.w500)),
                Text('Feels like ${s.temp(c.feelsLike)}', style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 16, runSpacing: 6, children: [
            if (today != null) _chip(Icons.thermostat, 'H ${s.temp(today.tMax)}  L ${s.temp(today.tMin)}'),
            _chip(Icons.air, '${s.wind(c.windSpeed)} ${compassPoint(c.windDir)}'),
            _chip(Icons.water_drop_outlined, '${c.humidity.r}%'),
            if (today != null && !today.precipProbMax.isNaN) _chip(Icons.umbrella_outlined, '${today.precipProbMax.r}%'),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 16, color: Colors.white70),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(color: Colors.white)),
      ]);
}

class _AlertCard extends StatelessWidget {
  final WeatherAlert a;
  const _AlertCard({required this.a});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          color: Colors.orange.shade100,
          child: ExpansionTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
            title: Text(a.title, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
            subtitle: Text('${a.severity} · ${a.source}', style: const TextStyle(color: Colors.black54)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [Text(a.description, style: const TextStyle(color: Colors.black87))],
          ),
        ),
      );
}

class _HourlyStrip extends StatelessWidget {
  final AppState s;
  final Forecast f;
  const _HourlyStrip({required this.s, required this.f});

  @override
  Widget build(BuildContext context) {
    final hours = f.hourly;
    if (hours.isEmpty) return const SizedBox();
    final temps = hours.map((h) => h.temp).where((t) => !t.isNaN);
    final lo = temps.isEmpty ? 0.0 : temps.reduce(math.min), hi = temps.isEmpty ? 0.0 : temps.reduce(math.max);
    const itemW = 64.0;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: SizedBox(
        height: 196,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          itemCount: hours.length,
          itemBuilder: (context, i) {
            final h = hours[i];
            final newDay = i > 0 && h.time.day != hours[i - 1].time.day;
            final norm = hi == lo || h.temp.isNaN ? 0.5 : (h.temp - lo) / (hi - lo);
            return Container(
              width: itemW,
              decoration: newDay ? BoxDecoration(border: Border(left: BorderSide(color: scheme.outlineVariant))) : null,
              child: Column(children: [
                Text(i == 0 ? 'Now' : DateFormat.H().format(h.time) + (newDay ? '\n' : ''), style: const TextStyle(fontSize: 13)),
                Text(newDay ? DateFormat.E().format(h.time) : ' ', style: TextStyle(fontSize: 11, color: scheme.primary)),
                const SizedBox(height: 4),
                Icon(WeatherCode.icon(h.code, isDay: h.isDay), color: WeatherCode.color(h.code, isDay: h.isDay), size: 26),
                const Spacer(),
                // Temperature position mini-chart.
                SizedBox(
                  height: 44,
                  child: Align(
                    alignment: Alignment(0, 1 - 2 * norm),
                    child: Text(s.temp(h.temp), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.water_drop, size: 11, color: h.precipProb >= 20 ? Colors.blue : scheme.outline),
                  Text(h.precipProb.isNaN ? '' : '${h.precipProb.r}%',
                      style: TextStyle(fontSize: 11, color: h.precipProb >= 20 ? Colors.blue : scheme.outline)),
                ]),
                const SizedBox(height: 2),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Transform.rotate(angle: (h.windDir + 180) * math.pi / 180, child: Icon(Icons.navigation, size: 11, color: scheme.outline)),
                  Text(s.mph ? (h.windSpeed / 1.609344).r : h.windSpeed.r, style: TextStyle(fontSize: 11, color: scheme.outline)),
                ]),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  final AppState s;
  final Forecast f;
  const _DetailsGrid({required this.s, required this.f});

  @override
  Widget build(BuildContext context) {
    final c = f.current;
    final today = f.daily.isNotEmpty ? f.daily.first : null;
    final hm = DateFormat.Hm();
    final tiles = <(IconData, String, String, String?)>[
      (Icons.thermostat, 'Feels like', s.temp(c.feelsLike, unit: true), 'Actual ${s.temp(c.temp, unit: true)}'),
      (Icons.air, 'Wind', s.wind(c.windSpeed), 'From ${compassPoint(c.windDir)} · gusts ${s.wind(c.windGusts)}'),
      (Icons.water_drop_outlined, 'Humidity', '${c.humidity.r}%', 'Cloud cover ${c.cloudCover.r}%'),
      (Icons.umbrella_outlined, 'Precipitation', '${c.precipitation.f1()} mm',
          today == null ? null : 'Today ${today.precipSum.f1()} mm${today.precipProbMax.isNaN ? '' : ' · ${today.precipProbMax.r}% chance'}'),
      (Icons.speed, 'Pressure', '${c.pressure.r} hPa', 'Mean sea level'),
      (Icons.wb_sunny_outlined, 'UV index', c.uv.f1(),
          '${uvCategory(c.uv)}${today != null ? ' · max ${today.uvMax.f1()}' : ''}'),
      (Icons.wb_twilight, 'Sunrise', today?.sunrise == null ? '–' : hm.format(today!.sunrise!), null),
      (Icons.nights_stay_outlined, 'Sunset', today?.sunset == null ? '–' : hm.format(today!.sunset!),
          today?.sunrise != null && today?.sunset != null ? _dayLength(today!.sunset!.difference(today.sunrise!)) : null),
    ];
    return LayoutBuilder(builder: (context, cons) {
      final cols = cons.maxWidth > 560 ? 4 : 2;
      const gap = 10.0;
      final w = (cons.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final t in tiles)
          SizedBox(
            width: w,
            height: 112,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(t.$1, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(t.$2, style: Theme.of(context).textTheme.labelLarge),
                  ]),
                  const Spacer(),
                  Text(t.$3, style: Theme.of(context).textTheme.headlineSmall),
                  if (t.$4 != null)
                    Text(t.$4!, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ),
      ]);
    });
  }

  String _dayLength(Duration d) => 'Daylight ${d.inHours}h ${d.inMinutes % 60}m';
}

class _DailyList extends StatelessWidget {
  final AppState s;
  final Forecast f;
  const _DailyList({required this.s, required this.f});

  @override
  Widget build(BuildContext context) {
    final days = f.daily;
    if (days.isEmpty) return const SizedBox();
    final mins = days.map((d) => d.tMin).where((v) => !v.isNaN), maxs = days.map((d) => d.tMax).where((v) => !v.isNaN);
    final lo = mins.isEmpty ? 0.0 : mins.reduce(math.min);
    final hi = maxs.isEmpty ? 1.0 : maxs.reduce(math.max);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(children: [
        for (var i = 0; i < days.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              SizedBox(
                width: 56,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i == 0 ? 'Today' : DateFormat.E().format(days[i].date), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(DateFormat('d MMM').format(days[i].date), style: TextStyle(fontSize: 11, color: scheme.outline)),
                ]),
              ),
              Icon(WeatherCode.icon(days[i].code), color: WeatherCode.color(days[i].code), size: 26),
              const SizedBox(width: 6),
              SizedBox(
                width: 42,
                child: Text(days[i].precipProbMax >= 10 ? '${days[i].precipProbMax.r}%' : '',
                    style: const TextStyle(fontSize: 12, color: Colors.blue)),
              ),
              SizedBox(width: 36, child: Text(s.temp(days[i].tMin), textAlign: TextAlign.right, style: TextStyle(color: scheme.outline))),
              const SizedBox(width: 8),
              Expanded(child: _RangeBar(lo: lo, hi: hi, a: days[i].tMin, b: days[i].tMax)),
              const SizedBox(width: 8),
              SizedBox(width: 36, child: Text(s.temp(days[i].tMax), style: const TextStyle(fontWeight: FontWeight.w600))),
              if (MediaQuery.sizeOf(context).width > 480)
                SizedBox(
                  width: 110,
                  child: Text('${s.wind(days[i].windMax)} · UV ${days[i].uvMax.r}',
                      textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: scheme.outline)),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _RangeBar extends StatelessWidget {
  final double lo, hi, a, b;
  const _RangeBar({required this.lo, required this.hi, required this.a, required this.b});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (a.isNaN || b.isNaN) return const SizedBox(height: 6);
      final span = (hi - lo).abs() < 0.1 ? 1 : hi - lo;
      final x0 = (a - lo) / span * c.maxWidth, x1 = (b - lo) / span * c.maxWidth;
      return SizedBox(
        height: 6,
        child: Stack(children: [
          Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(3))),
          Positioned(
            left: x0,
            width: math.max(6, x1 - x0),
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [scaleColor(tempStops, a), scaleColor(tempStops, b)]),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ]),
      );
    });
  }
}
