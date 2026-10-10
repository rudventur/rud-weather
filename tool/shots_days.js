// Usage: node shots_days.js <baseUrl> <outDir>
const { chromium } = require(process.env.PW_CORE);
const base = process.argv[2], out = process.argv[3];
const fs = require('fs');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/google/chrome/chrome', args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const logs = [];
  const mk = async (vp, mobile) => {
    const ctx = await b.newContext({ viewport: vp, deviceScaleFactor: mobile ? 2 : 1, isMobile: mobile, hasTouch: mobile,
      geolocation: { latitude: 51.5074, longitude: -0.1278 }, permissions: ['geolocation'] });
    const p = await ctx.newPage();
    p.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
    p.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
    p.on('response', (r) => { const u = r.url(); if (r.status() >= 400 || /limaps|blitzortung/.test(u)) logs.push(`[http ${r.status()}] ${u.slice(0, 150)}`); });
    await p.goto(base, { waitUntil: 'load', timeout: 90000 });
    await p.waitForTimeout(14000);
    return p;
  };
  const p = await mk({ width: 390, height: 844 }, true);
  await p.screenshot({ path: `${out}/phone-2-today.png` });
  await p.mouse.wheel(0, 0);
  const y = parseInt(process.env.SEG_Y || '78');
  await p.mouse.click(70, y); await p.waitForTimeout(6000);
  await p.screenshot({ path: `${out}/phone-1-yesterday.png` });
  await p.mouse.click(320, y); await p.waitForTimeout(4000);
  await p.screenshot({ path: `${out}/phone-3-tomorrow.png` });
  await p.mouse.click(195, y); await p.waitForTimeout(3000);
  await p.mouse.move(195, 740); await p.mouse.wheel(0, 500); await p.waitForTimeout(3000);
  await p.screenshot({ path: `${out}/phone-2b-today-scrolled.png` });
  const d = await mk({ width: 1280, height: 800 }, false);
  await d.screenshot({ path: `${out}/desktop-all-three.png` });
  fs.writeFileSync(`${out}/console.log`, logs.join('\n'));
  await b.close();
})();
