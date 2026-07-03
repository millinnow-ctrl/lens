# LensMood — Design Specification v2 "Instrument"

This is the binding spec for the LensMood rebrand. Every screen must follow it exactly.
The previous design read as AI-generated (pill buttons, soft-rounded cards, emoji icons,
violet gradient accents, glow blobs). Version 2 is the opposite: a **precision optical
instrument** — the design language of camera hardware, film packaging, and darkroom
contact sheets. Think Leica manual, Teenage Engineering panel, Swiss photo-book.

## Non-negotiables (the anti-AI checklist)

1. **Zero emojis.** Anywhere. Icons are drawn SVG strokes from `src/components/icons.tsx`.
2. **Zero pill buttons.** All buttons are rectangles with 2px radius max.
3. **Zero soft-rounded cards.** Structural blocks are square-cornered with 1px hairlines.
   Only image thumbnails may have 2px radius. Round shapes are reserved for *optical*
   elements: record dots, lens circles, slider knobs.
4. **Zero gradient text, zero blur blobs, zero glassmorphism.**
5. **No violet.** The accent is record-red, used only as a *signal* (selected states,
   record dots, live indicators, small emphasis) — never as button fill or large area.
6. **No centered-everything.** Default composition is left-aligned on a 12-col grid;
   center only what is optically centered (the viewfinder subject).
7. Numbers, values, EXIF data always in mono with `tabular-nums`.

## Tokens (already defined in `src/index.css` — use these, never raw hex)

Color (CSS vars via Tailwind theme):
- `paper`      #F6F5F1  — page ground, warm-biased (chosen, not default white)
- `surface`    #FCFCFA  — raised panels
- `ink`        #171614  — primary text, primary buttons
- `ink-soft`   #52504A  — secondary text
- `fog`        #8B887E  — tertiary text, placeholders
- `hairline`   #DDDAD2  — 1px rules and borders
- `signal`     #E1251B  — record red. Signal only.
- `vf`         #101010  — viewfinder / dark surfaces
- `vf-chrome`  #8E8C86  — text on dark surfaces

Type:
- Display + UI: `font-sans` → Archivo Variable.
  - Hero/section headlines: `font-sans font-semibold tracking-[-0.02em]` with
    `font-stretch: 115%` via the provided class `type-display`. Sentence case.
  - UI labels/buttons: Archivo 500–600, 13–14px.
- Technical: `font-mono` → IBM Plex Mono. Used for: eyebrows (11px uppercase
  `tracking-[0.14em]`), slider values, EXIF chrome, prices, frame numbers, timestamps,
  badges. Class `label-mono` = the standard eyebrow.
- Body: Archivo 400, 15px/1.6, max-width ~65ch.

Radius: `--radius-xs: 2px` for controls/thumbnails; everything else 0.
Shadow: none on cards (hairlines carry structure). Modals only: `--shadow-modal`.
Spacing: 4px base; sections separated by hairline rules (`<hr class="rule" />` or
`border-t border-hairline`), not by floating whitespace alone.

## Component recipes (classes defined in index.css)

- `.btn` base + `.btn-primary` (ink block, paper text) / `.btn-outline` (1px ink border)
  / `.btn-quiet` (no border, underline on hover). Heights: `.btn-lg` 48px, default 40px,
  `.btn-sm` 32px. Labels: Archivo 600 13px, `tracking-[0.01em]`, sentence case.
  Active selected state may add `.btn-signal-dot` (red dot before label).
- `.panel` — surface bg + 1px hairline border, square corners.
- `.rule` — 1px hairline horizontal rule.
- `.label-mono` — mono 11px uppercase tracking eyebrow, fog color.
- `.value-mono` — mono 12px tabular-nums ink-soft.
- `.tag` — mono 10px uppercase boxed tag (1px border, 2px 6px padding). `.tag-signal`
  red border+text. `.tag-fill` ink bg paper text. Used for PRO / TRENDING / THIS WEEK.
- `.lm-slider` — restyled: 2px track (ink fill portion, hairline rest), 16px white knob
  with 2px ink ring. Value shown right in `.value-mono`.
- Film-stock style card (`.stock-card` pattern): square-cornered, hairline border,
  image on top (aspect 4/5, the ONLY rounded-2px element inside), label block below on
  surface: `label-mono` index (LM·01 …), name Archivo 600 14px, tagline fog 12px.
  Selected: border becomes `signal`, red dot appears top-right of label block,
  index turns signal. Premium: `.tag` "PRO" in top-right of image.
- Viewfinder frame (the studio/hero preview): `vf` background, square corners, corner
  brackets drawn via CSS (`.vf-corners` adds 4 L-shaped marks), top strip with
  mono chrome text (style name left, f/1.4 · ISO 400 right), 1px hairline.

## Iconography

`src/components/icons.tsx` exports stroke icons (24 viewBox, strokeWidth 1.5,
strokeLinecap="square"): Camera, Upload, Play, Pause, Download, Share, Heart,
Close, Check, ArrowRight, ArrowLR (compare), Film, Grid, Home, Tag, Library, Dot
(filled circle), Aperture. Use these — never emoji, never ad-hoc paths in pages.

## Motion

Keep: shutter flash, develop reveal, generation progress, marquee scroll.
Everywhere else: 150ms ease-out opacity/translate only. No springs on hover, no
floating animations, no scale-ups on cards (hover = hairline darkens to ink, or a
translate-y of exactly -2px, pick per component but be consistent within a section).
Respect `prefers-reduced-motion` (framer-motion handles this via the global).

## Copy rules

Voice: precise, quietly confident, a little dry. The playfulness lives in the share
captions, not in the UI chrome. No exclamation marks in UI. No emoji.
- Buttons say what they do: "Open studio", "Develop", "Save photo", "Copy caption".
- Eyebrows are mono caps: "CAMERA MOODS", "THE STUDIO", "PRICING".
- Technical flavor is real, not decorative: film-stock indexes (LM·01), EXIF strips,
  frame counters "FRAME 03/12", timestamps.

## Per-page notes

### Nav (done by lead — reference only)
Hairline bottom border, paper bg. Wordmark: "LensMood" Archivo 700 + small red dot
after. Desktop links quiet, active = ink + red dot prefix. Right: mono credits counter
"3/5 FREE", "Sign in" quiet, "Open studio" btn-primary. Mobile: bottom bar, hairline
top, 4 tabs with icons + mono 10px labels, active = signal.

### LandingPage
- Hero: 12-col grid. Left 6 cols: `label-mono` eyebrow "THE AI AESTHETIC CAMERA",
  display headline "Turn any photo into a cinematic camera shot." (Archivo expanded,
  ~clamp(2.5rem,6vw,4.5rem), tracking tight, sentence case, `text-balance`),
  one-paragraph sub in body type, CTA row: btn-primary lg "Try it free" +
  btn-outline lg "Explore camera moods" (scrolls to #styles). Below, a mono meta line:
  "5 FREE SHOTS/MO · NO SIGN-UP · ON-DEVICE PROCESSING" with hairline above.
- Right 6 cols: the before/after slider inside a viewfinder frame with corner brackets
  and mono chrome strip. No float animation, no glow. Under it a mono caption line:
  "DRAG TO COMPARE — A24 STILL applied by the LensMood engine, live".
- Styles section: full-bleed marquee of film-stock cards between two hairlines,
  section header row: eyebrow + display h2 "One photo. Every era." left, "Open studio"
  btn-outline right.
- How it works: 3 columns divided by vertical hairlines (real sequence → mono numbers
  01/02/03 top of each), stroke icon, Archivo 600 title, fog body. No cards.
- Captions band: `vf` background full-width strip. Left: eyebrow + h2 "Captions
  included." + sub + btn (paper bg ink text). Right: 3 caption rows styled like
  contact-sheet slates: hairline-bordered rows, mono index C-01/02/03, caption text
  in Archivo italic? No — Archivo 400, quotes. No emoji speech bubbles.
- Featured mood: horizontal panel with hairline, image left (small, 2px radius),
  eyebrow "FEATURED THIS WEEK", name, description, btn-outline "Shoot it".
- Pricing teaser: left-aligned block, display h2, sub, two buttons. Hairline above.

### Studio suite
- Empty state: eyebrow + display headline left-aligned above UploadArea.
- UploadArea: large drop zone = 1px dashed hairline (dashes 6px), square, paper bg;
  on drag-over border turns signal + bg surface. Inside centered: Camera stroke icon
  (not in a rounded tile), headline Archivo 600, sub body, two buttons ("Choose photos"
  btn-primary, "Take a photo" btn-outline). Sample strip below: mono eyebrow
  "NO PHOTO HANDY — TRY A SAMPLE", 3 thumbnails (2px radius) with mono labels below
  each (not overlaid), hover: hairline→ink.
- Studio editor: viewfinder frame as described (brackets, chrome strip). View toggle:
  segmented control — hairline-bordered row of 3 rectangles, active = ink bg paper
  text (no pill). Actions right: "New photo" btn-quiet, "Export" btn-primary.
- Filmstrip (roll): row of 2px-radius thumbs with mono frame numbers below (01, 02…),
  active = signal underline bar + ink number.
- StyleCarousel: horizontal scroll of `.stock-card`s (see recipe). Card width ~150px.
- AdjustmentPanel: inside `.panel`. Header row: Archivo 600 "Fine-tune" + mono value
  of active preset. Presets: row of `.btn-sm` outline buttons (active = ink fill),
  labels plain words (Natural, Strong, Viral, Cinematic, Editorial) — NO emoji.
  Sliders per recipe with mono values. Reset/save row: btn-quiet + btn-outline sm.
- Developing overlay: on `vf`, centered aperture spinner (existing SVG fine but
  recolor: white blades, signal center dot), progress copy in mono uppercase
  ("READING LIGHTING…"), thin 2px progress bar in signal.
- Paywall modal: no emoji — use Film stroke icon. Copy per voice.

### ExportPanel / modals
- Modal: surface bg, square corners, hairline border, shadow-modal. Close button:
  square 32px hairline-bordered with Close icon.
- Header: eyebrow "DEVELOPED" (mono, signal) + display h3 "Your Disposable Camera shot".
- Preview area on `vf` bg. Actions column: btn-primary "Save photo", btn-outline
  "Share to TikTok / Reels", btn-outline "Copy caption", btn-outline "Copy style link",
  btn-quiet "Try another style". Delivered toast: mono 12px signal text.
- Caption box: hairline panel, `label-mono` "CAPTION", body text with quotes.
- Watermark note: fog 12px, link ink underline.

### PricingPage
- Header: left-aligned eyebrow "PRICING" + display h1 "Rent the camera bag." + sub.
- 4 plans as a connected table-like row: each column hairline-bordered (shared borders,
  like a printed table), square. Featured (Creator): ink bg, paper text, mono tag
  "MOST POPULAR" top. Plan name Archivo 600, blurb fog, price: mono 40px tabular
  "$7" + fog "/month". Features: rows with Check stroke icon (signal in featured).
  CTA full-width btn (featured: paper bg ink text; others: btn-primary).
- Checkout modal: no emoji. Success = Check icon in signal circle outline, copy dry:
  "Watermarks off. Premium moods unlocked."

### Dashboard
- Header row: eyebrow "YOUR LIBRARY" + display h1 + actions right.
- History as CONTACT SHEET: `vf` panel, grid of thumbs (2px radius) each with mono
  frame number + style name below in vf-chrome, delete on hover (square icon button).
  Empty state: Film icon + dry copy + btn.
- Presets: table rows with hairline dividers: name Archivo 600, params in value-mono
  ("INT 80 · GRN 62 · WRM 66"), Use btn-sm outline, Delete btn-quiet.
- Favorites: rows/chips as `.tag`-style rectangles with names + small Shoot link.
- Credits panel: mono huge number "3/5" tabular, thin 2px bar (ink fill on hairline),
  btn-primary "Upgrade". Paid state: plan name + "UNLIMITED" mono.
- Featured mood panel on `vf` as before but square + chrome type.

### AuthModal
Aperture mark (new, monochrome ink + signal dot), headline, Google button = btn-outline
with the G mark, divider hairline with mono "OR", email input (square, hairline,
focus: ink border 1px + no glow ring... use 2px ink outline), btn-primary submit.
Footnote fog 11px.

## Assets
- Sample photos: `src/assets/sample-*.jpg` (real photographs). Use `SAMPLES` import
  from UploadArea / landing as now.
- Logo/mark: `Logo.tsx` exports `ApertureMark` (ink circle + blades + signal dot) and
  wordmark. Keep usage API identical.

## Engineering constraints
- All existing props/state/logic/tests stay intact — this is a re-skin plus copy pass.
  Do not change store APIs, engine, or routing.
- Tailwind 4 tokens come from `@theme` in index.css: colors are `paper, surface, ink,
  ink-soft, fog, hairline, signal, vf, vf-chrome`. Old tokens (violet, mist, cloud…)
  are REMOVED — any reference to them must be replaced.
- `pill-base/pill-primary/pill-violet/pill-ghost/card` classes are gone; use the new
  `.btn*`/`.panel` classes.
- Keep `lm-develop`, `lm-shutter-flash`, `lm-breathe`, `lm-marquee`, `no-scrollbar`,
  `ui-grain` (subtler), `.lm-slider` (restyled) — same names, new looks.
