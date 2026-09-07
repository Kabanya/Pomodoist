import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { appCopyKeys, copy } from './bot_ui.ts';

// Read the real source dictionaries, not fixtures derived from bot copy. These
// run in Telegram CI with --allow-read, including on Flutter ARB-only changes.
for (const language of ['en', 'ru']) {
  const arbUrl = new URL(`../../../../lib/l10n/app_${language}.arb`, import.meta.url);
  if (!existsSync(arbUrl)) continue;
  Deno.test(`Telegram ${language} terminology matches Flutter localization`, () => {
    const arb = JSON.parse(readFileSync(arbUrl, 'utf8'));
    const text = copy(language);
    for (const [key, source] of Object.entries(appCopyKeys)) {
      assert.equal(text[key as keyof typeof appCopyKeys], arb[source], `${language}: ${key} must match ${source}`);
    }
  });
}
