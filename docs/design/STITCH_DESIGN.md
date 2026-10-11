---
name: Atelier Sonoro
colors:
  surface: '#151312'
  surface-dim: '#151312'
  surface-bright: '#3c3937'
  surface-container-lowest: '#100e0d'
  surface-container-low: '#1d1b1a'
  surface-container: '#211f1e'
  surface-container-high: '#2c2928'
  surface-container-highest: '#373433'
  on-surface: '#e8e1df'
  on-surface-variant: '#dfc0b3'
  inverse-surface: '#e8e1df'
  inverse-on-surface: '#33302f'
  outline: '#a78b7f'
  outline-variant: '#584239'
  surface-tint: '#ffb596'
  primary: '#ffb596'
  on-primary: '#581e00'
  primary-container: '#ea6b29'
  on-primary-container: '#4d1900'
  inverse-primary: '#a33e00'
  secondary: '#d0c5b8'
  on-secondary: '#362f27'
  secondary-container: '#4d463c'
  on-secondary-container: '#beb4a7'
  tertiary: '#d0c4bd'
  on-tertiary: '#362f2a'
  tertiary-container: '#998f88'
  on-tertiary-container: '#2f2824'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffdbcd'
  primary-fixed-dim: '#ffb596'
  on-primary-fixed: '#360f00'
  on-primary-fixed-variant: '#7c2e00'
  secondary-fixed: '#ece1d3'
  secondary-fixed-dim: '#d0c5b8'
  on-secondary-fixed: '#201b13'
  on-secondary-fixed-variant: '#4d463c'
  tertiary-fixed: '#ede0d9'
  tertiary-fixed-dim: '#d0c4bd'
  on-tertiary-fixed: '#201a16'
  on-tertiary-fixed-variant: '#4d4540'
  background: '#151312'
  on-background: '#e8e1df'
  surface-variant: '#373433'
typography:
  display-lg:
    fontFamily: Newsreader
    fontSize: 56px
    fontWeight: '400'
    lineHeight: 64px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Newsreader
    fontSize: 38px
    fontWeight: '400'
    lineHeight: 44px
    letterSpacing: -0.015em
  headline-lg:
    fontFamily: Newsreader
    fontSize: 36px
    fontWeight: '400'
    lineHeight: 44px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Newsreader
    fontSize: 28px
    fontWeight: '400'
    lineHeight: 34px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Newsreader
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 32px
    letterSpacing: 0em
  title-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: 0.01em
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0.01em
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.04em
  label-xs:
    fontFamily: Plus Jakarta Sans
    fontSize: 10px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.08em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-desktop: 2.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system treats the digital music player not as an ephemeral streaming utility, but as a high-fidelity physical instrument and editorial catalog. Inspired by Braun industrial audio equipment, mid-century vinyl liner notes, and boutique analog synthesizers, the aesthetic balances physical tactility with disciplined typography.

The target audience comprises audiophiles, crate-diggers, and design-conscious listeners on both desktop and mobile surfaces. The interface rejects generic neon blur spheres, translucent frost overlays, and synthetic purple-cyan gradients. Instead, it relies on a warm soot-and-bone chromatic anchor, tangible micro-reliefs, asymmetrical framing, and mechanical controls (stepped detents, knurled toggles, solid tactile travel). Every interaction communicates weight, permanence, and mechanical intent.

## Colors

The palette establishes an intimate, low-light listening environment rooted in charcoal, ink-brown, and warm paper tints:

- **Canvas & Base Tones:** The master base is `#110f0e` (Charcoal Obsidian). Elevating structural tiers are `#161413` (Deep Soot), `#1e1b19` (Burnt Carbon), `#282320` (Ink Wash), and `#38312c` (Ash Sepia) for structural dividers and inactive rails.
- **Master Accent:** `#e86927` (Burnt Vintage Tangerine) serves as the persistent default focus and active transport state. When extraction algorithms resolve dominant album art tones, this slot dynamically adopts the extracted pigment while keeping base surfaces and text contrast strictly anchored.
- **Editorial Typography:** Master primary typography uses `#f5efe6` (Warm Bone), secondary track and artist metadata uses `#d9cec1` (Unbleached Vellum), and micro-labels/timestamps rely on `#9e9185` (Weathered Parchment).
- **Mechanical Borders:** Borders never use pure white or generic transparent opacity; they use hard `#38312c` and `#282320` offsets to evoke chassis seams and machined panel cutouts.

## Typography

The type system stages an intentional tension between editorial classicism and functional clarity:

- **Display & Headlines (`Newsreader`):** Utilized for album titles, featured retrospective headers, artist monikers, and long-form liner notes. Rendered with natural optical sizing, delicate serifs, and high-contrast stroke terminals. It conveys authoritative cultural curation.
- **Interface & Metadata (`Plus Jakarta Sans`):** Clean, proportioned grotesque architecture used for tracklists, hardware toggles, timestamps, bitrates (e.g., `FLAC 24-bit / 96kHz`), and navigation nodes. Maintains legible structure at small scale against high-density list views.
- **Labels & Micro-indicators:** Applied uppercase with wide tracking (`0.04em` to `0.08em`) to mimic stamped faceplates, chassis serial indicators, and audio mastering stamps.

## Layout & Spacing

The structural layout adapts between multi-pane desktop workstations (Windows) and vertical touch navigation (Android):

- **Desktop Form Factor (Windows):** Built around a rigid, asymmetric three-column chassis layout. 
  - Left pane (Fixed 260px): Library index and record bins.
  - Center pane (Flexible 12-column grid, 24px gutters): Editorial view, track matrices, liner commentary.
  - Right pane (Fixed 340px): Dedicated tactile playback module, VU readout, and dynamic queue.
- **Mobile Form Factor (Android):** Single-column stacked system with an 8-column internal grid, 16px margins, and a persistent bottom dock with mechanical micro-offsets.
- **Spacing Rhythm:** Spacing scales on a rigorous 4px / 8px baseline rhythm. Dense data sections (track duration, frequency meters) use `space-xs` and `space-sm` for an instrumentation console feel, while editorial artwork and artist profile features use `space-lg` and `space-xl` to mimic magazine double-page spreads.

## Elevation & Depth

Depth is established through physical relief and structural chassis planes, deliberately avoiding soft, diffuse alpha shadows:

1. **Surface Carving & Recessed Decks:** Interactive control wells, seek bars, and search fields sit inside recessed surface decks (`#161413`) with a crisp 1px hard top border (`#110f0e`) and a subtle bottom lip (`#282320`), giving the illusion of stamped metal or milled phenolic resin.
2. **Hard Drop Shadows (Zero-Blur Tactility):** Elevated cards, context flyouts, and floating player controls do not diffuse into murky black hazes. They cast strict zero-blur offsets:
   - Level 1 (Buttons, Track Items): `1px 2px 0px #0a0908`
   - Level 2 (Album Art, Cassette Cards): `3px 4px 0px #000000`
   - Level 3 (Context Menus, Modal Overlays): `6px 8px 0px #000000`
3. **Chassis Seams & Mechanical Bevels:** All card containers, album envelopes, and sidebars feature a solid 1px continuous hairline outline using `#282320` or `#38312c`.
4. **Analog Micro-Texture:** Overlaid with an ultra-fine, deterministic SVG monochromatic grain texture at 2.5% opacity across the base tier, eliminating digital flatness without distracting from cover graphics.

## Shapes

The shape vocabulary rejects both sterile sharp rectangles and modern oversized pill shapes in favor of mechanical contours and tactile asymmetry:

- **Asymmetric Radii (Sleeve Cutouts):** Album art frames, queue preview thumbnails, and collection cards feature deliberate asymmetrical corner radii: `top-left: 8px; top-right: 2px; bottom-right: 8px; bottom-left: 2px`. This recalls vinyl sleeve packaging, heavy cardstock die-cuts, and precision-stamped physical cartridges.
- **Chassis Panels:** Main structural module containers and docked playback consoles maintain a disciplined `4px` radius (`roundedness: 1`), reinforcing precision fabrication.
- **Physical Pushcaps:** Action toggles and segmented filters use uniform `4px` corners with a 1px extruded bottom edge to sustain tactile push-button geometry.

## Components

### Buttons & Transport Triggers
- **Master Play/Pause:** Solid `#e86927` surface with a crisp 1px border (`#d9531e`). Casts a hard `2px 3px 0px #000000` shadow. On `:active`, the shadow reduces to `0px 0px 0px` and the button translates `2px` downwards and `1px` rightwards, providing tangible mechanical depression.
- **Secondary Actions (Skip, Loop, Shuffle):** Stepped buttons in `#1e1b19` with `#38312c` border and `#d9cec1` iconography. Inactive states rest at level 1; toggled active states switch to an illuminated `#e86927` fill with bone-white icons.

### Scrubbers, Faders & Dials
- **Seek Rails (Scrubber):** A milled 6px grooved track (`#161413`) flanked by a 1px border (`#282320`). The played region fills with an unbroken `#e86927` strip. The scrub handle is a solid rectangular needle (4px wide, 14px high) in `#f5efe6` with knurled vertical line notches, rather than a generic floating circle.
- **Volume & EQ Dials:** Circular rotary potentiometers styled with machined radial ticks in `#38312c` and an indicator marker that tracks angle changes with zero-latency visual feedback.

### Tracklists & Data Rows
- **List Structure:** Explicit table-style rows separated by a 1px hairline (`#1e1b19`).
- **Typography Layout:** Track number rendered in monospace or tabular `Plus Jakarta Sans` (`#9e9185`), track title in `Newsreader` (`#f5efe6`), and artist/album metadata in `Plus Jakarta Sans` (`#d9cec1`).
- **Interactive State:** Hover or highlight on desktop applies a flush background tint of `#1e1b19` paired with an `#e86927` 2px vertical indicator bar flush against the left boundary edge.

### Album Art Sleeves & Cards
- **Art Framing:** Artwork is framed with the signature asymmetric radius (`8px 2px 8px 2px`), encased by a 1px border in `#38312c` and an offset hard drop shadow (`3px 4px 0px #000000`).
- **Metadata Tagging:** Badges for audio formats (`DSD`, `24-BIT / 192KHZ`, `MONO`) appear as stamped debossed rectangular plates (`#161413`) with `#9e9185` uppercase micro-type.

### Inputs & Search
- Form fields are styled as recessed dark faceplates (`#161413`) with `#282320` inset contours. Caret is a solid `#e86927` block; placeholder text displays in `#9e9185` with italicized `Newsreader` stylings, transitioning into clean `Plus Jakarta Sans` upon user keystrokes.