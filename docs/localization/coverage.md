# Portuguese (Brazil), Japanese and Korean localization

Source: user-approved implementation plan, 2026-09-13. Translation and editorial
model: GPT-6 Astra, high reasoning. No runtime model changes.

Manual testing and Computer Use are excluded by explicit user instruction.
Visual acceptance and native-speaker review are not claimed. No deployments,
commits, messages, store submissions or live bot configuration are authorized.

| Surface | pt-BR | ja | ko | Automated evidence |
| --- | --- | --- | --- | --- |
| Flutter catalog and language selection | Implemented | Implemented | Implemented | `gen-l10n`, `analyze`, 1,458 Flutter tests |
| Quick Add parsing and source highlights | Implemented | Implemented | Implemented | 18 parser/locale tests passed |
| Achievements and updater | Implemented | Implemented | Implemented | Flutter suite |
| Notifications and system channels | Implemented | Implemented | Implemented | Flutter suite |
| Apple Watch, widgets, native menus and permissions | Implemented | Implemented | Implemented | macOS/iOS/Watch builds; two Swift checks |
| Speech locale routing | Implemented | Implemented | Implemented | Swift and Flutter tests |
| Telegram Mini App and bot | Implemented | Implemented | Implemented | Deno tests; bot configuration remains unapplied |
| Chrome extension | Implemented | Implemented | Implemented | 45 Node tests and production build |
| Web loader, CAPTCHA and auth links | Implemented | Implemented | Implemented | Flutter suite |
| Auth emails | Implemented | Implemented | Implemented | 14 Deno tests; Go template test |
| Payment locale propagation | Implemented | Implemented | Implemented | Stripe function tests |
| Landing and all published content | Implemented | Implemented | Implemented | 89 tests and Vite production build |
| Published documentation | Implemented | Implemented | Implemented | Next type check and static build (159 pages) |
| Store metadata and marketing assets | Prepared | Prepared | Prepared | 3 store packages; 18 automated demo captures |
| Windows/Linux packaging | Prepared | Prepared | Prepared | Installer and desktop resources changed; Windows/Linux runner required |

## Invariants

- Preserve user content, IDs, storage values and current unrelated changes.
- Canonical locale tags: pt-BR, ja, ko; website prefixes: pt-br, ja, ko.
- Portuguese fallback uses Brazilian copy. No separate European translation.
- Preserve placeholders, dates, prices, URLs, claims and command syntax.
- Existing English documentation URLs remain valid.
- Developer instructions and internal documentation stay in English.
- The matrix records automated evidence only. It does not represent manual visual
  acceptance, native-speaker review, production deployment, or store publication.
