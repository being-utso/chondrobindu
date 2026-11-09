# Product Requirements Document (PRD) & Design Specification
## Project: Chondrobindu (চন্দ্রবিন্দু) • Academic Operating System & Deep Focus Suite

---

### 1. Executive Summary & Vision
**Chondrobindu (চন্দ্রবিন্দু)** is a cross-platform Academic Operating System and Deep Focus Tracker engineered specifically for rigorous academic regimes (university engineering scholars, collegiate programs, and high-stakes admission candidates such as BUET, Medical, and Engineering tracks).

Bridging the tactile elegance of classical editorial printing with the utilitarian precision of an IDE and laboratory terminal, Chondrobindu unifies syllabus tracking, circadian focus cycles, attendance analytics, routines, and markdown journaling into a distraction-free, synchronized workstation.

---

### 2. Brand Identity & Design Philosophy
- **Name**: Chondrobindu (চন্দ্রবিন্দু) — derived from the Bengali nasal diacritic `ঁ`, symbolizing focus, inflection, and the catalytic focal dot (Bindu) nestled in an orbital crescent.
- **Aesthetic Movement**: *Neo-Brutalist Architectural Editorial meets Technical Lab Terminal*. Tactile paper textures, crisp 1px borders, monospace engineering metadata, and razor-sharp typographic hierarchy without gratuitous rounded bubble aesthetics.
- **Design Systems**:
  1. **Light Mode ("Lime Wash & Indigo Dye")**:
     - Canvas Background: `#EDEAE0` (Lime wash warm paper)
     - Elevated Surfaces: `#F7F5F0` / `#FFFFFF`
     - Borders & Outlines: `#DCD7C8` / `#C4BDAC`
     - Ink Typography: `#1F2A3A` (Deep Indigo Ink)
     - Primary Brand Accent: `#2F4A6D` (Natural Indigo)
     - Secondary Warm Accent: `#A5673F` / `#B84A39` (Terracotta Rust / Clay)
  2. **Dark Mode ("Indigo Slate & Luminous Rust")**:
     - Canvas Background: `#171C24` (Nocturne charcoal slate)
     - Elevated Surfaces: `#202733` / `#13171E`
     - Borders & Outlines: `#2E3846` / `#343942`
     - Primary Typography: `#EDEAE0` / `#E2E8F0`
     - Soft Accent: `#8FA8C8` (Muted Indigo)
     - Radiant Core Accent: `#C88256` (Luminous Copper / Terracotta Rust)
- **Typography Scale**:
  - Primary UI & Prose: *Plus Jakarta Sans* / Classical High-Contrast Editorial Serif (Bengali & English headings)
  - Technical Specs, Timers & Codes: *JetBrains Mono*

---

### 3. Core Feature Architecture & Modules

#### 3.1. Authentication & Academic Onboarding Portal
- **Desktop**: Dual-pane architectural monolith (left: scholastic brand banner, celestial aperture glyph, track metadata; right: sign-in/registration toggle with tabbed track configuration).
- **Mobile**: Responsive vertical stack with tactile segmented controls.
- **Academic Track Logic**:
  - *University Scholar*: Department (EEE, CSE, ME, CE, etc.), Level/Term (`L1-T1` to `L4-T2`), Student ID, and Credit Target (3.75–4.00 CGPA).
  - *College & Admission Candidate*: HSC Batch year, Division (Science / Business / Humanities), and conditional Target Selection matrix:
    - Primary Admission Targets: Engineering (BUET / CKET), Medical (DMC / AFMC), University Science (DU / JU / RU), IBA / BBA.
    - Secondary backup chips and custom track tags.

#### 3.2. Home Dashboard (Bento Grid)
- **Academic Status Bar**: Current Level, Term, Week cycle (`Week 04 of 14`), and real-time CGPA / Semester Progress indicators.
- **Next Academic Anchor**: Instant countdown to imminent lectures, labs, or class tests (CTs) with room codes, course codes, and instructor designations.
- **Deep Focus Cadence**: Daily focus hours counter (`Today's Focus: 3h 45m / Target 5h`), active streak badge (`12 Days`), and Pomodoro cycle meter (`3/5 Completed`).
- **Course Health Grid**: Compact progress bars for active subjects with syllabus completion percentages and upcoming evaluation warnings.

#### 3.3. Courses & Syllabus Workspace
- **Subject Registry**: Filterable list by theory vs. sessional/lab courses.
- **4-Tab Sub-navigation**:
  1. *Syllabus*: Collapsible chapter accordions, lecture tracking, subtopic checklists with inline focus launch buttons.
  2. *Assessments*: Class Tests (CTs), Midterms, Term Finals, and Lab Quizzes with grading weightage calculations.
  3. *Resources*: Curated textbook references, slide repositories, and lab manuals (no unorganized folder dumping).
  4. *Attendance & Notes*: Sectional lecture summaries and attendance safety margin alarms (e.g. alert if below 75%).

#### 3.4. Academic Planner & Routine
- **Dynamic Weekly Timetable**: Monospace time matrix with crisp block cells indicating Theory vs. Sessional labs, instructors, and room allocations.
- **Exam / Evaluation Calendar**: Monthly grid with date-badge overlays, multi-tier exam pills, and submission deadlines.
- **Attendance Ledger**: Quick-toggle attendance register (`[ Present | Late | Absent ]`) updating semester compliance in real time.

#### 3.5. Focus Timer Studio
- **Precision Arc / Ring Display**: Circular countdown with SVG drafting rings, cycle counter (`Cycle 2 of 5`), and interval ratios (`25m Work / 5m Rest`, `50m Deep / 10m Reset`).
- **Context Binding**: Direct linkage to current course syllabus topic (e.g., `EEE 101: AC Circuit Analysis`).
- **Inline Scratchpad / Brain Anchor**: Quick distraction capture notepad to offload fleeting thoughts without breaking flow.
- **Cadence Metrics**: Live session tally, cumulative daily focus gauge, and ambient sound generator presets (White Noise, Library, Binaural Alpha).

#### 3.6. Insights & Analytics
- **Circadian Focus Heatmap**: 52-week GitHub-style activity grid scaled by focus density.
- **Subject Time Allocation**: High-contrast donut chart comparing theoretical study vs. problem sets vs. lab reports.
- **Productivity & Streak Analytics**: Weekly rolling averages, peak focus hours (morning vs. late night), and milestone velocity tracking.

#### 3.7. Academic Journal & Brain Dump
- **Multi-Format Editor**: Markdown checklist support, syntax-highlighted code blocks, and formatted LaTeX equation rendering for engineering formulas.
- **Bilingual Tagging & Course Mapping**: Link journal entries directly to syllabus milestones and problem sets.
- **Search & Word Velocity**: Monospace word count, reading time calculator, and instant sync dispatch.

#### 3.8. Scholar Profile & Preferences
- **Student Profile**: Academic institution, department, registration ID, and scholastic honor roll status.
- **Theme Engine**: Seamless toggle between *Lime Wash & Indigo Dye* (Light), *Indigo Slate & Luminous Rust* (Dark), and System Auto-sync.
- **Preferences & Sync**: Pomodoro interval customization, notification thresholds, cloud backup status, and session termination (`[ Sign Out ]`).

#### 3.9. Help & Support & Developer Colophon
- **Tactile Shortcut Matrix**: Standardized `<kbd>` shortcut badges (`⌘K`, `Space`, `N`, `D`, `R`, `Esc`) with high-contrast borders.
- **Direct Telemetry & Bug Dispatch**: Clean categorized submission card (`Bug Report`, `Feature Req`, `General`) with local diagnostic context.
- **Developer Colophon**: Architectural attribution honoring the scholar origins (Shahriyer Sayem, BUET EEE), release versioning, and community channels.

---

### 4. Technical & Non-Functional Specifications
1. **Device Support**: Fully responsive across **Desktop Web** (1440px / 1280px / 960px bento containers) and **Mobile App** (390px viewport with ergonomic thumb-zone bottom navigation docks).
2. **Accessibility**: All interactive states, inputs, and badges strictly conform to WCAG AA / AAA standards (minimum 4.5:1 text contrast ratio, clear active stroke rings, and high-visibility focus states).
3. **Typography & Layout Integrity**: Strict prevention of line overflow, no clipping inside bordered containers, and uniform badge pill radii across both color themes.
4. **Data Sync**: Offline-first architectural posture with optimistic local updates synced to central cloud storage.
