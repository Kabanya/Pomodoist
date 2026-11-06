// Reuse the existing Editorial Signal templates; never draw app UI here.
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { createHash } = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const { chromium } = require('playwright');
const sharp = require('sharp');
const config = require('./store-screenshots.json');
const assetRoot = path.resolve(process.env.STORE_OUTPUT || path.join(root, 'design/app-store/localized'));
const locales = config.locales;
const slides = config.slides.map(([name, route, title, subtitle]) => [name, title, subtitle]);
const configurations = config.devices;
async function readJson(file) { return JSON.parse(await fs.readFile(file, 'utf8')); }
async function catalog(locale) {
  const language = { 'en-US': 'en', 'de-DE': 'de', 'es-ES': 'es', 'fr-FR': 'fr', 'ar-SA': 'ar', 'zh-Hans': 'zh', 'pt-BR': 'pt' }[locale] || locale;
  const folder = path.join(root, 'apps/flutter/lib/ui/core/localization');
  const base = await readJson(path.join(folder, `app_${language}.arb`));
  return locale === 'pt-BR' ? { ...base, ...await readJson(path.join(folder, 'app_pt_BR.arb')) } : base;
}
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--allow-file-access-from-files'] });
  const results = [];
  try {
    for (const device of (process.env.STORE_RENDER_DEVICES || 'iphone').split(',')) {
      const config = configurations[device];
      assert(config, `Unknown device: ${device}`);
      const [width, height] = config.canvas;
      for (const locale of (process.env.STORE_RENDER_LOCALES || locales.join(',')).split(',')) {
        assert(locales.includes(locale), `Unknown locale: ${locale}`);
        const copy = await catalog(locale);
        const series = device === 'watch' ? [
          ['01-voice-input', 'addTask', ''], ['02-tasks', 'navToday', ''], ['03-focus', 'navFocus', ''],
        ] : slides;
        const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1, reducedMotion: 'reduce', locale });
        await page.route(/^https?:/, route => route.abort());
        try {
          const folder = path.join(assetRoot, device, locale);
          await fs.mkdir(folder, { recursive: true });
          for (const [name, titleKey, subtitleKey] of series) {
            const uiLocale = process.env.STORE_UI_LOCALE === 'localized' ? locale : (process.env.STORE_UI_LOCALE || 'en-US');
            assert(locales.includes(uiLocale), `Unknown UI locale: ${uiLocale}`);
            const source = path.join(assetRoot, 'raw', device, uiLocale, `${name}.png`);
            const sourceData = await fs.readFile(source);
            const sourceMeta = await sharp(sourceData).metadata();
            assert.equal(sourceMeta.width, config.output[0], `Raw capture width: ${source}`);
            assert.equal(sourceMeta.height, config.output[1], `Raw capture height: ${source}`);
            const provenance = await readJson(source.replace(/\.png$/, '.json'));
            assert.equal(provenance.locale, uiLocale);
            assert.equal(provenance.device, device);
            assert(provenance.texts.length, `${source}: no localized text evidence`);
            const title = copy[titleKey], subtitle = subtitleKey ? copy[subtitleKey] : '';
            assert(title && typeof title === 'string');
            await page.goto(pathToFileURL(path.join(__dirname, 'templates', config.template, 'template.html')).href + '?slide=focus');
            await page.evaluate(({ title, subtitle, source, rtl, width, height, device, locale }) => {
              document.documentElement.lang = locale;
              document.querySelector('.slide').dataset.slide = 'localized';
              document.querySelector('h1').textContent = title;
              document.querySelector('.copy p').textContent = subtitle;
              const copy = document.querySelector('.copy');
              copy.style.direction = rtl ? 'rtl' : 'ltr';
              copy.style.textAlign = rtl ? 'right' : 'left';
              const margin = device === 'watch' ? 20 : device === 'iphone' ? 80 : 160;
              copy.style.width = `${width - 2 * margin}px`;
              copy.style.left = `${margin}px`;
              copy.style.top = device === 'watch' ? '18px' : device === 'iphone' ? '112px' : '112px';
              for (const extra of document.querySelectorAll('.focus-inset,.theme-labels,.calendar-themes,.calendar-dark,.calendar-forest,.forest')) extra.remove();
              const image = document.querySelector('.screen img, .screen-clip img');
              for (const other of document.querySelectorAll('.screen img,.screen-clip img')) if (other !== image) other.remove();
              image.src = source;
              image.style.cssText = 'display:block;position:relative;inset:auto;left:0;top:0;width:100%;height:auto;object-fit:contain';
              const screen = document.querySelector('.screen, .screen-shell');
              if (device === 'mac' || device === 'ipad') {
                screen.style.cssText += `;left:${margin}px;top:510px;width:${width - margin * 2}px;height:${height - 540}px;`;
                image.style.height = '100%';
              } else if (device === 'iphone') {
                screen.style.aspectRatio = '1206 / 2622';
              }
              const heading = document.querySelector('h1');
              heading.style.whiteSpace = 'normal';
              heading.style.overflowWrap = 'normal';
              const text = document.querySelector('.copy p');
              text.style.maxWidth = '100%';
              text.style.whiteSpace = 'normal';
            }, { title, subtitle, source: pathToFileURL(source).href, rtl: locale === 'ar-SA', width, height, device, locale });
            await page.evaluate(() => document.fonts.ready);
            await page.waitForFunction(() => [...document.images].every(image => image.complete && image.naturalWidth));
            const measurements = await page.evaluate(({ device }) => {
              const heading = document.querySelector('h1'), paragraph = document.querySelector('.copy p'), copy = document.querySelector('.copy');
              const screen = document.querySelector('.screen, .screen-shell').getBoundingClientRect();
              let size = device === 'watch' ? 40 : device === 'iphone' ? 142 : 180;
              const minimum = device === 'watch' ? 22 : device === 'iphone' ? 80 : 88;
              for (; size >= minimum; size -= device === 'watch' ? 1 : 2) {
                heading.style.fontSize = `${size}px`;
                if (heading.scrollWidth <= heading.clientWidth + 1 && copy.getBoundingClientRect().bottom <= screen.top - (device === 'watch' ? 4 : 32)) break;
              }
              if (size < minimum) throw Error(`Localized text does not fit: ${heading.textContent}`);
              if (paragraph.scrollWidth > paragraph.clientWidth + 1) throw Error('Subtitle overflow');
              const image = document.querySelector('.screen img, .screen-clip img');
              const box = image.getBoundingClientRect();
              const renderedAspect = image.style.height === '100%' ? image.naturalWidth / image.naturalHeight : box.width / box.height;
              if (Math.abs(renderedAspect - image.naturalWidth / image.naturalHeight) > .002) throw Error('Distorted app capture');
              return { title: heading.textContent, subtitle: paragraph.textContent, fontSize: size, captionBottom: copy.getBoundingClientRect().bottom, screenTop: screen.top };
            }, { device });
            const file = path.join(folder, `${name}.png`);
            await sharp(await page.screenshot({ animations: 'disabled' })).resize(...config.output, { fit: 'cover' }).flatten({ background: '#df382f' }).removeAlpha().withIccProfile('srgb').png().toFile(file);
            const meta = await sharp(file).metadata(), stats = await sharp(file).stats();
            assert.equal(meta.width, config.output[0]); assert.equal(meta.height, config.output[1]);
            assert.equal(meta.hasAlpha, false); assert.equal(meta.space, 'srgb'); assert.equal(meta.depth, 'uchar');
            assert(stats.entropy > 1, `Empty output: ${file}`);
            results.push({ device, locale, uiLocale, file: path.relative(assetRoot, file), source: path.relative(assetRoot, source), sourceSha256: createHash('sha256').update(sourceData).digest('hex'), sha256: createHash('sha256').update(await fs.readFile(file)).digest('hex'), ...measurements });
          }
          console.log(`${device}/${locale}: ${series.length} localized opaque PNGs passed`);
        } finally { await page.close(); }
      }
    }
    assert.equal(new Set(results.map(row => row.sha256)).size, results.length, 'Duplicate localized images');
    await fs.writeFile(path.join(assetRoot, 'render-checks.json'), JSON.stringify({ browser: browser.version(), sharp: sharp.versions.sharp, results }, null, 2) + '\n');
    console.log(`PASS: ${results.length} exported images`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
