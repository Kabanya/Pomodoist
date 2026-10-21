// Run with node tool/test_app_icon_web.mjs from apps/flutter.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../web/index.html', import.meta.url), 'utf8');
const source = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map((match) => match[1]).find((script) => script.includes('const flavors ='));
assert.ok(source);

function page(environment) {
  const links = Object.fromEntries(['icon', 'manifest', 'apple-touch-icon']
    .map((rel) => [rel, { href: '' }]));
  const meta = {};
  let completeManifest;
  const manifest = new Promise((resolve, reject) => {
    completeManifest = (success) => success
      ? resolve({ ok: true, json: async () => ({ icons: [{ sizes: '192x192', src: 'loaded.png' }] }) })
      : reject(new Error('offline'));
  });
  const window = { pomodoistBuildEnvironment: environment };
  const document = {
    documentElement: { dataset: {} },
    head: {
      querySelector(selector) {
        const name = selector.match(/"([^"]+)"/)[1];
        return selector.startsWith('link') ? links[name] : meta[name];
      },
      append(element) { meta[element.name] = element; },
    },
    createElement() { return {}; },
  };
  class Image {
    set src(_) { queueMicrotask(() => this.onload()); }
  }
  vm.runInNewContext(source, { window, document, Image, fetch: () => manifest });
  return { window, links, completeManifest };
}

const production = page('production');
assert.equal(production.links.icon.href, 'favicon.png');
production.window.pomodoistSetAppIcon('classic', 'production');
assert.equal(production.links.icon.href, 'icons/production/classic.png');
production.window.pomodoistSetAppIcon('icon-light-pomo', 'production');
assert.equal(production.links.icon.href, 'favicon.png');
assert.throws(() => production.window.pomodoistSetAppIcon('unknown', 'production'));
assert.throws(() => production.window.pomodoistSetAppIcon('classic', 'toString'));

for (const environment of ['local', 'staging']) {
  const flavor = environment === 'local' ? 'development' : environment;
  for (const success of [true, false]) {
    const current = page(environment);
    current.window.pomodoistSetAppIcon('classic', flavor);
    current.completeManifest(success);
    await new Promise(setImmediate);
    assert.equal(current.links.icon.href, `icons/${flavor}/classic.png`);
    current.window.pomodoistSetAppIcon('icon-light-pomo', flavor);
    assert.equal(current.links.icon.href, `icons/${flavor}/favicon.png`);
  }
}
console.log('Web icon defaults, selection validation and delayed manifest success/failure passed.');
