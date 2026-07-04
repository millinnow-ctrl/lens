# LensMood — Premium Design Research → Build Rules

Source: deep-research harness (search + fetch succeeded; adversarial
verification aborted on API rate-limit, so claims below are marked by
source tier and treated as directional, not gospel). Primary sources:
Halide's own engineering blog, Apple Developer news, PetaPixel/RNI.

## What the premium apps actually do

### Halide Mark II (pro camera — the "instrument" benchmark) — PRIMARY
- **Frames itself as a physical camera, not software.** This one decision
  drives every UI choice. → Our studio must read as a device, not a form.
- **Gesture dials over sliders.** Exposure/focus are swipe-driven virtual
  dials modeled on real camera dials, not 0–100 fields. → named stops +
  drag, no numeric readouts.
- **Custom etched typography** evoking type engraved on lens barrels. →
  mono, letter-spaced, engraved highlight; never a default UI font look.
- **Fixed control positions for muscle memory** — controls never move or
  reflow contextually. → stable panel layout, no jumping.
- **Rejected the "flight-simulator" maximal-dial aesthetic as
  intimidating**; goal was "excitement without intimidation." → restraint.
  Skeuomorphic *feel*, not skeuomorphic *clutter*.
- **Single accent color for active state** (yellow, camera homage) — but
  they learned color ALONE is too weak a signal; active state also needs
  shape/weight. → our violet accent must be reinforced by fill/scale, not
  carry active-state alone.
- **Tap a control → in-context description.** Labels teach. → each level
  control can reveal what it does.

### RNI Films (film emulation — editorial restraint) — SECONDARY
- **Names filters after real film stocks** (Agfa, Kodak, Fuji, Ilford),
  never abstract preset names. → our look names already do this in spirit;
  the *level vocabulary* should feel film-literate (grain "Chunky", temp
  "Golden") not slider-literate.
- **Organizes by physical film type** (negative / slide / instant /
  vintage / mono) not by mood. → a possible future shelf taxonomy.
- **Minimal interaction cost**, restraint.

### VSCO (utility) — UNVERIFIED (known industry pattern)
- Stepped adjustment scale and preset-strength dialing; tasteful,
  editorial, quiet. Discrete steps read as considered, not raw.

## UI science (directional)
- **Discrete labeled stops** reduce decision load and read as "curated /
  considered" vs a raw continuous value that reads as "config file."
  Named stops are harder to screenshot-clone — the vocabulary is the moat.
- **Premium = restraint + materiality + latency-free haptics.** Fewer
  elements, better materials (etched type, machined edges, real shadows),
  instant tactile response. Maximalism reads cheap.

## BUILD RULES for LensMood (what the revamp implements)
1. **No numbers in fine-tune.** Replace every 0–100 readout with a named
   stop (levels.ts). The stop name sits where the number was, in mono.
2. **Stepped, not smooth.** The slider snaps to stops with a haptic tick;
   dragging feels like a detented dial, not a continuous fader.
3. **Engraved instrument panel.** Mono uppercase labels with a top
   highlight (etched), tick rail per control aligned to the stops, the
   active stop marked by fill + scale (not color alone).
4. **Restraint.** No new glow. Violet only on the active stop / primary.
   Kill anything that reads as "SaaS settings screen."
5. **Muscle memory.** Panel layout fixed; controls never reorder.
6. **Film-literate vocabulary.** Grain None/Fine/Soft/Heavy/Chunky;
   Temperature Cold/Cool/Neutral/Warm/Golden; Flash Off/Kiss/Fill/Party/
   Blast; Character Trace/Soft/Balanced/Full/Pushed; Shadows Open/Lifted/
   Deep/Crushed; Skin Off/Touch/Studio.
7. **Tap-to-learn.** Long-press / tap a control label reveals a one-line
   description of what that stop does to the photo.
