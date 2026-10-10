# Grass Receipts
lines; the idea is older than both projects.
Flutter, and the inventor is credited rather than ignored. The maths is three
# Grass Receipts

**I touched grass and all I got was this absurd receipt.**

One button. Tap it on the way out, tap it on the way back. While the phone is
in your pocket it counts your steps and notices when you stop moving. When you
come back, a language model running **entirely on the device** prints a
thermal receipt of your time outdoors:

```
                GRASS TOUCHED
              RECEIPT NO. 42
------------------------------------------------
WENT OUTSIDE                        4:04 PM
CAME BACK                           4:47 PM
TIME BAND                    LATE AFTERNOON
------------------------------------------------
1234x STEPS, ON YOUR GOOD LEG
43x   MINUTES AWAY FROM THE SCREEN
1x    BENCH OCCUPIED, BRIEFLY
3x    BIRD THAT SAW YOU
1x    BREEZE, MILD, SUSPICIOUS
------------------------------------------------
TOTAL                        $0.00

YOUR REVIEW
3 stars. Great breeze, no wifi.

SIGNOFF
Come back tomorrow. Grass misses you.
```

The screen is the shortest part of the experience, which is the whole point:
you look at the phone for ten seconds going out and ten seconds coming back.
Everything in between is a pedometer and a clock.

Built for the [Hacktoberfest Open-Source AI Challenge: Week 1 — Touch
Grass](https://dev.to/challenges/hacktoberfest-week1-2026-10-05).

## What is actually here

Status as of the first install on a realme RMX3853 (Android 16):

| Piece | State |
| --- | --- |
| Receipt prompt, parse, validation, template fallback | **Unit tested** — 32 tests, no device needed |
| Torn-edge clipper and dashed rules | **Unit tested** |
| Receipt layout at the 32-column limit | **Widget-tested**, no overflow |
| Setup screen, model picker, download progress | **Runs on hardware** — Qwen3 0.6B download reached 50% and climbing |
| Model install / readiness wiring | **Wired**, download verified in progress |
| Sensor capture (steps, longest stop) | Written, **not yet exercised outdoors** |
| The `TOUCHING GRASS` → `I'M BACK` → receipt flow | Written, **not yet run end to end outdoors** |

An install and a screenshot of the setup screen are in `test/golden/`.

## The printing

The receipt does not appear already printed. It feeds out of the slot in
**14 discrete steps** over 1.7 seconds, with a dark band tracking its leading
edge while it is still inside the machine.

The steps are the part that matters. A single eased glide reads as a web page
loading; the jumps read as a roller tick-tick-ticking. Each step reveals
another ~1/14th of the paper, so the header prints first and the torn edge
appears last, which is also the correct order for a thermal roll.

- `PrintingReveal` in `lib/ui/widgets/printer_chassis.dart` — the `Align` with
  an animated `heightFactor`, plus the quantised fraction.
- `animate: false` skips it entirely, for anyone with motion sensitivity on.
- Both steps are covered by `test/receipt_golden_test.dart`, whose PNG is the
  picture in the write-up.

## What the AI model is actually for

The honest answer, because it is the question a submission should be able to
survive: **the sensors measure, and the model judges.**

The phone measures steps, minutes, time band and the longest standstill. It
cannot decide what kind of walk those add up to, how many times something
plausibly happened, or what the offline minutes meant for the natural world.
Those are the model's job, and the receipt reads as a result:

```
WENT OUTSIDE                       4:04 PM
WALK TYPE                          ESCAPE
1234x STEPS, ON YOUR GOOD LEG
43x   MINUTES AWAY FROM THE SCREEN
 7x   MINUTES OF DOING NOTHING AT ALL
44x   BIRD THAT SAW YOU
 1x   BENCH OCCUPIED, BRIEFLY
TOTAL                        $0.00
WHAT THE GRID MISSED
43 MINUTES OFF THE GRID. THE BIRDS WON.
```

Four things come from the model and not from the phone:

1. **A verdict on the walk** - `WALKTYPE`, one of a closed set the model is
   allowed to reach. It is the line a reader can disagree with, which is the
   point.
2. **Item quantities.** The model writes `44x BIRD THAT SAW YOU`, so a
   three-hour walk and a bathroom break produce receipts that do not look
   interchangeable.
3. **The nature line**, which must quote the measured minutes.
4. **The comedy** - item names, review, signoff.

### Why the quantities are bounded rather than trusted

The model chooses them, so its output cannot be fully verified: nobody knows
how many birds there were. What *can* be checked is whether a number is
**possible**, and that is the one rule enforced in `parseOutput`:

    quantity <= 1 + minutes

A ten-minute walk cannot claim twenty birds. The bound is also stated in the
prompt, so the model is told what it may claim and then held to it.

`ReceiptLine.measured` records which lines are the phone's. The measured step
count and duration are built in Dart and prepended, so the model can add its
own `12x STEPS` line but can never touch the pedometer's 1234 - and in tests a
claim of 999 steps is rejected outright for being impossible.

The nature line has its own check: it must contain the measured minutes as a
whole number. A line that says "43 MINUTES" about a six-minute walk is
decoration pretending to be fact, and that is exactly what this rejects.

All of this is covered by `receipt_service_test.dart` - including the boundary
(44 is allowed on a 43-minute walk, 45 is not) and the failure modes by name,
because the fallback reason is printed on screen.

## The one rule that matters

**The model never decides a number.**

Steps, minutes and the time band are measured by the phone and passed into the
prompt as facts. The model writes the jokes and nothing else, and the two
measured lines are built in Dart and prepended to whatever comes back. A model
that decides to print `999x STEPS` gets to keep that line, labelled unmeasured,
but it cannot touch the pedometer's 1234.

An invented number is worse than a dull one: the person holding the receipt
knows exactly how many steps they took, and a receipt that lies about it is a
broken joke. The `ReceiptLine.measured` flag exists so a reader can tell the
difference.

The same rule licensed the output format. This project answers in

```
ITEM: BIRD THAT SAW YOU
REVIEW: 3 stars. Great breeze, no wifi.
SIGNOFF: Come back tomorrow. Grass misses you.
```

not JSON. A 1B-class model emits valid JSON often enough on a laptop and
unreliably on a phone, and a strict parse failure means a fallback receipt —
so the format is deliberately the one that fails least.

## Why open

Every number above is true in the boring, checkable sense:

- **No server.** There is no backend, no database, no account, no analytics.
  The app has no permission to use the network after the model is installed.
- **No signal needed.** The receipt is written on the device. It works on a
  trail with no bars, which is a thing the theme asked for and most entries
  can only claim.
- **Nothing leaves the phone.** Location is never requested. Steps and
  timestamps live in a `WalkFacts` value object and are discarded when the
  process ends.
- **Nothing to pay.** No API keys, no token metering, no inference bill. The
  running cost of a receipt is zero.
- **Swappable.** The prompt is model-agnostic and the model is a constant in
  [`gemma_runtime.dart`](lib/services/gemma_runtime.dart). Three are wired up
  and selectable in the app, so "open" is a switch you can flip rather than a
  claim in a README.

That last one is the point worth making in the write-up. A closed-API version
of this app would be a `fetch` and an API key. The open version is a 500 MB
file, a prompt you own, and three models you can replace without asking
anyone.

## Models

| Model | Size | Credentials |
| --- | --- | --- |
| **Qwen3 0.6B (INT4)** - default | 329 MB | none |
| **SmolLM2 360M Instruct** | 356 MB | none |
| **Gemma 3 1B-IT (INT4)** | 529 MB | HF token, licence accepted |

The default needs **no Hugging Face account and no token**, so a fresh clone
runs as-is. The Gemma build is there because it is the obvious prize-category
model, and gating it is a Hugging Face licence question rather than a licence
on the weights.

Each spec names its file explicitly. That is not fussiness: the resolver
infers a conventional filename when you leave it out, 404s, and reports
"Model not found", which reads like a bad repo id.

That table is a claim, so it is checkable rather than asserted. A byte-range
request against each file, with no credentials at all:

```
Qwen3 0.6B    -> HTTP 206  (partial content, served)
SmolLM2 360M  -> HTTP 206  (partial content, served)
Gemma 3 1B    -> HTTP 401  (licence not accepted)
```

### The Qwen3 thinking trap

**Qwen3 is a thinking model**, and by default it will not stop thinking. The
first receipt on a real device came back as a template receipt saying "the
model returned too few lines", and the log showed why:

```
ReceiptService: rejected (tooLong) on both attempts.
raw: <|channel|>thought | Okay<channel|> ... SIGNOFF: Come back tomorrow...
```

Every token of its 512-token budget went into `thought` blocks, so the
actual receipt never appeared.

Two fixes, both needed:

1. **Ask the chat API, not the raw session.** `flutter_gemma`'s `InferenceChat`
   appends ` /no_think` to the prompt for Qwen3 when `isThinking: false`
   (chat.dart:167). The raw `InferenceModelSession` has no `modelType`
   parameter, so it cannot do this — which is why this project uses
   `createChat()` instead of `createSession()`.
2. **Strip the markers anyway.** `_cleanModelOutput` removes `think` blocks
   and channel markers on every turn, because a 0.6B model ignores
   instructions inconsistently and one stray marker breaks a line-based parse.

This is also why the fallback exists and why the UI says "Template receipt
printed: ... Your steps and minutes are still the real ones" instead of hiding
it. A silent failure here would have looked like a working app with bad jokes.

## Running it

```bash
flutter pub get
flutter run            # installs the default (Qwen3) model on first launch
```

First launch downloads 329 MB because the receipt writer has to live on the
phone. Choosing Gemma adds a token field on the setup screen; it is held in
memory for the length of one download and never written to disk.

```bash
flutter test           # 32 tests, no device or model needed
flutter analyze        # clean
```

The two `receipt_golden_test.dart` goldens are separate: they need a device
pixel density to render at, and their PNG doubles as the picture in the DEV
write-up.

```bash
flutter test --update-goldens test/receipt_golden_test.dart
```

## Known limits, stated up front

- **The walk ends if the process dies.** Sensor streams are held in the app;
  there is no background service. Closing the app mid-walk loses the walk. A
  `workmanager` periodic sample would fix it and is the obvious next step.
- **Standing still is measured from gaps between step events**, not a motion
  classifier. Ten seconds without a step counts as a stop, so a red light does
  not register but a bench does.
- **Falls back to a template receipt.** If the model cannot be loaded or the
  output cannot be validated, the receipt still prints with the real measured
  numbers and a note saying the model was not at its best. This is by design,
  and the UI says so rather than pretending.
- **One receipt per outing, not per day.** Receipt numbers are derived from
  the step count.
- **Android only** so far. The pedometer and Gemma paths are both
  cross-platform in principle; iOS is untested.

## Credit

The receipt look is a reimplementation of the **Polymer "Receipt Printer"**
experiment by Jean-Philippe Côté ([dqnamo.com](https://www.dqnamo.com/experiments/receipt-printer),
[source](https://github.com/dqnamo/website/blob/main/components/ReceiptPrinter.tsx)).
That source carries **no licence**, so nothing was copied from it — the torn
zigzag edge, the stepped paper feed and the dashed rules are re-derived here in
Flutter, and the inventor is credited rather than ignored. The maths is three
lines; the idea is older than both projects.
