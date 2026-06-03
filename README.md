<p align="center">
  <img width="70%" alt="gd-fsrs-thumbnail" src="https://github.com/user-attachments/assets/c7d35bda-da67-4048-b440-eed61df8ea55" />
</p>

**FSRS-6 spaced-repetition scheduler for Godot 4** — a faithful GDScript port of
[py-fsrs](https://github.com/open-spaced-repetition/py-fsrs) (v6.x).

It mirrors py-fsrs's module structure, class/field/method names, constants, and
mathematical behavior.

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

**All datetimes are UTC Unix timestamps (float seconds)**,
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

## License

The upstream py-fsrs project is MIT-licensed. This port follows suit.
