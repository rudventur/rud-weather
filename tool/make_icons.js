// Renders the app icon SVG to PNGs using headless Chrome (playwright-core).
const { chromium } = require('/workspace/pwtest/node_modules/playwright-core');
const path = require('path');
function svg(size, scale, rounded) {
  const r = rounded ? size * 0.22 : 0;
  const g = (size * (1 - scale)) / 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2F80ED"/><stop offset="1" stop-color="#0B3D91"/></linearGradient>
  <radialGradient id="sun" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFE259"/><stop offset="1" stop-color="#FFA751"/></radialGradient></defs>
  <rect width="${size}" height="${size}" rx="${r}" fill="url(#bg)"/>
  <g transform="translate(${g} ${g}) scale(${(size * scale) / 100})">
    <g stroke="#FFD24D" stroke-width="3.2" stroke-linecap="round">
      ${[0,45,90,135,180,225,270,315].map(a=>{const rad=a*Math.PI/180;const x1=38+Math.cos(rad)*21,y1=38+Math.sin(rad)*21,x2=38+Math.cos(rad)*28,y2=38+Math.sin(rad)*28;return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`}).join('')}
    </g>
    <circle cx="38" cy="38" r="16" fill="url(#sun)"/>
    <path d="M30 80 h44 a14 14 0 0 0 0-28 a19 19 0 0 0-36-4 a13 13 0 0 0-8 32 z" fill="#FFFFFF"/>
    <g stroke="#9ED0FF" stroke-width="3.5" stroke-linecap="round"><line x1="40" y1="86" x2="37" y2="94"/><line x1="54" y1="86" x2="51" y2="94"/><line x1="68" y1="86" x2="65" y2="94"/></g>
  </g></svg>`;
}
(async () => {
  const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome' });
  const p = await b.newPage();
  const out = path.join(__dirname, '..', 'web');
  const jobs = [
    ['icons/Icon-192.png', 192, 0.86, true], ['icons/Icon-512.png', 512, 0.86, true],
    ['icons/Icon-maskable-192.png', 192, 0.62, false], ['icons/Icon-maskable-512.png', 512, 0.62, false],
    ['icons/apple-touch-icon.png', 180, 0.78, false], ['favicon.png', 32, 0.95, true], ['icons/favicon-96.png', 96, 0.9, true],
  ];
  for (const [f, s, sc, rd] of jobs) {
    await p.setViewportSize({ width: s, height: s });
    await p.setContent(`<html><body style="margin:0;background:transparent">${svg(s, sc, rd)}</body></html>`);
    await p.screenshot({ path: path.join(out, f), omitBackground: true, clip: { x: 0, y: 0, width: s, height: s } });
  }
  await b.close();
})();
