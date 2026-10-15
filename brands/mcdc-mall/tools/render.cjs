const { chromium } = require(process.env.PW);
(async () => {
  const [html, out] = process.argv.slice(2);
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  await page.goto('file://' + html, { waitUntil: 'load', timeout: 15000 }).catch(e => console.log('load:', e.message));
  await page.locator('.slide').screenshot({ path: out });
  await browser.close();
})();
