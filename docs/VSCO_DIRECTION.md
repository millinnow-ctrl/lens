# LensMood — VSCO editorial direction (dark premium)

Research + build spec for shifting LensMood off the porcelain-white base
(the biggest "template/AI" tell) toward VSCO's dark, photo-forward,
editorial premium feel. User direction: **full VSCO dark but not pure
black**, **near-zero accent** (violet only on the logo + the single
primary action; everything else monochrome). Keep the 3D carousel, all
features, the develop reveal, and the motion work.

## What makes VSCO read as premium (research)

Sources: VSCO rebrand coverage (It's Nice That, Vice), VSCO support/feature
pages, UI/UX case studies (Medium/UX Collective).

- **Near-black darkroom canvas.** Monochrome chrome; the photograph is the
  only color on screen. "You'd see the photo and nothing else" (Joel Flory).
  This is the core move — it makes any photo look considered.
- **Zero brand accent.** No gradients, no colored chrome. Preset labels take
  their color from the actual film box/canister — color comes from content.
- **Custom sans (VSCO Gothic), UPPERCASE wide-tracked labels**, hairline
  bipolar sliders on a ~#3A3A3A track, white-ringed preset carousel.
- **Sharp/restrained, generous negative space, thin white line icons,
  fluid animation, clear swipe affordances.**
- **Film-literate control names**: Strength / Character / Warmth — validates
  our "levels" vocabulary (Character, Warmth already match).
- **Trade-off to avoid**: VSCO's extreme minimalism hurt discoverability
  (unclear icons). We keep labels + clarity; adopt the restraint, not the
  obscurity.

## New token system (index.css @theme) — warm near-black, NOT #000

    --color-paper:    #131217   (app canvas — warm charcoal, faint violet cast)
    --color-surface:  #1c1a22   (elevated card/panel)
    --color-elevated: #24222c   (raised control wells / recessed inverts)
    --color-ink:      #f3f1f6   (primary text — warm off-white)
    --color-ink-soft: #a7a2b2   (secondary text)
    --color-fog:      #6d6879   (tertiary / captions)
    --color-hairline: #2b2833   (dividers, borders)
    --color-vf:       #0d0c11   (deepest well — viewfinder/contact sheet)
    --color-violet:   #8b5cf6   (THE single accent — used sparingly)

Accent rule (near-zero): violet appears ONLY on (a) the logo wordmark and
(b) the one primary action per screen (Develop / Export / Start / Upgrade
CTA). Selection & active states use **white/near-white** rings and fills,
VSCO-style — NOT violet, NOT gradient. Kill `grad-text`/`grad-fill` as a
spread device (logo mark keeps its gradient as the brand exception only).

## Conversion rules (per surface — how to darken without a rebuild)

1. **Token flip is the spine.** Most components read tokens (bg-paper,
   bg-surface, text-ink, border-hairline) and invert for free.
2. **Hardcoded light values must be hunted**: `bg-white`, `text-white` used
   as chrome, `#fff`, `#f4f1f4`, `bg-black/5` fills, `rgb(23 19 31 / …)`
   shadows/borders (these were dark-on-light; on dark they vanish → switch
   to `rgb(255 255 255 / …)` at low alpha for hairlines/insets).
3. **Surfaces that were already dark (bg-vf viewfinder, contact sheet)**
   now sit on a dark app — give them a hairline top-highlight
   (`inset 0 1px 0 rgb(255 255 255/0.06)`) + a 1px `border-hairline` so they
   read as a distinct machined well, not a void.
4. **Shadows**: soft drop shadows disappear on dark. Replace card elevation
   with a 1px hairline border + a subtle inset top-highlight (material edge),
   not big blur shadows.
5. **Photos dominate**: cards become mostly image with minimal dark chrome;
   negative space is the dark canvas, not white.
6. **Selected/active → white** (ring/fill), reserving violet for primaries.
7. **Home hero, deck, dock, sheets, modals, studio, gallery, pricing,
   landing, legal** all adopt the dark tokens. The 3D carousel keeps its
   scroll/paint math; only the card chrome + ground shadow tint adapt.
8. **Status bar / theme-color** → dark; splash/PWA theme-color to #131217.

## Keep (do not touch)
- The 3D MoodSphere carousel (scroll/paint/spin physics).
- All features, routes, engine, levels/named-stops, face-lock, share cards,
  develop reveal + motion (only their colors adapt to dark).
- Violet as the single accent + the logo.
