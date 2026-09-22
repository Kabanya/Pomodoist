import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';

const loaderHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const loaderScript = [...loaderHtml.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match => match[1]).find(source => source.includes('const loader ='));
const challengeHtml = await readFile(new URL('../auth/challenge.html', import.meta.url), 'utf8');
const challengeScript = [...challengeHtml.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];
function elements() {
  const nodes = new Map();
  const get = id => {
    if (!nodes.has(id)) nodes.set(id, { hidden: false, textContent: '', listeners: {}, classList: { add() {} },
      addEventListener(event, fn) { this.listeners[event] = fn; }, replaceChildren() {}, remove() {}, querySelector: () => get('indicator') });
    return nodes.get(id);
  };
  return { nodes, get };
}
function load({ query = '', stored = null, languages = ['en'], inaccessibleStorage = false } = {}) {
  const { get } = elements();
  const document = { documentElement: {}, getElementById: get };
  const window = { setTimeout() {}, clearTimeout() {}, location: { reload() {} } };
  vm.runInNewContext(loaderScript, { document, window, URLSearchParams, location: { search: query }, navigator: { languages },
    localStorage: { getItem(key) { if (inaccessibleStorage) throw Error('blocked'); return key === 'flutter.app.language' ? stored : null; } } });
  return { document, window, stage: get('pomodoist-web-loader-stage'), reload: get('pomodoist-web-loader-reload') };
}
test('loader prioritizes valid language query, saved app language, then browser locales', () => {
  for (const [input, expected] of [
    [{ query: '?lang=ko', stored: '"ja"', languages: ['pt-PT'] }, 'ko'],
    [{ query: '?lang=unknown', stored: '"ptBR"', languages: ['ko'] }, 'pt-BR'],
    [{ query: '?lang=ja&lang=ko', stored: '"ptBR"' }, 'pt-BR'],
    [{ stored: '"system"', languages: ['xx', 'pt-PT'] }, 'pt-BR'],
    [{ inaccessibleStorage: true, languages: ['ja-JP'] }, 'ja'],
    [{ stored: '"ko"', languages: ['en'] }, 'ko'],
    [{ stored: '"constructor"', languages: ['unknown'] }, 'en'],
  ]) assert.equal(load(input).document.documentElement.lang, expected);
  for (const language of ['pt-BR', 'ja', 'ko']) {
    const current = load({ query: `?lang=${language}` });
    assert.notEqual(current.stage.textContent, load().stage.textContent);
    current.window.pomodoistShowLoadingFailure();
    assert.ok(current.stage.textContent);
    assert.equal(current.reload.hidden, false);
  }
});
function challenge(query, state = 's'.repeat(32)) {
  const { get } = elements(), scripts = [];
  const location = { pathname: '/auth/challenge', search: query, hash: `#state=${state}`,
    replace(value) { this.href = value; } };
  let turnstileOptions;
  const document = { title: '', documentElement: {}, body: { dataset: {} }, getElementById: get,
    createElement: () => ({}), head: { append: value => scripts.push(value) } };
  vm.runInNewContext(challengeScript, { document, URL, URLSearchParams,
    location, navigator: { languages: ['en'] },
    window: { pomodoistRuntimeConfig: { turnstileSiteKey: 'public-test-key' },
      turnstile: { render(_widget, options) { turnstileOptions = options; return 1; } } },
    requestAnimationFrame(callback) { callback(); }, setTimeout() {}, clearTimeout() {} });
  return { document, scripts, get, location, solve(token) { turnstileOptions.callback(token); } };
}
test('native CAPTCHA accepts every app flavor and returns the token to that exact scheme', () => {
  for (const scheme of ['pomodoist', 'pomodoist-stg', 'pomodoist-dev']) {
    const target = `${scheme}://captcha-callback`;
    const state = '-synthetic_state-for-native-captcha-0123456789';
    const page = challenge(`?returnTo=${encodeURIComponent(target)}&lang=en`, state);
    assert.equal(page.document.body.dataset.status, 'loading', scheme);
    assert.equal(page.scripts.length, 1);
    page.scripts[0].onload();
    assert.equal(page.document.body.dataset.status, 'ready');
    page.solve('opaque-token');
    assert.equal(page.document.body.dataset.status, 'success');
    assert.equal(page.location.href, `${target}?state=${state}&token=opaque-token`);
  }
});
test('native CAPTCHA rejects lookalike schemes and altered callback targets', () => {
  for (const target of [
    'pomodoist-stg-evil://captcha-callback', 'pomodoist-stg://evil.example',
    'pomodoist-stg://captcha-callback/', 'pomodoist-stg://user@captcha-callback',
    'pomodoist-stg://captcha-callback:443', 'pomodoist-stg://captcha-callback?extra=1',
    'pomodoist-stg://captcha-callback#extra',
  ]) {
    const page = challenge(`?returnTo=${encodeURIComponent(target)}&lang=en`);
    assert.equal(page.document.body.dataset.status, 'invalid', target);
    assert.equal(page.scripts.length, 0);
  }
});
test('CAPTCHA translates validated locale and rejects ambiguous or malicious query values', () => {
  const base = '?returnTo=' + encodeURIComponent('pomodoist://captcha-callback');
  for (const language of ['pt-BR', 'ja', 'ko']) {
    const page = challenge(`${base}&lang=${language}`);
    assert.equal(page.document.documentElement.lang, language);
    assert.equal(page.document.body.dataset.status, 'loading');
    assert.equal(page.scripts.length, 1);
    assert.notEqual(page.get('title').textContent, 'Pomodoist security check');
    assert.ok(page.get('return-to-app').textContent);
  }
  for (const query of [`${base}&lang=unknown`, `${base}&lang=ja&lang=ko`, `${base}&extra=1`, `${base}&lang=constructor`, '?returnTo=https://evil.example/&lang=ja']) {
    const page = challenge(query);
    assert.equal(page.document.body.dataset.status, 'invalid');
    assert.equal(page.scripts.length, 0);
  }
  assert.equal(challenge(`${base}&lang=ja`, 'short').document.body.dataset.status, 'invalid');
});
