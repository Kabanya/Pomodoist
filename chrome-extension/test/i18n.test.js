import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { text, localize } from '../src/i18n.js';
import { parseChallenge } from '../../web/auth/extension-challenge.js';

test('native Chrome messages translate UI, status, errors and placeholders', async () => {
  try {
    for (const locale of ['pt_BR', 'ja', 'ko']) {
      const messages = JSON.parse(await readFile(new URL(`../_locales/${locale}/messages.json`, import.meta.url), 'utf8'));
      globalThis.chrome = { i18n: { getMessage: key => messages[key]?.message || '', getUILanguage: () => locale.replace('_', '-') } };
      assert.notEqual(text('Session expired. Sign in again.'), 'Session expired. Sign in again.');
      assert.ok(text('{count} changes saved locally · waiting to sync', { count: 3 }).includes('3'));
      const label = { dataset: { i18n: 'Title' } };
      const input = { attrs: { placeholder: 'Add a task…', 'aria-label': 'New task title' },
        hasAttribute(key) { return key in this.attrs; }, getAttribute(key) { return this.attrs[key]; }, setAttribute(key, value) { this.attrs[key] = value; } };
      const document = { documentElement: {}, querySelectorAll: selector => selector === '[data-i18n]' ? [label] : [input] };
      localize(document);
      assert.equal(label.textContent, messages.title.message);
      assert.equal(input.attrs.placeholder, messages.add_a_task.message);
      assert.equal(document.documentElement.lang, locale.replace('_', '-'));
    }
  } finally { delete globalThis.chrome; }
  assert.equal(text('Save'), 'Save');
});

test('extension CAPTCHA locale is allowlisted without weakening callback or nonce validation', () => {
  const base = `https://app.example/auth/extension-challenge.html?returnTo=${encodeURIComponent(`https://${'a'.repeat(32)}.chromiumapp.org/captcha-callback`)}&lang=ja#state=${'s'.repeat(32)}`;
  assert.equal(parseChallenge(base).state, 's'.repeat(32));
  for (const raw of [base.replace('lang=ja', 'lang=unknown'), base.replace('lang=ja', 'lang=ja&lang=ko'), base.replace('lang=ja', 'lang=ja&extra=true'), base.replace('s'.repeat(32), 'short')]) assert.throws(() => parseChallenge(raw));
});
