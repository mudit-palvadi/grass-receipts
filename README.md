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


     GENERATED ON DEVICE. NO SERVER,
        NO ACCOUNT, NO SIGNAL.
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
