// Usage: node shots.js <baseUrl> <outDir>   (phone viewport 390x844)
const { chromium } = require(process.env.PW_CORE ? require('path').resolve(process.env.PW_CORE.startsWith('/') ? process.env.PW_CORE : 'node_modules/' + process.env.PW_CORE) : 'playwright-core');
const base = process.argv[2];
const out = process.argv[3] || '.';
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROME || undefined, args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
    geolocation: { latitude: 51.5074, longitude: -0.1278 }, permissions: ['geolocation'],
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1' });
  const p = await ctx.newPage();
  const logs = [];
  p.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
  p.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  p.on('requestfailed', (r) => logs.push(`[reqfail] ${r.url().slice(0, 120)} ${r.failure()?.errorText}`));
  p.on('response', (r) => { if (r.status() >= 400) logs.push(`[http ${r.status()}] ${r.url().slice(0, 140)}`); });
  await p.goto(base, { waitUntil: 'networkidle', timeout: 90000 });
  await p.waitForTimeout(9000);
  await p.screenshot({ path: `${out}/1-weather.png` });
  // Scroll the weather page to show hourly/details/daily
  await p.mouse.move(195, 500);
  await p.mouse.wheel(0, 700);
  await p.waitForTimeout(1500);
  await p.screenshot({ path: `${out}/1b-weather-details.png` });
  await p.mouse.wheel(0, 900);
  await p.waitForTimeout(1500);
  await p.screenshot({ path: `${out}/1c-weather-7day.png` });
  // Map tab: nav bar at bottom, 3 destinations
  await p.mouse.click(195, 812);
  await p.waitForTimeout(8000);
  await p.screenshot({ path: `${out}/2-map-radar.png` });
  // Tap on the map for point weather
  await p.mouse.click(160, 330);
  await p.waitForTimeout(6000);
  await p.screenshot({ path: `${out}/2b-map-tap.png` });
  // News tab
  await p.mouse.click(325, 812);
  await p.waitForTimeout(6000);
  await p.screenshot({ path: `${out}/3-news.png` });
  require('fs').writeFileSync(`${out}/console.log`, logs.join('\n'));
  await b.close();
})().catch((e) => { console.error(e); process.exit(1); });
