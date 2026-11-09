---
name: Chondrobindu Nocturne
colors:
  surface: '#0f141b'
  surface-dim: '#0f141b'
  surface-bright: '#343942'
  surface-container-lowest: '#090e16'
  surface-container-low: '#171c24'
  surface-container: '#1b2028'
  surface-container-high: '#252a33'
  surface-container-highest: '#30353e'
  on-surface: '#dee2ee'
  on-surface-variant: '#c3c6ce'
  inverse-surface: '#dee2ee'
  inverse-on-surface: '#2c3139'
  outline: '#8d9198'
  outline-variant: '#43474d'
  surface-tint: '#afc9ea'
  primary: '#afc9ea'
  on-primary: '#18324c'
  primary-container: '#8fa8c8'
  on-primary-container: '#243d58'
  inverse-primary: '#48607d'
  secondary: '#ffb68a'
  on-secondary: '#522300'
  secondary-container: '#713b15'
  on-secondary-container: '#f3a778'
  tertiary: '#85d8a6'
  on-tertiary: '#003920'
  tertiary-container: '#65b687'
  on-tertiary-container: '#004528'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#d1e4ff'
  primary-fixed-dim: '#afc9ea'
  on-primary-fixed: '#001d36'
  on-primary-fixed-variant: '#304864'
  secondary-fixed: '#ffdbc8'
  secondary-fixed-dim: '#ffb68a'
  on-secondary-fixed: '#321300'
  on-secondary-fixed-variant: '#6e3913'
  tertiary-fixed: '#a1f4c1'
  tertiary-fixed-dim: '#85d8a6'
  on-tertiary-fixed: '#002111'
  on-tertiary-fixed-variant: '#005231'
  background: '#0f141b'
  on-background: '#dee2ee'
  surface-variant: '#30353e'
typography:
  display-timer:
    fontFamily: JetBrains Mono
    fontSize: 56px
    fontWeight: '600'
    lineHeight: 64px
    letterSpacing: -0.04em
  display-timer-mobile:
    fontFamily: JetBrains Mono
    fontSize: 40px
    fontWeight: '600'
    lineHeight: 48px
    letterSpacing: -0.03em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.025em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.02em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.015em
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  code-md:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: -0.01em
  code-sm:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0em
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.08em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system establishes a focused, nocturnal operating system crafted for collegiate academia and deliberate, sustained study. It rejects abrasive neon gamification and high-stress notification patterns in favor of calm, physical clarity. The aesthetic merges contemporary Scandinavian desktop utility with computational rigor: deep indigo slate bedrock, luminous rust focal drivers, crisp structural borders, and monospace data density.

The interface serves university scholars, researchers, and technical undergraduates balancing high-cognitive workloads. The environment must evoke the stillness of an empty campus library at 02:00 AM—delivering total distraction reduction, quiet spatial composure, and immediate tactical orientation toward upcoming academic milestones.

### Stylistic Directives
- **Structural Blueprinting:** All visual division relies on crisp 1px borders and surface-depth tiering rather than muddy ambient drop shadows.
- **Academic Precision:** Course identifiers, lecture timestamps, CGPA calculations, and focus countdowns are treated with mathematical dignity using monospace typography and tabular figure alignment.
- **Intentional Luster:** Warm accents (Luminous Rust and Amber) are reserved exclusively for focus-state progression, impending evaluation deadlines, and active study session states.

## Colors

The palette employs a nocturnal "Indigo Slate & Luminous Rust" scheme optimized for low-fatigue nighttime screen reading and high-contrast information hierarchy.

### Canvas & Surface Hierarchy
- **Canvas Base (`#171C24`):** Deep indigo charcoal foundational canvas.
- **Raised Surface (`#202733`):** Slate indigo surface applied to cards, popovers, headers, and modal dialogues.
- **Recessed / Inset Container (`#13171E`):** Deep pressed slate for input wells, data track backgrounds, code blocks, and inactive progress paths.
- **Structural Border (`#2E3846`):** Standard 1px structural stroke framing every card, divider, and interactive perimeter.
- **Subtle Surface Overlay (`rgba(32, 39, 51, 0.90)`):** Backing for mobile floating navigation docks and desktop glass overlays with 16px backdrop blur.

### Text & Glyph Tokens
- **Text Primary (`#EDEAE0`):** Lime wash off-white for headers, dominant numerical metrics, and high-emphasis body copy.
- **Text Secondary / Muted (`#94A3B8`):** Cool grey-blue slate for supporting metadata, field descriptions, inactive tab labels, and axis markers.
- **Text Inverted (`#13171E`):** Deep slate fill used when text sits on active solid pills (`#8FA8C8`).

### Accent & Semantic Roles
- **Primary Accent (`#8FA8C8`):** Soft washed indigo for active UI navigation segments, primary action triggers, interactive toggles, and global progress indicators.
- **Secondary Focus Accent (`#C88256`):** Luminous rust for active Pomodoro countdown counters, streak fires, examination alerts, and immediate urgency callouts.
- **Status Success / Regular (`#4E9F72`):** Soft sage green for completed coursework, validated attendance, and normal weekly routine slots.
- **Status Warning / Prep (`#D98A3C`):** Warm amber for study recess periods, preparation windows, and approaching assignment thresholds.
- **Status Critical / Absence (`#EF4444`):** Coral crimson for missed deadlines, emergency calendar adjustments, and attendance warnings.

## Typography

The typographic hierarchy separates narrative prose from technical facts.

- **Headlines (Plus Jakarta Sans):** Tightly tracked display weights with organic curves counteract the clinical structure of the grid. Bengali script renders cleanly within these proportions.
- **Body & Controls (Inter):** Workhorse sans-serif deployed for academic notes, reflective journals, syllabi descriptions, and standard operational microcopy.
- **Metadata, Timers & Tabular Data (JetBrains Mono):** Mandatory for countdown clocks, duration intervals, course codes (e.g., `CSE 201`, `EEE 109`), credit values, GPA calculations, and timestamp badges. Always enable OpenType `tnum` (tabular numbers) to guarantee jitter-free rendering during active countdown increments.

## Layout & Spacing

### System Architecture
The application uses a responsive modular column grid anchored to an 8px base rhythm (with 4px micro-subdivisions for compact controls).

- **Desktop (≥1024px):** Fixed-height 60px top bar pinned to the upper edge. The primary workspace operates on a 12-column layout bounded by a maximum content container of 1440px with `margin-desktop: 2rem` and `gutter-desktop: 1.5rem`.
- **Tablet (768px - 1023px):** Fluid 8-column layout, `gutter: 1rem`, `margin: 1.5rem`. Top navigation collapses low-priority utility actions into a drawer.
- **Mobile (<768px):** Single-column stack with dynamic safe area insets. The desktop navigation transfers into a 64px floating bottom capsule dock elevated above the bottom safe area by `1rem`.

### Navigation Shells
- **Desktop Top Shell (60px):**
  - Left: Logotype mark `"চন্দ্রবিন্দু • CHONDROBINDU"` in `#EDEAE0`.
  - Center: Segmented pill dock encapsulating six core modules: `[ Home | Courses | Timer | Planner | Journal | Insights ]`.
  - Right: Global action cluster containing `⌘K Quick Find`, notification bell, theme toggle, and user profile avatar.
- **Mobile Floating Dock (64px):**
  - Horizontally centered, detached capsule floating 16px above the device bottom boundary.
  - Houses 5 primary views: `[ Home | Courses | Timer | Planner | Insights ]`.
  - The Journal is accessed via a dedicated top-bar action button alongside the profile trigger sheet.

## Elevation & Depth

This system avoids diffuse drop shadows and artificial lighting sources. Instead, depth is established through layered tonal stepping and crisp borders.

### Depth Stratification
1. **Bedrock Canvas (`#171C24`):** The absolute background. Zero elevation.
2. **Pressed / Recessed Wells (`#13171E`):** Visually sunk into the canvas using an interior 1px stroke of `#2E3846` and darkened background fill. Used for form inputs, inactive task tracks, and code blocks.
3. **Resting Card Layer (`#202733`):** Sits directly upon the canvas, delineated by an exterior 1px border (`#2E3846`). No drop shadow is applied.
4. **Active / Hover State:** Cards elevate on user interaction not by casting a shadow, but by transitioning their border to `#8FA8C8` at 40% opacity or advancing surface lightness to `#262E3C`.
5. **Floating Overlay Shells:** Modals, drop-down menus, and floating docks utilize `#202733` rendered with a 90% opacity alpha channel and a 16px background blur filter (`backdrop-filter: blur(16px)`), framed with a 1px border in `#2E3846`.

## Shapes

The geometric framework balances card architecture with pill actions:

- **Cards & Major Modular Units:** Use `rounded-2xl` (16px / 1rem radius) to frame analytical content, schedule routines, and timer centers.
- **Input Fields & Inset Containers:** Standardized at `rounded-lg` (8px / 0.5rem radius) to reinforce structural precision.
- **Segmented Docks, Navigational Items & Status Badges:** Fully rounded (`rounded-full` / 9999px pill geometry) to cleanly delineate interactive touch targets from structural data cards.
- **Dividers & Metric Rules:** Fixed 1px hairline elements without rounded caps.

## Components

### Buttons
- **Primary Action:** Solid pill (`rounded-full`), `#8FA8C8` fill with `#13171E` bold label text. Hover shifts to `#A2BBD9`.
- **Secondary Action:** Ghost pill with `#202733` background, 1px border in `#2E3846`, and `#EDEAE0` text. Hover brings border to `#8FA8C8`.
- **Focus Action (Pomodoro/Session):** Solid or ghost pill powered by Luminous Rust (`#C88256`) with dark slate label text on solid, or `#C88256` text with rust border on ghost.

### Navigation Dock (Desktop & Mobile)
- **Container:** Slate indigo (`#202733`) at 90% alpha, 16px blur, surrounded by a 1px `#2E3846` border, shaped as `rounded-full`.
- **Tab Item:** Inactive tabs use `#94A3B8` text. The active tab switches to an illuminated pill backplate (`#8FA8C8`) with dark slate typography (`#13171E`) and seamless transition physics.

### Cards & Surfaces
- Structural surface `#202733`, framed by 1px `#2E3846`, with corner radius `rounded-2xl`.
- Padding scales from `space-md` (mobile) to `space-lg` (desktop).
- Header sections within cards sit flush or are demarcated by a 1px `#2E3846` separator line.

### Input Fields & Search Bars
- Background set to recessed container `#13171E`, border 1px `#2E3846`, corner radius `rounded-lg`.
- Text color `#EDEAE0`, placeholder `#94A3B8` at 60% opacity.
- Focus state switches the border to `#8FA8C8` with zero outer glow rings.
- Inline shortcuts (such as `⌘K`) are rendered via monospace label chips in `#94A3B8` over a `#202733` background.

### Academic Metadata Chips & Status Badges
- Built using `JetBrains Mono`, `label-caps` (11px uppercase), `rounded-full`, padding `4px 10px`.
- **Regular Routine / Completed:** `#4E9F72` text over `rgba(78, 159, 114, 0.12)` background.
- **Exam Window / Prep:** `#D98A3C` text over `rgba(217, 138, 60, 0.12)` background.
- **Exam Day / CT / Viva:** `#C88256` text over `rgba(200, 130, 86, 0.16)` background.
- **Course Code Identifier:** `#8FA8C8` text over `rgba(143, 168, 200, 0.12)` background.

### Focus Timer Display
- Centers an oversized display counter (`display-timer`) using tabular numerals in JetBrains Mono.
- Enclosed by a recessed circular track (`#13171E`) with an active progress stroke rendered in `#C88256`.
- Accompanying interval counters, phase badges (Study, Short Break, Long Break), and current course association tags sit beneath the numerical read-out in `code-sm`.

### Form Controls (Checkboxes & Radios)
- Box footprint 18x18px, base background `#13171E`, 1px border `#2E3846`, `rounded-sm` (4px) for checkboxes and `rounded-full` for radios.
- Selected state fills with `#8FA8C8` bearing a crisp `#13171E` checkmark glyph.