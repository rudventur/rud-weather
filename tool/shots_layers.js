// Extra checks: temperature+wind layers, radar playback, MET Norway fallback.
const { chromium } = require(process.env.PW_CORE || 'playwright-core');
const base = process.argv[2];
const out = process.argv[3] || '.';
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || undefined, args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const mk = async () => {
    const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
      geolocation: { latitude: 51.5074, longitude: -0.1278 }, permissions: ['geolocation'] });
    const p = await ctx.newPage();
    const logs = [];
    p.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
    p.on('console', (m) => { if (m.type() === 'error') logs.push(`[console.error] ${m.text()}`); });
    p.on('response', (r) => { if (r.status() >= 400) logs.push(`[http ${r.status()}] ${r.url().slice(0, 140)}`); });
    return { ctx, p, logs };
  };
  let { ctx, p, logs } = await mk();
  await p.goto(base + '?tab=map&layers=temp,wind', { waitUntil: 'networkidle', timeout: 90000 });
  await p.waitForTimeout(10000);
  await p.screenshot({ path: `${out}/4-map-temp-wind.png` });
  await ctx.close();
  ({ ctx, p, logs: l2 } = await mk());
  await p.goto(base + '?tab=map&layers=radar', { waitUntil: 'networkidle', timeout: 90000 });
  await p.waitForTimeout(6000);
  // zoom out twice for a wider radar view, then press play
  await p.mouse.click(356, 239); await p.waitForTimeout(500); await p.mouse.click(356, 239);
  await p.waitForTimeout(3000);
  await p.mouse.click(36, 726); // play button
  await p.waitForTimeout(2600);
  await p.screenshot({ path: `${out}/5-map-radar-playing.png` });
  await ctx.close();
  // Fallback: block Open-Meteo forecast API -> MET Norway
  ({ ctx, p, logs: l3 } = await mk());
  await p.route(/api\.open-meteo\.com/, (r) => r.fulfill({ status: 429, contentType: 'application/json', body: '{"error":true,"reason":"Simulated limit"}' }));
  await p.goto(base + '?tab=weather', { waitUntil: 'networkidle', timeout: 90000 });
  await p.waitForTimeout(9000);
  await p.screenshot({ path: `${out}/6-weather-fallback-metno.png` });
  await p.mouse.move(195, 500); await p.mouse.wheel(0, 2000); await p.waitForTimeout(1500);
  await p.screenshot({ path: `${out}/6b-weather-fallback-bottom.png` });
  require('fs').writeFileSync(`${out}/console-layers.log`, [...logs, '---', ...l2, '---', ...l3].join('\n'));
  await b.close();
})().catch((e) => { console.error(e); process.exit(1); });
