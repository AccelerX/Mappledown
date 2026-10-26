// Renders a Markdown file with the app's own preview page in Chromium and
// reports math errors. Usage: node scripts/preview-test.js <file.md> [out.png] [dark]
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

(async () => {
  const mdPath = process.argv[2] || path.join(__dirname, '../Mappledown/Resources/Samples/Math stress test.md');
  const out = process.argv[3];
  const dark = process.argv[4] === 'dark';
  const page = await (await chromium.launch()).newPage({ viewport: { width: 820, height: 1000 } });
  const logs = [];
  page.on('console', (m) => logs.push(m.text()));
  page.on('pageerror', (e) => logs.push('PAGE ERROR ' + e.message));
  await page.addInitScript((d) => { window.MAPPLEDOWN_CONFIG = { dark: d }; }, dark);
  await page.goto('file://' + path.join(__dirname, '../Mappledown/Resources/Web/preview.html'));
  await page.waitForFunction(() => window.MathJax && MathJax.startup && MathJax.startup.promise);
  await page.evaluate(() => MathJax.startup.promise);
  await page.evaluate((t) => Mappledown.render(t), fs.readFileSync(mdPath, 'utf8'));
  await page.waitForFunction(() => Mappledown.isReady(), null, { timeout: 30000 });
  const r = await page.evaluate(() => {
    const el = document.getElementById('content');
    return {
      math: el.querySelectorAll('mjx-container').length,
      display: el.querySelectorAll('mjx-container[display="true"]').length,
      errors: [...el.querySelectorAll('mjx-merror, [data-mml-node="merror"]')].map((e) => e.getAttribute('data-mjx-error') || e.textContent),
      leftoverDollars: [...el.querySelectorAll('p, li, td')].filter((e) => !e.closest('code') && /\$[^\s$]/.test(e.innerText)).map((e) => e.innerText.slice(0, 80)),
      eqNumbers: [...el.querySelectorAll('mjx-container')].map((c) => c.textContent).length
    };
  });
  console.log(JSON.stringify(r, null, 2));
  if (logs.length) console.log('console:', logs.join('\n'));
  if (out) await page.screenshot({ path: out, fullPage: true });
  process.exit(0);
})();
