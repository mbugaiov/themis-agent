# 60 — Design SoT pixel gate (screens + controls)

**Applies to every repo that runs `review (Themis)`** when the product already
has a visual pixel gate (`PIXEL_SURFACES` / `PIXEL_ELEMENTS`, `test:preview-pixel`,
or equivalent) **or** the factory project configures `design_preview` / Figma.

Portable rule: do **not** name product slugs. If the diff is engine-only with no
app UI, this lens does not apply.

## Bar

When a prototype or Figma URL is the visual source of truth, shipped UI must
match it at **mismatch ≤ 2% (≥ 98% similarity)** on:

- every gated **screen** (`PIXEL_SURFACES` or documented scored band)
- every chrome **control** (`PIXEL_ELEMENTS`: dropdown, text, icon, button,
  input, chip, nav, tab, card, and other visible kinds)

## Block on (put under `## Blocking issues`)

1. **UI added or restyled** (routes, components, CSS) **without** a new/updated
   required pixel catalog row for that surface or control.
2. **`required: false` / `skipReason`** on a PIXEL_* row (or equivalent skip of
   the 98% bar) introduced or kept to make CI green.
3. **Pixel tests deleted or threshold loosened** (e.g. `MAX_MISMATCH` raised)
   without an OpenSpec/product contract that replaces the 98% bar.
4. **Docs/skills claim 98%** while code still skips screens or controls.

## What does not block

- Non-UI diffs (API, factory scripts, docs-only typos).
- Seed/demo **data** masked out of scored bands when chrome is still gated.
- A first PR that **introduces** the pixel gate (must still ship tests + catalogs).

## Reviewer instructions

- If `scripts/pixel_surfaces.mjs` / `pixel_elements.mjs` (or the product’s named
  equivalent) exists, UI files in the diff must have matching catalog/test
  updates.
- Name the missing surface or control id in the Blocking bullet.
