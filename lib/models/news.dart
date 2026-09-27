class NewsItem {
  final String title, link, source, summary;
  final String? image;
  final DateTime? published;

  NewsItem({required this.title, required this.link, required this.source, required this.summary, this.image, this.published});

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        title: j['title'] as String? ?? '',
        link: j['link'] as String? ?? '',
        source: j['source'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        image: (j['image'] as String?)?.isEmpty ?? true ? null : j['image'] as String,
        published: j['published'] == null ? null : DateTime.tryParse(j['published'] as String)?.toLocal(),
      );
}

class NewsFeed {
  final DateTime? generatedAt;
  final List<NewsItem> items;
  final List<NewsItem> alerts;
  final int sourcesOk, sourcesTotal;
  NewsFeed(this.generatedAt, this.items, this.alerts, this.sourcesOk, this.sourcesTotal);

  factory NewsFeed.fromJson(Map<String, dynamic> j) {
    final sources = (j['sources'] as List? ?? const []).cast<Map<String, dynamic>>();
    return NewsFeed(
      j['generatedAt'] == null ? null : DateTime.tryParse(j['generatedAt'] as String)?.toLocal(),
      (j['items'] as List? ?? const []).map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList(),
      (j['alerts'] as List? ?? const []).map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList(),
      sources.where((s) => s['ok'] == true && s['alerts'] != true).length,
      sources.where((s) => s['alerts'] != true).length,
    );
  }
}
