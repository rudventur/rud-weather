// Fetches real weather news feeds, keeps weather-related items, dedupes,
// sorts newest-first and writes ../../web/news.json (served by GitHub Pages).
import { XMLParser } from 'fast-xml-parser';
import { writeFileSync, readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const OUT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../web/news.json');
const UA = 'Mozilla/5.0 (compatible; rud-weather-news/1.0; +https://github.com/rudventur/rud-weather)';

// filter: true => only keep items that look weather-related.
const FEEDS = [
  { name: 'The Guardian – Weather', url: 'https://www.theguardian.com/uk/weather/rss', filter: false },
  { name: 'Severe Weather Europe', url: 'https://www.severe-weather.eu/feed/', filter: false },
  { name: 'CBS News – Weather', url: 'https://www.cbsnews.com/latest/rss/weather', filter: false },
  { name: 'BBC News – Science & Environment', url: 'https://feeds.bbci.co.uk/news/science_and_environment/rss.xml', filter: true },
  { name: 'BBC News – UK', url: 'https://feeds.bbci.co.uk/news/uk/rss.xml', filter: true },
  { name: 'NASA Earth Observatory', url: 'https://earthobservatory.nasa.gov/feeds/natural-hazards.rss', filter: true },
  { name: 'NOAA', url: 'https://www.noaa.gov/rss.xml', filter: true },
  { name: 'National Weather Service', url: 'https://www.weather.gov/rss_page.php?site_name=nws', filter: false },
  { name: 'NHC – Atlantic', url: 'https://www.nhc.noaa.gov/index-at.xml', filter: false, kind: 'nhc' },
  { name: 'NHC – Eastern Pacific', url: 'https://www.nhc.noaa.gov/index-ep.xml', filter: false, kind: 'nhc' },
  { name: 'Yale Climate Connections', url: 'https://www.yaleclimateconnections.org/feed/', filter: true },
  { name: 'NYT – Climate', url: 'https://rss.nytimes.com/services/xml/rss/nyt/Climate.xml', filter: true },
  { name: 'Sky News – UK', url: 'https://feeds.skynews.com/feeds/rss/uk.xml', filter: true },
  { name: 'EUMETSAT', url: 'https://www.eumetsat.int/rss.xml', filter: true },
];
const ALERT_FEEDS = [
  { name: 'Met Office – UK warnings', url: 'https://www.metoffice.gov.uk/public/data/PWSCache/WarningsRSS/Region/UK' },
];

const WEATHER_RE = new RegExp(
  '\\b(weather|forecasts?|forecasters?|storms?|stormy|hurricanes?|typhoons?|cyclones?|tropical (storm|depression)|tornado(es)?|twisters?|' +
  'floods?|flooding|flash flood|rain|rainfall|downpours?|showers|snow|snowfall|blizzards?|sleet|hail|thunder(storms?)?|lightning|' +
  'heatwaves?|heat wave|heat dome|extreme heat|hottest|record heat|temperatures?|drought|wildfires?|bushfires?|monsoon|gales?|' +
  'strong winds|high winds|gusts|frost|fog|ice storm|cold snap|el ni[nñ]o|la ni[nñ]a|met office|meteorolog\\w*|atmospher\\w*|' +
  'polar vortex|jet stream|dust storm|wildfire smoke|air quality|sea ice)\\b', 'i');

const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@', textNodeName: '#text', cdataPropName: false, trimValues: true, processEntities: false, htmlEntities: false });

const text = (v) => {
  if (v == null) return '';
  if (typeof v === 'string' || typeof v === 'number') return String(v);
  if (Array.isArray(v)) return text(v[0]);
  if (typeof v === 'object') return text(v['#text'] ?? '');
  return '';
};
const decode = (s) => s
  .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n))
  .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
  .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&rsquo;|&lsquo;/g, "'").replace(/&ldquo;|&rdquo;/g, '"')
  .replace(/&ndash;/g, '–').replace(/&mdash;/g, '—').replace(/&hellip;/g, '…');
const stripHtml = (s) => decode(String(s).replace(/<script[\s\S]*?<\/script>/gi, '').replace(/<style[\s\S]*?<\/style>/gi, '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
const clip = (s, n) => (s.length > n ? s.slice(0, n - 1).replace(/\s+\S*$/, '') + '…' : s);

function pickLink(item) {
  const l = item.link;
  if (typeof l === 'string') return l;
  if (Array.isArray(l)) {
    const alt = l.find((x) => typeof x === 'object' && (x['@rel'] ?? 'alternate') === 'alternate') ?? l[0];
    return typeof alt === 'string' ? alt : alt?.['@href'] ?? '';
  }
  if (l && typeof l === 'object') return l['@href'] ?? text(l);
  return text(item.guid);
}
function pickImage(item, rawDesc) {
  const arr = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);
  for (const m of [...arr(item['media:content']), ...arr(item['media:group']?.['media:content'])]) {
    if (m?.['@url'] && (!m['@medium'] || m['@medium'] === 'image') && !/\.(mp4|mp3)$/i.test(m['@url'])) return m['@url'];
  }
  for (const m of arr(item['media:thumbnail'])) if (m?.['@url']) return m['@url'];
  for (const e of arr(item.enclosure)) if (e?.['@url'] && /^image\//.test(e['@type'] ?? 'image/')) return e['@url'];
  const m = /<img[^>]+src=["']([^"']+)["']/i.exec(rawDesc || '');
  return m ? decode(m[1]) : null;
}
function parseDate(item) {
  const raw = text(item.pubDate) || text(item.published) || text(item.updated) || text(item['dc:date']);
  const d = raw ? new Date(raw.replace(/\bUTC\b/, 'GMT')) : null;
  return d && !isNaN(d) ? d : null;
}

async function fetchFeed(feed) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 20000);
  try {
    const res = await fetch(feed.url, { headers: { 'User-Agent': UA, Accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*' }, signal: ctl.signal, redirect: 'follow' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const xml = await res.text();
    const doc = parser.parse(xml);
    const items = doc?.rss?.channel?.item ?? doc?.feed?.entry ?? doc?.['rdf:RDF']?.item ?? [];
    return (Array.isArray(items) ? items : [items]).map((it) => {
      const rawDesc = text(it.description) || text(it.summary) || text(it.content) || text(it['content:encoded']);
      return {
        title: clip(stripHtml(text(it.title)), 220),
        link: decode(pickLink(it).trim()),
        source: feed.name,
        published: parseDate(it),
        summary: clip(stripHtml(rawDesc), 300),
        image: pickImage(it, rawDesc + text(it['content:encoded'])),
      };
    }).filter((x) => x.title && /^https?:\/\//.test(x.link));
  } finally { clearTimeout(t); }
}

const normTitle = (s) => s.toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim();
const normLink = (s) => s.replace(/[?#].*$/, '').replace(/\/$/, '').replace(/^http:/, 'https:');

async function main() {
  const now = Date.now();
  const maxAge = 30 * 24 * 3600 * 1000;
  const sources = [];
  let all = [];
  const results = await Promise.allSettled(FEEDS.map(fetchFeed));
  results.forEach((r, i) => {
    const f = FEEDS[i];
    if (r.status === 'rejected') { sources.push({ name: f.name, url: f.url, ok: false, count: 0, error: String(r.reason?.message ?? r.reason) }); return; }
    let items = r.value;
    if (f.filter) items = items.filter((x) => WEATHER_RE.test(`${x.title} ${x.summary}`));
    if (f.kind === 'nhc') items = items.filter((x) => /^summary for|tropical weather outlook/i.test(x.title));
    items = items.slice(0, 15);
    items = items.filter((x) => x.published && now - x.published.getTime() < maxAge && x.published.getTime() < now + 3600e3);
    sources.push({ name: f.name, url: f.url, ok: true, count: items.length });
    all.push(...items);
  });

  const seenL = new Set(), seenT = new Set();
  all.sort((a, b) => b.published - a.published);
  all = all.filter((x) => {
    const l = normLink(x.link), t = normTitle(x.title);
    if (seenL.has(l) || seenT.has(t)) return false;
    seenL.add(l); seenT.add(t); return true;
  }).slice(0, 120);

  const alerts = [];
  for (const f of ALERT_FEEDS) {
    try {
      const items = await fetchFeed(f);
      alerts.push(...items.map((x) => ({ ...x, published: x.published?.toISOString() ?? null })));
      sources.push({ name: f.name, url: f.url, ok: true, count: items.length, alerts: true });
    } catch (e) { sources.push({ name: f.name, url: f.url, ok: false, count: 0, alerts: true, error: String(e.message ?? e) }); }
  }

  const okCount = sources.filter((s) => s.ok && !s.alerts).length;
  if (all.length === 0 || okCount === 0) {
    console.error('No news fetched; keeping previous news.json if present.');
    if (existsSync(OUT)) { console.log(readFileSync(OUT, 'utf8').slice(0, 200)); return; }
  }
  const out = {
    generatedAt: new Date().toISOString(),
    count: all.length,
    sources,
    alerts,
    items: all.map((x) => ({ ...x, published: x.published.toISOString() })),
  };
  writeFileSync(OUT, JSON.stringify(out, null, 1));
  console.log(`Wrote ${all.length} items (${alerts.length} alerts) to ${OUT}`);
  for (const s of sources) console.log(`${s.ok ? 'OK ' : 'ERR'} ${String(s.count).padStart(3)}  ${s.name}${s.error ? '  ' + s.error : ''}`);
}
main().catch((e) => { console.error(e); process.exit(1); });
