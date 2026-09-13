# Store localization release material

All files are drafts for the next localization release. No store has been updated.

- Apple source: public [US listing](https://apps.apple.com/us/app/pomodoist/id6794391064), retrieved through Apple's lookup API on 2026-09-13, version 1.0.5. `source-apple-en.json` preserves the source. iOS and Mac share the applicable product description.
- Google Play: adapted from the same verified product functionality and local Android implementation; no public Google Play listing was available as a source. Platform-specific Apple billing text is omitted. Do not treat this as a copy of a current Play listing.
- Chrome: `chrome-extension/README.md`, popup and native i18n manifest are the source; no unimplemented project moves, Focus, voice or billing are advertised.
- New release notes describe this pending localization release; they are not translations of the public 1.0.5 notes.
- Purchase IDs come from the existing billing catalog. Translations change labels only, not prices, currency, entitlement or billing period. Publication is separate.
- `imageCaptions` is localized artwork copy for existing Today, Quick Add, Focus, Reports and companion surfaces. Actual captures and platform acceptance are recorded in the coverage matrix; text preparation does not imply image approval.

## Field limits

Checked against the primary documentation on 2026-09-13:

- [Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information): name and subtitle, 30 characters.
- [Apple product page](https://developer.apple.com/app-store/product-page/): promotional text, 170; description, 4,000; keywords, 100. The checker additionally limits UTF-8 keyword bytes to 100.
- [Google Play listing](https://support.google.com/googleplay/android-developer/answer/9859152): name, 30; short description, 80; full description, 4,000.
- [Chrome description](https://developer.chrome.com/docs/apps/manifest/description): manifest description, 132 characters.
- Purchase display names are kept within 30 characters and descriptions within 45, matching [Apple purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information).

Run `python3 tool/check_localization.py` to validate these files together with app and Apple catalogs. Native-speaker review has not been performed. Automated checks do not replace linguistic or visual acceptance.
