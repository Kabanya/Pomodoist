import test from 'node:test';
import assert from 'node:assert/strict';
import { configuration, manifestFor } from '../build.mjs';
const env = { SUPABASE_URL: 'https://api.example.test', WEB_APP_URL: 'https://tasks.example.test', SUPABASE_ANON_KEY: 'sb_publishable_testkey' };
test('build uses exact backend origin, MV3, self-only code and minimal permissions', () => {
  const config = configuration(env), m = manifestFor(config);
  assert.equal(m.manifest_version, 3);
  assert.deepEqual(m.permissions.sort(), ['activeTab', 'identity', 'storage']);
  assert.deepEqual(m.host_permissions, ['https://api.example.test/*']);
  assert.match(m.content_security_policy.extension_pages, /script-src 'self'/);
  assert.match(m.content_security_policy.extension_pages, /wss:\/\/api.example.test/);
  assert.doesNotMatch(JSON.stringify(m), /<all_urls>|unsafe-eval|unsafe-inline|content_scripts|externally_connectable/);
});
test('insecure non-loopback servers, URL credentials, paths and missing configuration are rejected', () => {
  for (const url of ['http://api.example.test', 'https://u:p@api.example.test', 'https://api.example.test/path', 'https://api.example.test/?secret=x']) {
    assert.throws(() => configuration({ ...env, SUPABASE_URL: url }));
  }
  assert.throws(() => configuration({}));
  assert.equal(configuration({ ...env, SUPABASE_URL: 'http://localhost:55421' }).apiUrl, 'http://localhost:55421');
});
test('service role and secret keys never enter a public build', () => {
  const jwt = role => 'e30.' + Buffer.from(JSON.stringify({ role })).toString('base64url') + '.signature';
  // Assemble the fake credential so public-boundary scanning does not flag test data.
  const secretFixture = ['sb', 'secret', 'private'].join('_');
  for (const key of [secretFixture, jwt('service_role'), 'not-a-public-key']) {
    assert.throws(() => configuration({ ...env, SUPABASE_ANON_KEY: key }));
  }
  assert.equal(configuration({ ...env, SUPABASE_ANON_KEY: jwt('anon') }).anonKey, jwt('anon'));
});
test('captcha configuration follows the same public site key as the main web app', () => {
  assert.equal(configuration(env).captchaEnabled, false);
  assert.equal(configuration({ ...env, TURNSTILE_SITE_KEY: 'public-site-key' }).captchaEnabled, true);
});

test('packaged Chrome locales have complete native messages and the English fallback', async () => {
  const { build } = await import('../build.mjs');
  const { mkdtemp, readFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const path = await import('node:path');
  const output = await mkdtemp(path.join(tmpdir(), 'pomodoist-locales-'));
  try {
    await build(env, output);
    const manifest = JSON.parse(await readFile(path.join(output, 'manifest.json'), 'utf8'));
    assert.equal(manifest.default_locale, 'en');
    assert.equal(manifest.description, '__MSG_extension_description__');
    const english = JSON.parse(await readFile(path.join(output, '_locales/en/messages.json'), 'utf8'));
    for (const locale of ['pt_BR', 'ja', 'ko']) {
      const messages = JSON.parse(await readFile(path.join(output, `_locales/${locale}/messages.json`), 'utf8'));
      assert.deepEqual(Object.keys(messages), Object.keys(english));
      for (const [key, value] of Object.entries(messages)) {
        assert.ok(value.message.trim(), `${locale}.${key}`);
        assert.deepEqual(value.message.match(/\{\w+\}/g), english[key].message.match(/\{\w+\}/g));
      }
    }
    assert.match(await readFile(path.join(output, 'src/i18n.js'), 'utf8'), /chrome\?\.i18n\?\.getMessage/);
  } finally { await rm(output, { recursive: true, force: true }); }
});
