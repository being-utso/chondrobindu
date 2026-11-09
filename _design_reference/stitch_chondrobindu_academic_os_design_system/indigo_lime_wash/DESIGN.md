---
name: Indigo & Lime Wash
colors:
  surface: '#f8f9ff'
  surface-dim: '#cfdbf0'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff3ff'
  surface-container: '#e6eeff'
  surface-container-high: '#dde9fe'
  surface-container-highest: '#d8e3f9'
  on-surface: '#111c2b'
  on-surface-variant: '#43474e'
  inverse-surface: '#263141'
  inverse-on-surface: '#ebf1ff'
  outline: '#74777f'
  outline-variant: '#c4c6cf'
  surface-tint: '#456084'
  primary: '#163355'
  on-primary: '#ffffff'
  primary-container: '#2f4a6d'
  on-primary-container: '#9fbae3'
  inverse-primary: '#adc8f2'
  secondary: '#89502a'
  on-secondary: '#ffffff'
  secondary-container: '#feb385'
  on-secondary-container: '#79431e'
  tertiary: '#003b22'
  on-tertiary: '#ffffff'
  tertiary-container: '#0f5434'
  on-tertiary-container: '#86c79e'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d3e3ff'
  primary-fixed-dim: '#adc8f2'
  on-primary-fixed: '#001c39'
  on-primary-fixed-variant: '#2d486b'
  secondary-fixed: '#ffdbc8'
  secondary-fixed-dim: '#ffb68a'
  on-secondary-fixed: '#321300'
  on-secondary-fixed-variant: '#6d3915'
  tertiary-fixed: '#aff1c6'
  tertiary-fixed-dim: '#93d5ac'
  on-tertiary-fixed: '#002111'
  on-tertiary-fixed-variant: '#0a5132'
  background: '#f8f9ff'
  on-background: '#111c2b'
  surface-variant: '#d8e3f9'
typography:
  display-hero:
    fontFamily: Plus Jakarta Sans
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.03em
  display-hero-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.005em
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 26px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 22px
  body-sm:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  mono-timer-display:
    fontFamily: JetBrains Mono
    fontSize: 56px
    fontWeight: '500'
    lineHeight: 60px
    letterSpacing: -0.04em
  mono-timer-display-mobile:
    fontFamily: JetBrains Mono
    fontSize: 40px
    fontWeight: '500'
    lineHeight: 44px
    letterSpacing: -0.03em
  mono-code-md:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 18px
  mono-badge-sm:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.04em
  label-caps:
    fontFamily: Plus Jakarta Sans
    fontSize: 11px
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
  gutter: 1.5rem
  gutter-mobile: 0.75rem
  margin: 2.5rem
  margin-mobile: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system embodies the tactile rigor of classical scholarship met with the quiet discipline of modern studio architecture. Styled as "Indigo Dye & Lime Wash," the visual language treats digital screens as physical atelier surfaces: lime-washed mineral plasters, pressed handmade rag papers, and dark iron-gall or indigo pigments. It deliberately avoids sterile corporate SaaS tropes, neon-drenched gamification, and hyper-synthetic gradients.

The target audience comprises scholars, researchers, engineering students, and dedicated autodidacts who require sustained, deep cognitive presence. The interface induces quietude, weight, and timeless deliberate action. Surfaces interact via micro-thin hairline boundaries, disciplined typographic hierarchies, and organic earth minerals rather than floating neon planes.

## Colors

The palette draws strictly from natural earth dyes, weathered minerals, and hand-ground pigments.

### Light Mode (Default)
- **Canvas / Background**: `#EDEAE0` — Porous, matte lime-washed wall base.
- **Surface / Containers**: `#F7F5F0` — Warm chalk paper sheets layered over lime wash.
- **Surface Border**: `#DCD7C8` — 1px dry-edge boundary separating papers from plaster.
- **Primary Text**: `#1F2A3A` — Deep Indigo Ink with heavy pigment density.
- **Muted / Secondary Text**: `#5A6578` — Weathered Slate for academic metainformation.
- **Primary Brand Accent**: `#2F4A6D` — Natural Indigo Dye for active tab anchors, primary buttons, and focus focus-states.
- **Secondary Accent**: `#A5673F` — Warm Rust for deadline markers, active sessions, and attention callouts.

### Dark Mode
- **Canvas / Background**: `#171C24` — Deep Indigo Charcoal ground.
- **Surface / Containers**: `#202733` — Slate Indigo Surface.
- **Surface Border**: `#2E3846` — Subdued slate structural hairline.
- **Primary Text**: `#EDEAE0` — Lime wash off-white lettering.
- **Muted / Secondary Text**: `#94A3B8` — Cool Grey-Blue notation.
- **Primary Brand Accent**: `#8FA8C8` — Soft Washed Indigo glow for legibility against charcoal.
- **Secondary Accent**: `#C88256` — Luminous Rust for timers, focus dials, and urgent milestones.

### Academic & Schedule Status Semantics
- **Completed / Regular Lecture**: `#3B7A57` (Light) / `#4E9F72` (Dark) — Organic Moss Green.
- **Exam Window / Recess**: `#D98A3C` — Warm Ochre.
- **Quiz / Specific Evaluation Day**: `#A5673F` (Light) / `#C88256` (Dark) — Rust Highlight.
- **Holiday / Missed Slot**: `#B84A39` — Terracotta Crimson.

## Typography

The typographic hierarchy pairs clean, modern structural sans serifs with a technical monospaced engine.

- **Primary Interface & Editorial Headings**: `Plus Jakarta Sans` delivers architectural clarity with precise geometry and warm human terminations.
- **Reading & Continuous Body**: `Inter` handles dense course syllabi, analytical notes, and reference readings at maximum legibility.
- **Academic Metrics, Course Codes & Focus Clocks**: `JetBrains Mono` governs all course identifiers (e.g., `CSE-401`), room numbers, credit tallies, GPA metrics, and chronometer dials. Always format these numeric entities with CSS `font-variant-numeric: tabular-nums` to eliminate jitter during active timer ticks and numerical reflows.
- **All-Caps Eyebrows**: Render `label-caps` in uppercase with wide tracking for semester labels, section dividers, and metadata tags.

## Layout & Spacing

The layout is built upon an architectural grid with rhythmic horizontal bands reflecting classical bound notebooks.

### Screen Adaptations & Layout Models
- **Desktop (1440px+)**: A 12-column grid anchored by a structured top bar (h-14 / 56px) housing semester switchers, status indicators, and profile utilities. Content spans a maximum width of 1360px centered with `margin: 2.5rem` and `gutter: 1.5rem`. Split layouts feature a primary 8-column analytical/calendar pane paired with a 4-column active focus module.
- **Tablet (768px – 1024px)**: 8-column layout. The right workspace collapses into an overlay drawer or folds below main timetable matrices.
- **Mobile (390px Viewport)**: A single-column flow bounded by `margin-mobile: 1rem` and `gutter-mobile: 0.75rem`. Desktop top navigation transitions to a bottom dock (h-16 / 64px) elevated above the home indicator. Course grids collapse into tactile stacked cards.

### Rhythm Principles
Component padding conforms strictly to the 4px baseline. Interior course card paddings use `space-md` (16px) or `space-lg` (24px) for prominent hero widgets. Gaps between distinct thematic sections consume `space-xl` (40px) to give intellectual breathing room.

## Elevation & Depth

Visual order relies on **tonal paper layering and hairline structural boundaries**, deliberately rejecting heavy diffuse drop shadows and plastic skeuomorphism.

- **Stacking Surfaces**: Elevation is represented by laying lighter, purer paper sheets on top of textured lime wash. Light mode canvas `#EDEAE0` receives surface `#F7F5F0`. In dark mode, `#171C24` receives surface `#202733`.
- **Hairline Framing**: Every elevated panel, table cell, or segmented tab possesses a crisp `1px solid` border (`#DCD7C8` in light mode, `#2E3846` in dark mode).
- **Physical Contact Shadows**: When an active focus modal, course picker, or command bar floats over the workspace, apply an ultra-subtle contact occlusion shadow tinted with indigo pigment rather than neutral black:
  - *Light Mode Elevated*: `0 1px 3px rgba(31, 42, 58, 0.06), 0 8px 24px -4px rgba(31, 42, 58, 0.08)`
  - *Dark Mode Elevated*: `0 2px 6px rgba(0, 0, 0, 0.35), 0 12px 32px -4px rgba(10, 14, 20, 0.5)`
- **Recessed Inset**: Search bars, terminal viewports, and elapsed progress tracks use an inset tone (`#E4E0D5` Light / `#1B212B` Dark) with a subtle inset border, signaling an indented physical tray.

## Shapes

The interface adopts a restrained **Soft (`1`)** shape language that evokes hand-trimmed archival cards and architectural drafting templates.

- **Standard Base Corners**: Inputs, academic cards, calendar day cells, and action trays use `0.25rem` (4px).
- **Medium Panels (`rounded-lg`)**: Larger structural cards, course timetable blocks, and focus modal envelopes use `0.5rem` (8px).
- **Segmented Tabs & Control Chips**: Interactive category filters, segmented view switches, and status badges take `9999px` (full pill radius) to distinguish dynamic navigational toggles from static card sheets.

## Components

### Buttons
- **Primary Action (Indigo Fill)**: Solid `#2F4A6D` background (Light) or `#8FA8C8` (Dark) with contrasting text (`#EDEAE0` or `#171C24`). Height 40px, padding `0 16px`, corner radius `4px`. Hover state applies a 5% brightness increase; active state depresses by `1px`.
- **Secondary Action (Rust Accent)**: Solid `#A5673F` (Light) or `#C88256` (Dark) with ivory text. Used strictly for focus ignition, recording attendance, and exam submissions.
- **Outline / Editorial Action**: Transparent surface with a 1px border (`#DCD7C8` / `#2E3846`) and indigo ink text. Hover background shifts to `#E4E0D5` (Light) or `#283241` (Dark).

### Segmented Pills & Controls
- Container uses an indented channel background with a 1px border.
- The active item sits on an ivory paper pill (`#F7F5F0` Light / `#2E3846` Dark) with subtle border definition and bold typography. Inactive segments maintain Slate text (`#5A6578` / `#94A3B8`) without background.

### Academic Course Cards
- Framed in a 1px border over the `#F7F5F0` surface.
- Left edge features a 3px vertical accent stripe encoded with the course's semantic color.
- Upper region displays the course code in `JetBrains Mono` (`CSE-301`), right-aligned credit units (`3.0 CR`), and professor credentials.
- Lower block features class location, schedule time, and real-time attendance meter displayed via segmented ticks.

### Focus Timer Dial & Widget
- Large center display rendered in `JetBrains Mono` at `56px` (`40px` mobile).
- Surrounding ring is a non-skeuomorphic 4px circular SVG gauge: track in `#DCD7C8` (Light) / `#2E3846` (Dark), filled head in `#A5673F` (Warm Rust) or `#2F4A6D` (Indigo).
- Dial center features small uppercase session badges (e.g., `DEEP FOCUS // BLOCK 02`).

### Status Badges & Chips
- Fully rounded pills (`border-radius: 9999px`) with padding `2px 8px`.
- Composed of an 8% alpha tint background, matching solid colored text, and a leading 6px circular indicator dot:
  - *Completed Class*: Moss Green (`#3B7A57` / `#4E9F72`)
  - *Recess / Prep Window*: Warm Ochre (`#D98A3C`)
  - *Exam / Quiz*: Rust (`#A5673F` / `#C88256`)
  - *Missed / Warning*: Crimson (`#B84A39`)

### Checkboxes & Attendance Switches
- Checkboxes are 18x18px squares with a 2px radius and 1px border. Checked state fills with `#2F4A6D` displaying a crisp geometric tick icon in `#EDEAE0`.
- Segmented binary attendance states (Present / Late / Absent) display as a linked horizontal trio in `JetBrains Mono`.

### Input Fields
- Matte paper background with an inset 1px border.
- Floating helper labels rendered in `Plus Jakarta Sans` bold caps. Focus state changes border to `#2F4A6D` without introducing heavy glow rings.
- Tabular figures used in numeric academic calculation fields (CGPA calculators, grade projections).

### Navigation Shells
- **Desktop (1440px)**: Top bar pinned at 56px with a bottom hairline divider (`1px solid #DCD7C8`). Left holds university branding, center holds the active semester switcher pill, and right contains the global focus status chip and user profile.
- **Mobile (390px)**: Persistent bottom floating dock positioned 16px above the home bar. Features frosted translucent backing (`backdrop-filter: blur(12px)` over `#F7F5F0EE` Light / `#202733EE` Dark) bordered by `#DCD7C8`, holding 4 primary destinations (Timetable, Focus, Grades, Syllabus) with micro monospaced labels.