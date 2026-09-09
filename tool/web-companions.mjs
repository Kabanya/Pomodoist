import { readFile, mkdir, copyFile, writeFile, rm } from 'node:fs/promises';
import { parseEnv, parseArgs, promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { build, configuration } from '../chrome-extension/build.mjs';

export const root = fileURLToPath(new URL('../', import.meta.url));
export const miniAppFiles = ['index.html', 'app.js', 'core.js', 'styles.css'];
const execute = promisify(execFile);
export const loadEnv = async file => parseEnv(await readFile(file, 'utf8'));

export function runtimeConfig(env) {
  const config = configuration({ ...env, WEB_APP_URL: env.POMODOIST_WEB_URL || env.WEB_APP_URL });
  return { environment: env.POMODOIST_ENVIRONMENT,
    webAppUrl: config.webUrl, supabaseUrl: config.apiUrl, supabaseAnonKey: config.anonKey };
}
export function configScript(config) {
  return `window.pomodoistRuntimeConfig = ${JSON.stringify(config).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029')};\n`;
}
export async function buildMiniApp(env, destination) {
  const config = runtimeConfig(env);
  destination = path.resolve(destination);
  if (destination === path.parse(destination).root || destination === root.slice(0, -1) || root.startsWith(destination + path.sep) ||
      destination === path.join(root, 'telegram-mini-app')) throw new Error('Build output must not contain the source.');
  await rm(destination, { recursive: true, force: true });
  await mkdir(path.join(destination, 'telegram'), { recursive: true });
  for (const file of miniAppFiles) await copyFile(path.join(root, 'telegram-mini-app', file), path.join(destination, 'telegram', file));
  await writeFile(path.join(destination, 'config.js'), configScript(config));
  return destination;
}
export async function openUrl(url, chrome = false) {
  try {
    if (process.platform === 'darwin') await execute('open', chrome ? ['-a', 'Google Chrome', url] : [url]);
    else if (process.platform === 'win32') await execute('rundll32.exe', ['url.dll,FileProtocolHandler', url]);
    else await execute(chrome ? 'google-chrome' : 'xdg-open', [url]);
  } catch { console.log(`Open manually: ${url}`); }
}

async function main() {
  const { values, positionals: [platform, mode] } = parseArgs({ allowPositionals: true,
    options: { config: { type: 'string' }, 'no-open': { type: 'boolean' } } });
  if (!['chrome', 'telegram'].includes(platform) || !['debug', 'release'].includes(mode) || platform === 'telegram' && mode === 'debug') {
    throw new Error('Use make chrome-debug, chrome-release, telegram-debug or telegram-release.');
  }
  const configFile = values.config || path.join(root, mode === 'debug' ? '.env.staging' : '.env.testflight');
  const env = await loadEnv(configFile);
  if (env.POMODOIST_ENVIRONMENT !== (mode === 'debug' ? 'staging' : 'production')) throw new Error(`Wrong environment in ${configFile}.`);
  const destination = path.join(root, 'build', platform, mode);
  await (platform === 'chrome' ? build(env, destination) : buildMiniApp(env, destination));
  console.log(`Built ${platform} (${env.POMODOIST_ENVIRONMENT}): ${destination}`);
  if (mode === 'release') {
    const archive = path.join(root, 'build', platform, `pomodoist-${platform}-release.zip`);
    await rm(archive, { force: true });
    await execute('zip', ['-qr', archive, '.'], { cwd: destination });
    console.log(`Archive: ${archive}`);
  } else {
    console.log('Chrome: Developer mode → Load unpacked (first run); Reload after rebuilding.');
    if (!values['no-open']) await openUrl('chrome://extensions', true);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
