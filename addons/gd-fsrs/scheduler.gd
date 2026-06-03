## fsrs.scheduler
## ---------------
## The FSRS spaced-repetition scheduler. Enables the reviewing and future
## scheduling of cards according to the FSRS-6 algorithm.
##
## Mirrors fsrs/scheduler.py. Datetimes are UTC Unix timestamps (float seconds)
## and intervals are tracked internally in seconds. Learning/relearning steps
## are stored as arrays of float seconds (py-fsrs uses timedelta objects).
class_name FSRSScheduler
extends RefCounted

const FSRS_DEFAULT_DECAY := 0.1542
const DEFAULT_PARAMETERS := [
	0.212,
	1.2931,
	2.3065,
	8.2956,
	6.4133,
	0.8334,
	3.0194,
	0.001,
	1.8722,
	0.1666,
	0.796,
	1.4835,
	0.0614,
	0.2629,
	1.6483,
	0.6014,
	1.8729,
	0.5425,
	0.0912,
	0.0658,
	FSRS_DEFAULT_DECAY,
]

const STABILITY_MIN := 0.001
const LOWER_BOUNDS_PARAMETERS := [
	STABILITY_MIN,
	STABILITY_MIN,
	STABILITY_MIN,
	STABILITY_MIN,
	1.0,
	0.001,
	0.001,
	0.001,
	0.0,
	0.0,
	0.001,
	0.001,
	0.001,
	0.001,
	0.0,
	0.0,
	1.0,
	0.0,
	0.0,
	0.0,
	0.1,
]

const INITIAL_STABILITY_MAX := 100.0
const UPPER_BOUNDS_PARAMETERS := [
	INITIAL_STABILITY_MAX,
	INITIAL_STABILITY_MAX,
	INITIAL_STABILITY_MAX,
	INITIAL_STABILITY_MAX,
	10.0,
	4.0,
	4.0,
	0.75,
	4.5,
	0.8,
	3.5,
	5.0,
	0.25,
	0.9,
	4.0,
	1.0,
	6.0,
	2.0,
	2.0,
	0.8,
	0.8,
]

const MIN_DIFFICULTY := 1.0
const MAX_DIFFICULTY := 10.0

const SECONDS_PER_DAY := 86400.0

const FUZZ_RANGES := [
	{"start": 2.5, "end": 7.0, "factor": 0.15},
	{"start": 7.0, "end": 20.0, "factor": 0.1},
	{"start": 20.0, "end": INF, "factor": 0.05},
]

## Seedable RNG used for interval fuzzing. Static so tests can pin the seed
## (via FSRSScheduler.seed(n)) the way py-fsrs uses random.seed(n).
static var _rng := RandomNumberGenerator.new()

var parameters: Array[float]
var desired_retention: float
var learning_steps: Array  ## float seconds
var relearning_steps: Array  ## float seconds
var maximum_interval: int
var enable_fuzzing: bool
var _DECAY: float
var _FACTOR: float


## Result of review_card(): the updated card and its corresponding review log.
class ReviewResult:
	extends RefCounted
	var card: FSRSCard
	var review_log: FSRSReviewLog

	func _init(p_card: FSRSCard, p_review_log: FSRSReviewLog) -> void:
		card = p_card
		review_log = p_review_log


func _init(
	p_parameters: Array = DEFAULT_PARAMETERS,
	p_desired_retention: float = 0.9,
	p_learning_steps: Array = [60.0, 600.0],
	p_relearning_steps: Array = [600.0],
	p_maximum_interval: int = 36500,
	p_enable_fuzzing: bool = true,
) -> void:
	var err := validate_parameters(p_parameters)
	assert(err.is_empty(), err)
	if err != "":
		push_error(err)

	parameters = []
	for v in p_parameters:
		parameters.append(v)
	desired_retention = p_desired_retention
	learning_steps = []
	for s in p_learning_steps:
		learning_steps.append(float(s))
	relearning_steps = []
	for s in p_relearning_steps:
		relearning_steps.append(float(s))
	maximum_interval = p_maximum_interval
	enable_fuzzing = p_enable_fuzzing

	# Only computable when the parameter set has the expected length.
	if parameters.size() == LOWER_BOUNDS_PARAMETERS.size():
		_DECAY = -float(parameters[20])
		_FACTOR = pow(0.9, 1.0 / _DECAY) - 1.0


## Seeds the static fuzz RNG (analogous to Python's random.seed).
static func seed(n: int) -> void:
	_rng.seed = n


static func validate_parameters(params: Array) -> String:
	if params.size() != LOWER_BOUNDS_PARAMETERS.size():
		return "Expected %d parameters, got %d." % [LOWER_BOUNDS_PARAMETERS.size(), params.size()]

	var error_messages: Array = []
	for index in range(params.size()):
		var parameter: float = params[index]
		var lower_bound: float = LOWER_BOUNDS_PARAMETERS[index]
		var upper_bound: float = UPPER_BOUNDS_PARAMETERS[index]
		if not (lower_bound <= parameter and parameter <= upper_bound):
			error_messages.append(
				"parameters[%d] = %s is out of bounds: (%s, %s)"
				% [index, parameter, lower_bound, upper_bound]
			)

	if error_messages.size() > 0:
		return "One or more parameters are out of bounds:\n" + "\n".join(error_messages)

	return ""


func get_card_retrievability(card: FSRSCard, current_datetime = null) -> float:
	if card.last_review == null or card.stability == null:
		return 0.0

	if current_datetime == null:
		current_datetime = Time.get_unix_time_from_system()

	var elapsed_days: int = max(0, _days_between(current_datetime, card.last_review))

	return pow(1.0 + _FACTOR * elapsed_days / card.stability, _DECAY)


func review_card(
	card: FSRSCard,
	rating: int,
	review_datetime = null,
	review_duration = null,
) -> ReviewResult:
	card = card.clone()

	if review_datetime == null:
		review_datetime = Time.get_unix_time_from_system()

	var days_since_last_review = _days_between(review_datetime, card.last_review)

	var next_interval: float = 0.0  # seconds

	match card.state:
		FSRSState.Learning:
			assert(card.step != null)	
			if card.stability == null or card.difficulty == null:
				card.stability = _initial_stability(rating)
				card.difficulty = _initial_difficulty(rating, true)
			elif days_since_last_review != null and days_since_last_review < 1:
				card.stability = _short_term_stability(card.stability, rating)
				card.difficulty = _next_difficulty(card.difficulty, rating)
			else:
				card.stability = _next_stability(
					card.difficulty,
					card.stability,
					get_card_retrievability(card, review_datetime),
					rating,
				)
				card.difficulty = _next_difficulty(card.difficulty, rating)

			# calculate the card's next interval
			if learning_steps.size() == 0 or (
				card.step >= learning_steps.size()
				and rating in [FSRSRating.Hard, FSRSRating.Good, FSRSRating.Easy]
			):
				card.state = FSRSState.Review
				card.step = null
				next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
			else:
				match rating:
					FSRSRating.Again:
						card.step = 0
						next_interval = learning_steps[card.step]
					FSRSRating.Hard:
						# card step stays the same
						if card.step == 0 and learning_steps.size() == 1:
							next_interval = learning_steps[0] * 1.5
						elif card.step == 0 and learning_steps.size() >= 2:
							next_interval = (learning_steps[0] + learning_steps[1]) / 2.0
						else:
							next_interval = learning_steps[card.step]
					FSRSRating.Good:
						if card.step + 1 == learning_steps.size():  # the last step
							card.state = FSRSState.Review
							card.step = null
							next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
						else:
							card.step += 1
							next_interval = learning_steps[card.step]
					FSRSRating.Easy:
						card.state = FSRSState.Review
						card.step = null
						next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
					_:
						push_error("Unknown rating: %s" % rating)

		FSRSState.Review:
			# update the card's stability and difficulty
			if days_since_last_review != null and days_since_last_review < 1:
				card.stability = _short_term_stability(card.stability, rating)
			else:
				card.stability = _next_stability(
					card.difficulty,
					card.stability,
					get_card_retrievability(card, review_datetime),
					rating,
				)

			card.difficulty = _next_difficulty(card.difficulty, rating)

			# calculate the card's next interval
			match rating:
				FSRSRating.Again:
					if relearning_steps.size() == 0:
						next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
					else:
						card.state = FSRSState.Relearning
						card.step = 0
						next_interval = relearning_steps[card.step]
				FSRSRating.Hard, FSRSRating.Good, FSRSRating.Easy:
					next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
				_:
					push_error("Unknown rating: %s" % rating)

		FSRSState.Relearning:
			# update the card's stability and difficulty
			if days_since_last_review != null and days_since_last_review < 1:
				card.stability = _short_term_stability(card.stability, rating)
				card.difficulty = _next_difficulty(card.difficulty, rating)
			else:
				card.stability = _next_stability(
					card.difficulty,
					card.stability,
					get_card_retrievability(card, review_datetime),
					rating,
				)
				card.difficulty = _next_difficulty(card.difficulty, rating)

			# calculate the card's next interval
			if relearning_steps.size() == 0 or (
				card.step >= relearning_steps.size()
				and rating in [FSRSRating.Hard, FSRSRating.Good, FSRSRating.Easy]
			):
				card.state = FSRSState.Review
				card.step = null
				next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
			else:
				match rating:
					FSRSRating.Again:
						card.step = 0
						next_interval = relearning_steps[card.step]
					FSRSRating.Hard:
						if card.step == 0 and relearning_steps.size() == 1:
							next_interval = relearning_steps[0] * 1.5
						elif card.step == 0 and relearning_steps.size() >= 2:
							next_interval = (relearning_steps[0] + relearning_steps[1]) / 2.0
						else:
							next_interval = relearning_steps[card.step]
					FSRSRating.Good:
						if card.step + 1 == relearning_steps.size():  # the last step
							card.state = FSRSState.Review
							card.step = null
							next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
						else:
							card.step += 1
							next_interval = relearning_steps[card.step]
					FSRSRating.Easy:
						card.state = FSRSState.Review
						card.step = null
						next_interval = _next_interval(card.stability) * SECONDS_PER_DAY
					_:
						push_error("Unknown rating: %s" % rating)

		_:
			push_error("Unknown card state: %s" % card.state)

	if enable_fuzzing and card.state == FSRSState.Review:
		next_interval = _get_fuzzed_interval(next_interval)

	card.due = review_datetime + next_interval
	card.last_review = review_datetime

	var review_log := FSRSReviewLog.new(card.card_id, rating, review_datetime, review_duration)

	return ReviewResult.new(card, review_log)


func reschedule_card(card: FSRSCard, review_logs: Array) -> FSRSCard:
	for review_log in review_logs:
		if review_log.card_id != card.card_id:
			push_error(
				"ReviewLog card_id %d does not match Card card_id %d"
				% [review_log.card_id, card.card_id]
			)
			return null

	var sorted_logs := review_logs.duplicate()
	sorted_logs.sort_custom(func(a, b): return a.review_datetime < b.review_datetime)

	var rescheduled_card := FSRSCard.new(card.card_id, FSRSState.Learning, null, null, null, card.due)

	for review_log in sorted_logs:
		var res := review_card(rescheduled_card, review_log.rating, review_log.review_datetime)
		rescheduled_card = res.card

	return rescheduled_card


func to_dict() -> Dictionary:
	var ls: Array = []
	for step in learning_steps:
		ls.append(int(step))
	var rls: Array = []
	for step in relearning_steps:
		rls.append(int(step))
	return {
		"parameters": parameters.duplicate(),
		"desired_retention": desired_retention,
		"learning_steps": ls,
		"relearning_steps": rls,
		"maximum_interval": maximum_interval,
		"enable_fuzzing": enable_fuzzing,
	}


static func from_dict(source_dict: Dictionary) -> FSRSScheduler:
	var ls: Array = []
	for step in source_dict["learning_steps"]:
		ls.append(float(step))
	var rls: Array = []
	for step in source_dict["relearning_steps"]:
		rls.append(float(step))
	return FSRSScheduler.new(
		source_dict["parameters"],
		float(source_dict["desired_retention"]),
		ls,
		rls,
		int(source_dict["maximum_interval"]),
		bool(source_dict["enable_fuzzing"]),
	)


func to_json(indent = null) -> String:
	return JSON.stringify(to_dict(), FSRSCard._indent_string(indent), true, true)


static func from_json(source_json: String) -> FSRSScheduler:
	return from_dict(JSON.parse_string(source_json))


func equals(other) -> bool:
	if other == null or not (other is FSRSScheduler):
		return false
	return (
		parameters == other.parameters
		and desired_retention == other.desired_retention
		and learning_steps == other.learning_steps
		and relearning_steps == other.relearning_steps
		and maximum_interval == other.maximum_interval
		and enable_fuzzing == other.enable_fuzzing
	)


func _to_string() -> String:
	return "FSRSScheduler(%s)" % str(to_dict())


# --- internal math helpers (exact ports of fsrs/scheduler.py) ---

## Integer floor of whole days between two unix timestamps (Python timedelta.days).
## Returns null when `earlier` is null.
static func _days_between(later: float, earlier):
	if earlier == null:
		return null
	return int(floorf((later - earlier) / SECONDS_PER_DAY))


## Python's round(): round-half-to-even (banker's rounding).
static func _py_round(x: float) -> int:
	var f := floorf(x)
	var diff := x - f
	if diff < 0.5:
		return int(f)
	elif diff > 0.5:
		return int(f) + 1
	else:
		var fi := int(f)
		if fi % 2 == 0:
			return fi
		return fi + 1


func _clamp_difficulty(difficulty: float) -> float:
	return min(max(difficulty, MIN_DIFFICULTY), MAX_DIFFICULTY)


func _clamp_stability(stability: float) -> float:
	return max(stability, STABILITY_MIN)


func _initial_stability(rating: int) -> float:
	return _clamp_stability(parameters[rating - 1])


func _initial_difficulty(rating: int, clamp: bool) -> float:
	var initial_difficulty: float = parameters[4] - exp(parameters[5] * (rating - 1)) + 1.0
	if clamp:
		initial_difficulty = _clamp_difficulty(initial_difficulty)
	return initial_difficulty


func _next_interval(stability: float) -> int:
	var next_interval: float = (stability / _FACTOR) * (pow(desired_retention, 1.0 / _DECAY) - 1.0)
	var ni := _py_round(next_interval)  # intervals are full days
	ni = max(ni, 1)  # must be at least 1 day long
	ni = min(ni, maximum_interval)  # can not be longer than the maximum interval
	return ni


func _short_term_stability(stability: float, rating: int) -> float:
	var short_term_stability_increase: float = (
		exp(parameters[17] * (rating - 3 + parameters[18])) * pow(stability, -parameters[19])
	)
	if rating in [FSRSRating.Good, FSRSRating.Easy]:
		short_term_stability_increase = max(short_term_stability_increase, 1.0)
	return _clamp_stability(stability * short_term_stability_increase)


func _next_difficulty(difficulty: float, rating: int) -> float:
	var arg_1: float = _initial_difficulty(FSRSRating.Easy, false)
	var delta_difficulty: float = -(parameters[6] * (rating - 3))
	var arg_2: float = difficulty + _linear_damping(delta_difficulty, difficulty)
	var next_difficulty: float = _mean_reversion(arg_1, arg_2)
	return _clamp_difficulty(next_difficulty)


func _linear_damping(delta_difficulty: float, difficulty: float) -> float:
	return (10.0 - difficulty) * delta_difficulty / 9.0


func _mean_reversion(arg_1: float, arg_2: float) -> float:
	return parameters[7] * arg_1 + (1.0 - parameters[7]) * arg_2


func _next_stability(difficulty: float, stability: float, retrievability: float, rating: int) -> float:
	var next_stability: float
	if rating == FSRSRating.Again:
		next_stability = _next_forget_stability(difficulty, stability, retrievability)
	elif rating in [FSRSRating.Hard, FSRSRating.Good, FSRSRating.Easy]:
		next_stability = _next_recall_stability(difficulty, stability, retrievability, rating)
	else:
		push_error("Unknown rating: %s" % rating)
		next_stability = stability
	return _clamp_stability(next_stability)


func _next_forget_stability(difficulty: float, stability: float, retrievability: float) -> float:
	var long_term: float = (
		parameters[11]
		* pow(difficulty, -parameters[12])
		* (pow(stability + 1.0, parameters[13]) - 1.0)
		* exp((1.0 - retrievability) * parameters[14])
	)
	var short_term: float = stability / exp(parameters[17] * parameters[18])
	return min(long_term, short_term)


func _next_recall_stability(difficulty: float, stability: float, retrievability: float, rating: int) -> float:
	var hard_penalty: float = parameters[15] if rating == FSRSRating.Hard else 1.0
	var easy_bonus: float = parameters[16] if rating == FSRSRating.Easy else 1.0
	return stability * (
		1.0
		+ exp(parameters[8])
		* (11.0 - difficulty)
		* pow(stability, -parameters[9])
		* (exp((1.0 - retrievability) * parameters[10]) - 1.0)
		* hard_penalty
		* easy_bonus
	)


## Takes a calculated interval (seconds) and adds a small amount of random fuzz.
func _get_fuzzed_interval(interval: float) -> float:
	var interval_days := int(floorf(interval / SECONDS_PER_DAY))

	if interval_days < 2.5:  # fuzz is not applied to intervals less than 2.5
		return interval

	var bounds := _get_fuzz_range(interval_days)
	var min_ivl: int = bounds[0]
	var max_ivl: int = bounds[1]

	# the next interval is a random value between min_ivl and max_ivl
	var fuzzed_interval_days := (_rng.randf() * (max_ivl - min_ivl + 1)) + min_ivl
	var result: int = min(_py_round(fuzzed_interval_days), maximum_interval)

	return result * SECONDS_PER_DAY


func _get_fuzz_range(interval_days: int) -> Array:
	var delta := 1.0
	for fuzz_range in FUZZ_RANGES:
		delta += fuzz_range["factor"] * max(
			min(float(interval_days), fuzz_range["end"]) - fuzz_range["start"], 0.0
		)

	var min_ivl := _py_round(interval_days - delta)
	var max_ivl := _py_round(interval_days + delta)

	# make sure the min_ivl and max_ivl fall into a valid range
	min_ivl = max(2, min_ivl)
	max_ivl = min(max_ivl, maximum_interval)
	min_ivl = min(min_ivl, max_ivl)

	return [min_ivl, max_ivl]
