import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/news.dart';
import '../services/api.dart';

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat('d MMM').format(t);
}

Future<void> openLink(String url) => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  NewsFeed? _feed;
  String? _error;
  bool _loading = true;
  String? _source; // filter

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final f = await WeatherApi.news();
      if (!mounted) return;
      setState(() {
        _feed = f;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _feed;
    final sources = f == null ? <String>[] : (f.items.map((e) => e.source).toSet().toList()..sort());
    final items = f == null ? <NewsItem>[] : f.items.where((e) => _source == null || e.source == _source).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather news'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
        bottom: _loading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(builder: (context, c) {
          final pad = c.maxWidth > 760 ? (c.maxWidth - 720) / 2 : 12.0;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
            children: [
              if (_error != null && f == null)
                Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Could not load news.\n$_error'))),
              if (f != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Updated ${timeAgo(f.generatedAt)} · ${f.items.length} stories from ${f.sourcesOk} feeds · refreshed hourly',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final a in f.alerts) _AlertTile(a: a),
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: const Text('All'), selected: _source == null, onSelected: (_) => setState(() => _source = null)),
                    ),
                    for (final s in sources)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: Text(s), selected: _source == s, onSelected: (_) => setState(() => _source = _source == s ? null : s)),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                for (final it in items) _NewsCard(item: it),
                if (items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('No stories right now.', textAlign: TextAlign.center)),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final NewsItem a;
  const _AlertTile({required this.a});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          color: Colors.orange.shade100,
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
            title: Text(a.title, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
            subtitle: Text('${a.source} · ${timeAgo(a.published)}', style: const TextStyle(color: Colors.black54)),
            onTap: () => openLink(a.link),
          ),
        ),
      );
}

class _NewsCard extends StatelessWidget {
  final NewsItem item;
  const _NewsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openLink(item.link),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (item.summary.isNotEmpty)
                    Text(item.summary, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    Flexible(child: Text(item.source, style: t.labelSmall?.copyWith(color: scheme.primary), overflow: TextOverflow.ellipsis)),
                    Text('  ·  ${timeAgo(item.published)}', style: t.labelSmall?.copyWith(color: scheme.outline)),
                    const SizedBox(width: 4),
                    Icon(Icons.open_in_new, size: 12, color: scheme.outline),
                  ]),
                ]),
              ),
              if (item.image != null) ...[
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    item.image!,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    // Most news CDNs send no CORS headers; fall back to an <img> element.
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (_, _, _) => const SizedBox(width: 88, height: 88),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
