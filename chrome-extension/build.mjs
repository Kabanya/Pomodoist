import { mkdir, readFile, copyFile, writeFile, rm } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
const root = path.dirname(fileURLToPath(import.meta.url));
function origin(value, name) {
  let url;
  try { url = new URL(value); } catch { throw new Error(`${name} must be configured with a valid origin.`); }
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if ((url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) || url.username || url.password ||
      url.search || url.hash || url.pathname !== '/') throw new Error(`${name} must be an HTTPS origin (HTTP is only allowed on loopback).`);
  return url.origin;
}
export function configuration(env) {
  const apiUrl = origin(env.SUPABASE_URL, 'SUPABASE_URL'), webUrl = origin(env.WEB_APP_URL, 'WEB_APP_URL');
  const anonKey = env.SUPABASE_ANON_KEY?.trim() ?? '';
  let publicKey = /^sb_publishable_[A-Za-z0-9_-]+$/.test(anonKey);
  if (!publicKey) {
    try { publicKey = anonKey.split('.').length === 3 && JSON.parse(Buffer.from(anonKey.split('.')[1], 'base64url')).role === 'anon'; }
    catch { publicKey = false; }
  }
  if (!publicKey) throw new Error('SUPABASE_ANON_KEY must be a public anon/publishable key, never a service-role or secret key.');
  return { apiUrl, webUrl, anonKey, captchaEnabled: !!env.TURNSTILE_SITE_KEY?.trim() };
}
export function manifestFor(config) {
  const socket = new URL(config.apiUrl); socket.protocol = socket.protocol === 'https:' ? 'wss:' : 'ws:';
  return { manifest_version: 3, name: 'Pomodoist', version: '0.1.0', minimum_chrome_version: '116',
    description: 'Quick access to your Pomodoist tasks: Today, Upcoming, scheduling and browser tab capture.',
    action: { default_popup: 'popup.html', default_title: 'Pomodoist', default_icon: 'icon.png' },
    icons: { 16: 'icon.png', 32: 'icon.png', 48: 'icon.png', 128: 'icon.png' },
    background: { service_worker: 'src/background.js', type: 'module' },
    permissions: ['storage', 'identity', 'activeTab'], host_permissions: [`${config.apiUrl}/*`],
    content_security_policy: { extension_pages: `default-src 'self'; script-src 'self'; object-src 'none'; style-src 'self'; img-src 'self'; connect-src ${config.apiUrl} ${socket.origin}; base-uri 'none'; form-action 'none'` },
  };
}
export async function build(env = process.env, destination = path.join(root, 'dist')) {
  const config = configuration(env);
  destination = path.resolve(destination);
  if (destination === path.parse(destination).root || destination === root || root.startsWith(destination + path.sep)) throw new Error('Build output must not contain the extension source.');
  await rm(destination, { recursive: true, force: true });
  await mkdir(path.join(destination, 'src'), { recursive: true });
  for (const file of ['background.js', 'client.js', 'core.js', 'popup.js', 'realtime.js', 'sync.js']) {
    await copyFile(path.join(root, 'src', file), path.join(destination, 'src', file));
  }
  for (const file of ['popup.html', 'styles.css']) await copyFile(path.join(root, file), path.join(destination, file));
  // Reuse the application's existing branded PNG; Chrome scales it for toolbar sizes.
  await copyFile(path.join(root, '../web/icons/Icon-192.png'), path.join(destination, 'icon.png'));
  await copyFile(path.join(root, '../LICENSE'), path.join(destination, 'LICENSE'));
  await writeFile(path.join(destination, 'manifest.json'), JSON.stringify(manifestFor(config), null, 2) + '\n');
  await writeFile(path.join(destination, 'src/config.js'), `export const config = Object.freeze(${JSON.stringify(config, null, 2)});\n`);
  await writeFile(path.join(destination, 'SOURCE.txt'), 'Pomodoist Chrome extension — AGPL-3.0-only\nSource and build instructions: https://github.com/Kabanya/Pomodoist/tree/' +
    (env.GITHUB_SHA && /^[a-f0-9]{40}$/.test(env.GITHUB_SHA) ? env.GITHUB_SHA : 'main') + '/chrome-extension\n');
  // Parse the emitted manifest, rather than reporting success after a partial write.
  JSON.parse(await readFile(path.join(destination, 'manifest.json'), 'utf8'));
  return destination;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { console.log(`Built extension: ${await build()}`); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
