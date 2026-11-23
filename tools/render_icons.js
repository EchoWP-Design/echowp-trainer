const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [,, dir] = process.argv;
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  const jobs = [
    ['app-icon.svg', 'app-icon-512.png', 512, false],
    ['app-icon.svg', 'app-icon-192.png', 192, false],
    ['app-icon-maskable.svg', 'app-icon-maskable-512.png', 512, false],
    ['app-icon.svg', 'apple-touch-icon.png', 180, true],
    ['app-icon.svg', 'favicon-48.png', 48, false],
  ];
  for (const [src, dst, size, solid] of jobs) {
    const svg = fs.readFileSync(`${dir}/${src}`, 'utf8');
    await p.setViewportSize({ width: size, height: size });
    await p.setContent(`<html><body style="margin:0;background:${solid ? '#0A0A0A' : 'transparent'}"><img src="data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}" width="${size}" height="${size}" style="display:block"></body></html>`);
    await p.screenshot({ path: `${dir}/${dst}`, omitBackground: !solid });
  }
  // Prüfbild: rund, Squircle-Maske, 48 px
  const svgR = fs.readFileSync(`${dir}/app-icon.svg`).toString('base64');
  const svgM = fs.readFileSync(`${dir}/app-icon-maskable.svg`).toString('base64');
  await p.setViewportSize({ width: 900, height: 320 });
  await p.setContent(`<body style="margin:0;background:#777;display:flex;gap:30px;align-items:center;padding:20px">
   <img src="data:image/svg+xml;base64,${svgR}" width="256">
   <div style="width:256px;height:256px;border-radius:60px;overflow:hidden"><img src="data:image/svg+xml;base64,${svgM}" width="256"></div>
   <div style="width:256px;height:256px;border-radius:50%;overflow:hidden"><img src="data:image/svg+xml;base64,${svgM}" width="256"></div>
   <img src="data:image/svg+xml;base64,${svgR}" width="48"></body>`);
  await p.screenshot({ path: process.argv[3] });
  await b.close();
})();
