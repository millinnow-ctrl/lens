# LensMood — Product Strategy (research-grounded)

> Working note by the autonomous product effort. Subordinate to
> `docs/MASTER_DIRECTIVE.md`. This translates the owner's *Deep Research
> Report* into decisions that fit **the actual product**.

## 0. The most important finding: the research brief is mis-scoped

The owner commissioned a "LensMood Deep Research Report." It is rigorous and
well-sourced, but it **assumes the wrong product category**. On its own first
page it records every product dimension as *"Unspecified"* and then adopts a
working frame of:

> "a mobile app for lightweight emotional check-ins, reflection … and insight
> over time"

i.e. a **mood-tracker / wellbeing journal**, benchmarked against Daylio, How
We Feel, Finch, Stoic, Reflectly, and Bearable. The name *LensMood*
(Lens + **Mood**) almost certainly steered the researcher there.

**LensMood is not that.** Per `CLAUDE.md` and `MASTER_DIRECTIVE.md` it is a
**film-look camera app** — 18 film "lenses," a real AVFoundation camera, a
develop ceremony, a Print Room, and a VHS camcorder. Its true competitive set
is **VSCO, Dazz Cam, 1998 Cam, Photoroom, Lapse** — creative-photo products,
not wellbeing trackers.

**Consequence:** we do **not** implement the report's mood-tracker *features*
(one-tap mood selector, emotion matrix, streak repair, if-then reminders,
weekly mood correlations). We **do** adopt its *principles*, which are
category-agnostic and mostly already validated HCI. Everything below is that
translation.

> Recommendation to owner: if a genuinely photo-first research pass is wanted,
> re-run the brief with the category stated ("iOS film-emulation camera app").
> Meanwhile the transferable layer below is safe to act on now.

## 1. What transfers (principle → LensMood action)

| Report principle (evidence) | Transfers? | LensMood translation |
|---|---|---|
| Reduce motor/choice/cognitive cost at the moment of action (Fitts, Hick, cognitive load) | ✅ fully | The core loop is **open → pick a look / shoot → develop → save/share**. Keep it one-hand, few decisions, big targets. |
| ≥44pt (iOS) / 48dp (Android) tap targets; full-width buttons easier to hit | ✅ fully | Audit every control to ≥44pt. (First ship — see §4.) |
| 3–5 global bottom-nav destinations | ✅ fully | We have 4 slots + a dominant center **Capture** — already on-pattern. Watch for creep; consider merging Print+Tape into one "Studio" only if it tests better (§3). |
| Immediate post-action value/reward; short action→insight loop | ✅ fully | The **develop ceremony** already does real on-device compute and shows decisions. Strengthen the finish moment ("here's what LensMood saw / did"). |
| Progressive disclosure; don't overwhelm | ✅ fully | Advanced capture dials, LUT internals, surfaces stay behind disclosure. |
| Ethical freemium: keep the core action free, monetize **depth** (advanced looks, exports, packs); annual-default, value-framed, post-value paywall timing; no dark patterns | ✅ fully | This is our eventual model (§5). Gates stay **OFF** until launch per directive. |
| Trust/privacy as a product feature; on-device processing; minimal permissions; clear disclosure | ✅ fully | Vision + film engine run **on-device**; `PrivacyInfo.xcprivacy` shipped; Photos is **add-only**. Keep and surface this. |
| Performance: fast cold start, offline-first, never lose the artifact, compress/cache, render visible range first | ✅ fully | §6. A camera app is judged on shutter-to-review latency and never losing a shot. |
| Business-oriented analytics taxonomy + Remote-Config experiments | ⚠️ later | Right architecture, but premature pre-backend. Taxonomy captured in §7 so instrumentation is a lookup, not a redesign, when a backend lands. |
| Mood check-in flow, emotion vocabulary matrix, streaks, if-then mood reminders, mood correlations | ❌ no | Wrong category. Do **not** build. |
| Habit reminders tied to user cues, tapering | ➖ weak | A creative app isn't a daily-obligation app. A *gentle*, opt-in "golden-hour / on this day" resurfacing could be tested later — never nagging. |

## 2. North-star & guardrail metrics (re-derived for a creative app)

The report's north-star ("weekly meaningful reflections per retained user") is a
mood-app metric. The creative-app analogue that ties frequency to **realized
value** (creation, not vanity opens):

- **North star:** *Finished looks per active creator per week* — a develop that
  ends in a **save or share**. Capture without a saved/shared result is
  unrealized value.
- **Activation:** % of new users who **develop + save their first photo** in the
  first session (time-to-first-delight).
- **Core engagement:** develops per WAU; distinct looks tried per WAU.
- **Retention:** D1 / D7 / D30 by cohort.
- **Quality/reliability:** shutter→review latency; develop success rate;
  crash-free sessions; **zero lost captures** (a release gate).
- **Trust:** Photos-permission grant rate; export success; deletion success.

## 3. Prioritized roadmap (mapped to the real product)

**Now — remove friction from the first creative loop**
1. Accessibility & touch-target pass to ≥44pt across nav + controls. *(first ship)*
2. Time-to-first-delight audit: cold start → a developed, saved photo with the
   fewest taps; strong empty/first-run state.
3. Confirm the develop "reward moment" reads as real computation, not a filter.

**Next — increase perceived value per develop**
4. A crisp post-develop "what LensMood did" card (on-device scene/subject read),
   outcome-worded, not jargon.
5. Look discovery: make the 18 looks legible and comparable without overwhelm
   (progressive disclosure of dials/EXIF).

**Later — ethical monetization (gates still OFF until launch)**
6. Value-framed, post-value paywall architecture, Remote-Config-driven (§5).
7. Premium depth moat: advanced looks/packs, higher-res + batch export,
   premium surfaces — never the core capture.

## 4. First ship (this round)

Accessibility & tap-target pass — the report's highest-confidence, lowest-risk,
category-agnostic recommendation (Apple HIG 44pt; Material 48dp; Fitts/Hick).
Concretely: guarantee ≥44pt hit areas on the nav dock and primary controls.
See the accompanying diff.

## 5. Ethical monetization model (for launch; NOT built yet)

Free forever: capturing, developing, saving your own photos, core looks, basic
library. Premium (subscription, **annual-default value anchor**, monthly
alternative): advanced/seasonal look packs, high-res + batch export, premium
surfaces/print templates, camcorder depth. One-time packs for subscribe-averse
users. **Guardrails (FTC dark-pattern report):** paywall only *after* a
delivered result, outcome-framed copy ("see every look on your photo"), plain
restore/manage, honest renewal terms, no confirm-shaming, no gate on a
vulnerable moment. Pricing is a **remote-config surface**, not hard-coded.
Rule: *monetize delight, never friction.*

## 6. Performance program

Cold start: preload only the first surface; defer LUT packs, heavy previews,
video. Capture: minimize shutter→review latency; never drop a frame. Data:
offline-first; a developed photo is only "done" once written to Photos —
**never lose a capture**. Images: cache thumbnails, generate display variants,
bound in-memory library (already capped at 48). Charts/history: render the
visible range first. Release gates: crash-free sessions + zero-lost-capture.

## 7. Analytics taxonomy (captured now, instrumented when a backend exists)

Business-oriented, vendor-agnostic events (translate mood→creative):
`app_opened`, `first_run_completed`, `capture_started {source}`,
`develop_started {look_id, source}`, `develop_finished {look_id, ms}`,
`photo_saved {look_id, resolution}`, `photo_shared {channel}`,
`look_previewed {look_id}`, `print_created {surface}`, `tape_developed`,
`paywall_viewed {trigger_surface, plan_order}`, `trial_started {plan}`,
`subscription_converted {billing_period}`, `subscription_canceled {tenure}`.
Inject experiment buckets once at a single wrapper so vendor swaps and A/B
attribution stay cheap.
