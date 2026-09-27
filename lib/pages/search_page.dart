import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/place.dart';
import '../services/api.dart';

/// Full-screen city search (Open-Meteo geocoding). Pops with the chosen [Place].
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  static Future<Place?> open(BuildContext context) =>
      Navigator.of(context).push<Place>(MaterialPageRoute(builder: (_) => const SearchPage(), fullscreenDialog: true));

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    if (q.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await WeatherApi.search(q);
      if (seq != _seq || !mounted) return;
      setState(() {
        _results = r;
        _error = r.isEmpty ? 'No places found for "$q"' : null;
      });
    } catch (e) {
      if (seq == _seq && mounted) setState(() => _error = e.toString());
    } finally {
      if (seq == _seq && mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final showFavs = _ctl.text.trim().length < 2;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Search city or place…', border: InputBorder.none),
          onChanged: _onChanged,
          onSubmitted: _run,
        ),
        actions: [
          if (_ctl.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.clear), onPressed: () {
              _ctl.clear();
              _run('');
            }),
        ],
        bottom: _loading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              if (showFavs) ...[
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: const Text('Use my current location'),
                  onTap: () {
                    s.useMyLocation();
                    Navigator.pop(context);
                  },
                ),
                if (s.favourites.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Saved places')),
                for (final p in s.favourites)
                  ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: Text(p.name),
                    subtitle: p.subtitle.isEmpty ? null : Text(p.subtitle),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
              for (final p in _results)
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(p.name),
                  subtitle: Text([p.subtitle, Place.coordLabel(p.lat, p.lon)].where((e) => e.isNotEmpty).join(' · ')),
                  trailing: IconButton(
                    icon: Icon(s.isFavourite(p) ? Icons.star : Icons.star_border, color: s.isFavourite(p) ? Colors.amber : null),
                    tooltip: 'Save place',
                    onPressed: () => s.toggleFavourite(p),
                  ),
                  onTap: () => Navigator.pop(context, p),
                ),
              if (!showFavs && _results.isNotEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Search by Open-Meteo Geocoding API', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }
}
