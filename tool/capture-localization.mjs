// Automated demo-only captures. Run after building lib/main_demo.dart into build/localization-demo.
import { createServer } from 'node:http';
import { readFile, mkdir, stat, writeFile } from 'node:fs/promises';
import { resolve, extname } from 'node:path';
import { createRequire } from 'node:module';
import { build } from '../apps/chrome-extension/build.mjs';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = resolve(import.meta.dirname, '..'), output = resolve(root, 'output/localization');
await mkdir(output, { recursive: true });
await build({ SUPABASE_URL: 'https://example.test', SUPABASE_ANON_KEY: 'sb_publishable_demo', WEB_APP_URL: 'https://example.test' }, resolve(root, 'build/localization-chrome'));
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.woff2': 'font/woff2' };
const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const base = pathname.startsWith('/chrome/') ? 'build/localization-chrome' : pathname.startsWith('/telegram/') ? 'apps/telegram-mini-app' : 'build/localization-demo';
    const relative = base === 'build/localization-demo' ? pathname : pathname.replace(/^\/(chrome|telegram)/, '');
    let file = resolve(root, base, '.' + relative);
    if (!file.startsWith(resolve(root, base) + '/') && file !== resolve(root, base)) throw new Error('Invalid path');
    if (pathname === '/config.js') { res.writeHead(200, {'Content-Type':'text/javascript'}); res.end('// Local demo: use the built-in local runtime configuration.'); return; }
    try { if ((await stat(file)).isDirectory()) file += '/index.html'; } catch { file = resolve(root, base, 'index.html'); }
    res.writeHead(200, { 'Content-Type': mime[extname(file)] || 'application/octet-stream' }); res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(done => server.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox'] });
const results = [];
try {
  for (const locale of ['pt-BR', 'ja', 'ko']) {
    for (const [name, width, height, dark] of [['desktop',1440,960,false],['phone',430,932,false],['desktop-dark',1440,960,true],['phone-dark',430,932,true]]) {
      const context = await browser.newContext({ locale, viewport: {width,height}, deviceScaleFactor: 1, colorScheme: dark ? 'dark' : 'light', reducedMotion: 'reduce' });
      await context.addInitScript(({locale,dark}) => {
        localStorage.setItem('flutter.app.language', JSON.stringify(locale === 'pt-BR' ? 'ptBR' : locale));
        localStorage.setItem('flutter.onboarding.completed.v1', 'true');
      }, {locale,dark});
      const page = await context.newPage(), errors = [];
      page.on('pageerror', error => { errors.push(error.stack); console.error(error.stack); });
      page.on('console', message => {if(message.type() === 'error') console.error(message.text());});
      await page.goto(`${origin}/today?lang=${locale}`, { waitUntil: 'domcontentloaded' });
      await page.locator('flutter-view').waitFor({timeout:60000});
      await page.locator('#pomodoist-web-loader').waitFor({state:'hidden',timeout:60000});
      await page.waitForTimeout(2500);
      if (errors.length) throw new Error('Flutter demo startup failed: '+errors.join('\n')); 
      const semantics = page.locator('flt-semantics-placeholder');
      if (await semantics.count()) await semantics.evaluate(e => e.click());
      await page.waitForTimeout(500);
      await page.screenshot({ path: `${output}/${locale}-${name}-today.png` });
      results.push({locale, surface:name, errors, text: (await page.locator('body').innerText()).slice(0,3000)});
      await context.close();
    }
    const messages = JSON.parse(await readFile(resolve(root, `apps/chrome-extension/_locales/${locale === 'pt-BR' ? 'pt_BR' : locale}/messages.json`)));
    const context = await browser.newContext({locale,viewport:{width:420,height:620},deviceScaleFactor:2});
    await context.addInitScript(({locale,messages}) => {
      window.chrome = { i18n: { getUILanguage: () => locale, getMessage: (key, substitutions) => {
        let value = messages[key]?.message || ''; for (const [i,v] of [].concat(substitutions || []).entries()) value = value.replaceAll('$'+(i+1), v); return value;
      } }, runtime: { onMessage: {addListener() {}}, sendMessage: async () => ({ok:true,value:{ user:null,records:{},pending:0 }}) } };
    }, {locale,messages});
    const page = await context.newPage();
    await page.goto(`${origin}/chrome/popup.html`); await page.locator('#email').waitFor();
    await page.screenshot({path:`${output}/${locale}-chrome.png`});
    if ((await page.locator('html').getAttribute('lang')) !== locale) throw new Error('Chrome html lang mismatch');
    results.push({locale,surface:'chrome',text:await page.locator('body').innerText()});
    await page.goto(`${origin}/telegram/index.html`); await page.locator('#outside:not([hidden])').waitFor();
    await page.screenshot({path:`${output}/${locale}-telegram.png`});
    if ((await page.locator('html').getAttribute('lang')) !== locale) throw new Error('Telegram html lang mismatch');
    results.push({locale,surface:'telegram',text:await page.locator('body').innerText()});
    await context.close();
  }
  await writeFile(`${output}/capture-results.json`, JSON.stringify(results,null,2)+'\n');
  console.log(`Captured ${results.length} demo-only surfaces in ${output}`);
} finally { await browser.close(); server.close(); }
