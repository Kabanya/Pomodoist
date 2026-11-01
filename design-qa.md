# Quick Add priority menu verification

Date: 2026-11-02.

## Visual target and evidence

- Source: `/var/folders/vz/_fjds83j6z1c01cz81zyb7nr0000gn/T/codex-clipboard-2801de8f-98b5-4aca-ac26-a5d91e0258f7.png` (1254 × 1254).
- The user's later instruction removes Use default, leaving exactly four flag choices.
- Implementation: `output/imagegen/priority-2026-11-02/implementation-component.png`.
- Focused implementation: `output/imagegen/priority-2026-11-02/implementation-menu.png`.
- Side-by-side comparison: `output/imagegen/priority-2026-11-02/comparison.png`.
- State: English, dark theme, open menu, P3 selected. Capture uses the actual Flutter widget at 2× pixel density. The source menu is normalized to the implementation's 608 px width; the comparison excludes the superseded default footer.

## Findings and comparison history

- Initial rendered capture revealed that the ghost-button theme inherited a zero-width selected border. Set its width explicitly to 1 px; the final comparison shows the selected outline and checkmark.
- Typography: bundled Geist labels and GeistMono badges preserve the hierarchy. Retain the application's existing control text sizes rather than enlarging the toolbar to the concept image scale.
- Spacing: four aligned rows with 40 px flag tiles and a minimum 64 px row height. Scaled text can grow rows inside the scrollable popover. Existing toolbar density and compact P3 labels remain unchanged.
- Colors: use existing priority palette roles and shared contrast adjustment. The selected badge uses the stronger semantic tint so it remains distinct from the row fill.
- Assets: use the installed Lucide flag for all four levels, preserving the application's icon vocabulary rather than introducing custom filled or striped glyphs.
- Content: all four priority labels and localized subtitles are present; Use default and its separator are absent, as requested.
- No remaining actionable P0/P1/P2 differences in the compared component. The consistent outline flag and existing type scale are intentional adaptations to the repository design system.

## Validation

- 41 Quick Add, window, toolbar and architecture tests passed before the final footer removal.
- All three priority widget tests passed after removal, including preservation of other metadata and Russian text at 200% in light/dark themes.
- Targeted analysis and diff whitespace checks passed.
- macOS development build launched; hot reload succeeded and runtime error retrieval returned no errors.
- Visual comparison uses a Flutter test rendering with loaded bundled fonts; the native macOS menu was also inspected before the footer removal. No full test suite or other-platform device verification was performed.

final result: passed
