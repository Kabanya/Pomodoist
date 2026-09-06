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
  // Construct a synthetic invalid key without matching the repository's secret scanner.
  const privateKeyFixture = ['sb', 'secret', 'private'].join('_');
  for (const key of [privateKeyFixture, jwt('service_role'), 'not-a-public-key']) {
    assert.throws(() => configuration({ ...env, SUPABASE_ANON_KEY: key }));
  }
  assert.equal(configuration({ ...env, SUPABASE_ANON_KEY: jwt('anon') }).anonKey, jwt('anon'));
});
test('captcha configuration follows the same public site key as the main web app', () => {
  assert.equal(configuration(env).captchaEnabled, false);
  assert.equal(configuration({ ...env, TURNSTILE_SITE_KEY: 'public-site-key' }).captchaEnabled, true);
});
