# gd-fsrs

**FSRS-6 spaced-repetition scheduler for Godot 4** — a faithful GDScript port of
[py-fsrs](https://github.com/open-spaced-repetition/py-fsrs) (v6.x).

It mirrors py-fsrs's module structure, class/field/method names, constants, and
mathematical behavior. The full py-fsrs `test_basic.py` suite is ported to GDScript
and passes (39/39).

> Scope: scheduling only. The ML **Optimizer** (parameter training) is out of scope,
> as is any editor UI or persistence — storing cards/logs is up to you.

---

## Requirements

- Godot **4.4+** (developed and tested on **4.6.stable**).

## Installation

Copy the `addons/gd-fsrs/` folder into your project's `addons/` directory, then enable
**gd-fsrs** under *Project → Project Settings → Plugins* (optional — the classes are
exposed via `class_name`, so the plugin needs no autoloads).

The public classes become globally available: `FSRSCard`, `FSRSReviewLog`,
`FSRSScheduler`, `FSRSRating`, `FSRSState`.

---

## Quick start

```gdscript
var scheduler := FSRSScheduler.new()
var card := FSRSCard.new()

# Review the card with a rating. Returns a result object.
var result := scheduler.review_card(card, FSRSRating.Good)
card = result.card
var review_log := result.review_log

# `card.due` is a UTC Unix timestamp (float seconds) — schedule the next review then.
print("Next due at unix time: ", card.due)

# Predict recall probability right now (0.0–1.0):
print("Retrievability: ", scheduler.get_card_retrievability(card))
```

### Datetimes

There are no `datetime` objects. **All datetimes are UTC Unix timestamps (float seconds)**,
as returned by `Time.get_unix_time_from_system()`. To pass a specific moment, convert it:

```gdscript
var t := Time.get_unix_time_from_datetime_string("2022-11-29T12:30:00")  # treated as UTC
scheduler.review_card(card, FSRSRating.Good, t)
```

Learning/relearning steps and intervals are also expressed in **seconds**
(`60.0` = 1 minute, `600.0` = 10 minutes, `86400.0` = 1 day).

---

## API reference

### `FSRSRating` (enum)
`Again = 1`, `Hard = 2`, `Good = 3`, `Easy = 4`

### `FSRSState` (enum)
`Learning = 1`, `Review = 2`, `Relearning = 3`

### `FSRSCard` (extends `RefCounted`)

| Field | Type | Notes |
|-------|------|-------|
| `card_id` | `int` | Epoch milliseconds at creation (auto-generated, unique). |
| `state` | `int` | An `FSRSState` value. |
| `step` | `int` \| `null` | `null` when the card is in the Review state. |
| `stability` | `float` \| `null` | `null` until the first review. |
| `difficulty` | `float` \| `null` | `null` until the first review. |
| `due` | `float` | UTC Unix timestamp (seconds). |
| `last_review` | `float` \| `null` | UTC Unix timestamp; `null` until first review. |

```gdscript
FSRSCard.new(card_id = null, state = FSRSState.Learning, step = null,
             stability = null, difficulty = null, due = null, last_review = null)

card.clone() -> FSRSCard           # shallow copy
card.to_dict() -> Dictionary
FSRSCard.from_dict(d) -> FSRSCard  # static
card.to_json(indent = null) -> String
FSRSCard.from_json(s) -> FSRSCard  # static
card.equals(other) -> bool         # value equality
```

### `FSRSReviewLog` (extends `RefCounted`)

| Field | Type |
|-------|------|
| `card_id` | `int` |
| `rating` | `int` (an `FSRSRating` value) |
| `review_datetime` | `float` (UTC Unix timestamp) |
| `review_duration` | `int` \| `null` (milliseconds) |

Same `to_dict` / `from_dict` / `to_json` / `from_json` / `equals` helpers as `FSRSCard`.

### `FSRSScheduler` (extends `RefCounted`)

```gdscript
FSRSScheduler.new(
    parameters       = FSRSScheduler.DEFAULT_PARAMETERS,  # 21 floats
    desired_retention = 0.9,
    learning_steps   = [60.0, 600.0],   # seconds
    relearning_steps = [600.0],         # seconds
    maximum_interval = 36500,           # days
    enable_fuzzing   = true)
```

GDScript has no keyword arguments. To change just one option with the others defaulted,
construct and then set the field — e.g. `var s := FSRSScheduler.new(); s.enable_fuzzing = false`.
(Custom `parameters` must be passed to the constructor, since the decay factor is derived
from them at construction.)

```gdscript
# Review a card. Returns a ReviewResult with .card and .review_log.
scheduler.review_card(card, rating, review_datetime = null, review_duration = null) -> ReviewResult

# Predicted recall probability (0.0–1.0) at a given time (defaults to now).
scheduler.get_card_retrievability(card, current_datetime = null) -> float

# Replay a card's history under this scheduler (e.g. after changing parameters).
# Returns null (and pushes an error) if any log's card_id doesn't match the card.
scheduler.reschedule_card(card, review_logs: Array) -> FSRSCard

# Validate a parameter set without raising. Returns "" if valid, else an error message.
FSRSScheduler.validate_parameters(params: Array) -> String   # static

# Seed the fuzzing RNG for reproducible intervals (see "Notes" below).
FSRSScheduler.seed(n: int)                                   # static

scheduler.to_dict() / from_dict() / to_json() / from_json() / equals()  # serialization
```

---

## Running the tests

The acceptance suite is a standalone headless runner that prints pass/fail per test
and a final total:

```sh
godot --headless --path . --script res://addons/gd-fsrs/tests/test_basic.gd
```

On a fresh checkout the `class_name` globals must be registered first — run an import
pass once if the script reports unknown identifiers:

```sh
godot --headless --path . --import
```

Float results are asserted within `1e-9` (or each test's own looser tolerance);
state/step/rating are asserted as exact integers.

---

## Notes & differences from py-fsrs

These are deliberate adaptations where Python features don't map directly to GDScript.
Mathematical behavior is unchanged.

- **No exceptions.** Where py-fsrs raises `ValueError`, this port logs via `push_error`
  and returns a detectable value: `validate_parameters()` returns an error string
  (`""` = OK), and `reschedule_card()` returns `null` on a mismatched `card_id`.
- **`review_card` returns a result object** (`ReviewResult` with `.card` and `.review_log`),
  not a positional tuple.
- **Serialization stores float Unix timestamps**, not ISO strings — Godot's
  `Time` string conversions are second-precision only, so floats round-trip losslessly.
  JSON is written with full float precision.
- **Fuzzing uses Godot's native `RandomNumberGenerator`** (PCG32), not Python's
  Mersenne Twister. Fuzzed intervals are therefore valid but will not match py-fsrs's
  exact seeded values. Use `FSRSScheduler.seed(n)` for reproducible fuzzing, or set
  `enable_fuzzing = false` for fully deterministic intervals.
- **Out of scope:** the Optimizer, editor UI, and persistence.

## License

The upstream py-fsrs project is MIT-licensed. This port follows suit.
