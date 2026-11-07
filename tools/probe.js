// Probe tiktok.com mobile web with feed-observer.js injected. Usage: node tools/probe.js [url]
const { chromium, devices } = require('playwright');
const fs = require('fs'); const path = require('path');
const SEL = JSON.parse(fs.readFileSync(__dirname + '/../Resources/hide-selectors.json','utf8'));
const JS = fs.readFileSync(__dirname + '/../Resources/feed-observer.js','utf8')
  .replace('__HIDE_SELECTORS__', JSON.stringify(SEL.hide || SEL))
  .replace('__CLICK_SELECTORS__', JSON.stringify(SEL.click || []));
async function touchSwipe(cdp, x, y0, y1, steps = 12) {
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: y0 }] });
  for (let i = 1; i <= steps; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y0 + (y1 - y0) * i / steps }] });
    await new Promise(r => setTimeout(r, 16));
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}
(async () => {
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ ...devices['iPhone 14'], locale: 'en-US', ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  const msgs = [];
  await page.exposeFunction('__tqPost', (m) => msgs.push(m));
  await page.addInitScript(() => { window.webkit = { messageHandlers: { tq: { postMessage: (m) => window.__tqPost(m) } } }; });
  await page.addInitScript(JS);
  const cdp = await ctx.newCDPSession(page);
  await page.goto(process.argv[2] || 'https://www.tiktok.com/@tiktok/video/7106594312292453675', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(6000);
  const popupStill = await page.$('[data-e2e="launch-popup-close"]');
  console.log('launch popup still present after auto-dismiss?', !!popupStill && await popupStill.isVisible().catch(()=>false));
  console.log('observer logs:', JSON.stringify(msgs.filter(m => m.type === 'log').map(m => m.msg)));

  const hidden = await page.evaluate(() => {
    const q = (s) => { const e = document.querySelector(s); return e ? getComputedStyle(e).display : 'absent'; };
    return { bottom_banner: q('[data-e2e="bottom_banner"]'), top_open: q('[data-e2e="top-banner-open"]'), style: !!document.getElementById('__tq_hide') };
  });
  console.log('hide check', JSON.stringify(hidden));
  await page.screenshot({ path: path.join(require('os').tmpdir(), 'tq-probe.png') });

  console.log('before touch scrollY', await page.evaluate(() => scrollY));
  await touchSwipe(cdp, 195, 600, 150);
  await page.waitForTimeout(1500);
  console.log('after touch swipe scrollY', await page.evaluate(() => scrollY), 'videos', await page.evaluate(() => document.querySelectorAll('video').length));
  await page.evaluate(() => scrollTo(0, 0)); await page.waitForTimeout(500);

  const r = await page.evaluate(() => window.__tq.next());
  await page.waitForTimeout(1200);
  console.log('__tq.next() ->', r, 'scrollY', await page.evaluate(() => scrollY), 'innerH', await page.evaluate(() => innerHeight));
  await page.evaluate(() => window.__tq.pause());
  console.log('paused?', await page.evaluate(() => [...document.querySelectorAll('video')].map(v => v.paused)));
  await page.evaluate(() => window.__tq.resume()); await page.waitForTimeout(500);
  console.log('resumed?', await page.evaluate(() => [...document.querySelectorAll('video')].map(v => !v.paused)));
  console.log('video msgs', msgs.filter(m => m.type === 'video').length);
  await browser.close();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
