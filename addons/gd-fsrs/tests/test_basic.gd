# godot --headless --path . --script res://addons/gd-fsrs/tests/test_basic.gd
extends SceneTree

const DAY := 86400.0

const TEST_RATINGS_1 := [
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Again,
	FSRSRating.Again,
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Good,
	FSRSRating.Good,
]

# Fuzz intervals observed from Godot's seeded RandomNumberGenerator (PCG32),
# captured during implementation. py-fsrs (MT19937) produces 12 and 11; this
# port uses Godot's native RNG, so the expected values are baked from it.
const FUZZ_SEED_42_DAYS := 10
const FUZZ_SEED_12345_DAYS := 10

var _passed := 0
var _failed := 0
var _current_failed := false
var _fail_msgs: Array = []


func _initialize() -> void:
	# Deterministic baseline for any test that leaves fuzzing enabled.
	FSRSScheduler.seed(0)

	var tests := [
		"test_review_card",
		"test_repeated_correct_reviews",
		"test_memo_state",
		"test_repeat_default_arg",
		"test_datetime",
		"test_Card_dict_serialize",
		"test_Card_json_serialize",
		"test_ReviewLog_dict_serialize",
		"test_ReviewLog_json_serialize",
		"test_Scheduler_dict_serialize",
		"test_Scheduler_json_serialize",
		"test_custom_scheduler_args",
		"test_retrievability",
		"test_good_learning_steps",
		"test_again_learning_steps",
		"test_hard_learning_steps",
		"test_easy_learning_steps",
		"test_review_state",
		"test_relearning",
		"test_fuzz",
		"test_no_learning_steps",
		"test_no_relearning_steps",
		"test_one_card_multiple_schedulers",
		"test_maximum_interval",
		"test_class_repr",
		"test_unique_card_ids",
		"test_stability_lower_bound",
		"test_scheduler_parameter_validation",
		"test_class_eq_methods",
		"test_learning_card_rate_hard_one_learning_step",
		"test_learning_card_rate_hard_second_learning_step",
		"test_long_term_stability_learning_state",
		"test_relearning_card_rate_hard_one_relearning_step",
		"test_relearning_card_rate_hard_two_relearning_steps",
		"test_reschedule_card_same_scheduler",
		"test_reschedule_card_different_parameters",
		"test_reschedule_card_different_desired_retention",
		"test_reschedule_card_different_learning_steps",
		"test_reschedule_card_wrong_review_logs",
	]

	print("Running %d tests...\n" % tests.size())
	for test_name in tests:
		_current_failed = false
		_fail_msgs = []
		Callable(self, test_name).call()
		if _current_failed:
			_failed += 1
			print("  FAIL  %s" % test_name)
			for m in _fail_msgs:
				print("          - %s" % m)
		else:
			_passed += 1
			print("  PASS  %s" % test_name)

	print("\n========================================")
	print("Total: %d   Passed: %d   Failed: %d" % [_passed + _failed, _passed, _failed])
	print("========================================")
	quit(1 if _failed > 0 else 0)


# --- assertion helpers -------------------------------------------------------

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_current_failed = true
		_fail_msgs.append(msg)
	return cond


func _check_approx(a: float, b: float, msg: String, tol := 1e-9) -> bool:
	return _check(absf(a - b) <= tol, "%s (got %s, expected %s, tol %s)" % [msg, a, b, tol])


func _ivl_days(card: FSRSCard) -> int:
	return FSRSScheduler._days_between(card.due, card.last_review)


# --- tests -------------------------------------------------------------------

func test_review_card() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false

	var card := FSRSCard.new()
	var review_datetime := Time.get_unix_time_from_datetime_string("2022-11-29T12:30:00")

	var ivl_history: Array = []
	for rating in TEST_RATINGS_1:
		var r := scheduler.review_card(card, rating, review_datetime)
		card = r.card
		ivl_history.append(_ivl_days(card))
		review_datetime = card.due

	_check(ivl_history == [0, 2, 11, 46, 163, 498, 0, 0, 2, 4, 7, 12, 21],
		"ivl_history = %s" % str(ivl_history))


func test_repeated_correct_reviews() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false

	var card := FSRSCard.new()
	var base := Time.get_unix_time_from_datetime_string("2022-11-29T12:30:00")
	for i in range(10):
		var r := scheduler.review_card(card, FSRSRating.Easy, base + i * 0.000001)
		card = r.card

	_check(card.difficulty == 1.0, "difficulty == 1.0 (got %s)" % card.difficulty)


func test_memo_state() -> void:
	var scheduler := FSRSScheduler.new()

	var ratings := [
		FSRSRating.Again, FSRSRating.Good, FSRSRating.Good,
		FSRSRating.Good, FSRSRating.Good, FSRSRating.Good,
	]
	var ivl_history := [0, 0, 1, 3, 8, 21]

	var card := FSRSCard.new()
	var review_datetime := Time.get_unix_time_from_datetime_string("2022-11-29T12:30:00")

	for idx in range(ratings.size()):
		review_datetime += ivl_history[idx] * DAY
		var r := scheduler.review_card(card, ratings[idx], review_datetime)
		card = r.card

	_check_approx(card.stability, 53.62691, "stability", 1e-4)
	_check_approx(card.difficulty, 6.3574867, "difficulty", 1e-4)


func test_repeat_default_arg() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()
	var now := Time.get_unix_time_from_system()
	var r := scheduler.review_card(card, FSRSRating.Good)
	var time_delta: float = r.card.due - now
	_check(time_delta > 500.0, "due in approx 8-10 minutes (delta %s)" % time_delta)


func test_datetime() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()

	# new cards should be due immediately after creation
	_check(Time.get_unix_time_from_system() >= card.due, "new card due immediately")

	var r := scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	card = r.card

	# due should be later than (or equal to) last review
	_check(card.due >= card.last_review, "due >= last_review")


func test_Card_dict_serialize() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()

	_check(typeof(JSON.stringify(card.to_dict())) == TYPE_STRING, "to_dict() is JSON-serializable")

	var copied := FSRSCard.from_dict(card.to_dict())
	_check(card.equals(copied), "card == copied")
	_check(card.to_dict() == copied.to_dict(), "card.to_dict() == copied.to_dict()")

	var r := scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	var reviewed := r.card
	_check(typeof(JSON.stringify(reviewed.to_dict())) == TYPE_STRING, "reviewed to_dict() serializable")

	var copied_reviewed := FSRSCard.from_dict(reviewed.to_dict())
	_check(reviewed.equals(copied_reviewed), "reviewed == copied_reviewed")
	_check(reviewed.to_dict() == copied_reviewed.to_dict(), "reviewed dicts equal")

	_check(not card.equals(reviewed), "original != reviewed")
	_check(card.to_dict() != reviewed.to_dict(), "original dict != reviewed dict")


func test_Card_json_serialize() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()

	var copied := FSRSCard.from_json(card.to_json())
	_check(card.equals(copied), "card == copied (json)")
	_check(card.to_json() == copied.to_json(), "json strings equal")

	var r := scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	var reviewed := r.card
	var copied_reviewed := FSRSCard.from_json(reviewed.to_json())
	_check(reviewed.equals(copied_reviewed), "reviewed == copied (json)")
	_check(reviewed.to_json() == copied_reviewed.to_json(), "reviewed json equal")

	_check(not card.equals(reviewed), "original != reviewed (json)")
	_check(card.to_json() != reviewed.to_json(), "original json != reviewed json")


func test_ReviewLog_dict_serialize() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()

	var r := scheduler.review_card(card, FSRSRating.Again)
	card = r.card
	var review_log := r.review_log

	_check(typeof(JSON.stringify(review_log.to_dict())) == TYPE_STRING, "review_log serializable")
	var copied := FSRSReviewLog.from_dict(review_log.to_dict())
	_check(review_log.to_dict() == copied.to_dict(), "review_log dicts equal")

	var r2 := scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	var next_log := r2.review_log
	_check(typeof(JSON.stringify(next_log.to_dict())) == TYPE_STRING, "next_log serializable")
	var copied_next := FSRSReviewLog.from_dict(next_log.to_dict())
	_check(next_log.to_dict() == copied_next.to_dict(), "next_log dicts equal")

	_check(review_log.to_dict() != next_log.to_dict(), "logs differ")


func test_ReviewLog_json_serialize() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()

	var r := scheduler.review_card(card, FSRSRating.Again)
	card = r.card
	var review_log := r.review_log

	var copied := FSRSReviewLog.from_json(review_log.to_json())
	_check(review_log.equals(copied), "review_log == copied (json)")
	_check(review_log.to_json() == copied.to_json(), "review_log json equal")

	var r2 := scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	var next_log := r2.review_log
	var copied_next := FSRSReviewLog.from_json(next_log.to_json())
	_check(next_log.equals(copied_next), "next_log == copied (json)")
	_check(next_log.to_json() == copied_next.to_json(), "next_log json equal")

	_check(not review_log.equals(next_log), "logs differ (json)")
	_check(review_log.to_json() != next_log.to_json(), "log json differ")


func test_Scheduler_dict_serialize() -> void:
	var scheduler := FSRSScheduler.new()
	_check(typeof(JSON.stringify(scheduler.to_dict())) == TYPE_STRING, "scheduler serializable")

	var copied := FSRSScheduler.from_dict(scheduler.to_dict())
	_check(scheduler.equals(copied), "scheduler == copied")
	_check(scheduler.to_dict() == copied.to_dict(), "scheduler dicts equal")


func test_Scheduler_json_serialize() -> void:
	var scheduler := FSRSScheduler.new()
	_check(typeof(scheduler.to_json()) == TYPE_STRING, "scheduler to_json() is string")

	var copied := FSRSScheduler.from_json(scheduler.to_json())
	_check(scheduler.equals(copied), "scheduler == copied (json)")
	_check(scheduler.to_json() == copied.to_json(), "scheduler json equal")


func test_custom_scheduler_args() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false

	var card := FSRSCard.new()
	var now := Time.get_unix_time_from_datetime_string("2022-11-29T12:30:00")

	var ivl_history: Array = []
	for rating in TEST_RATINGS_1:
		var r := scheduler.review_card(card, rating, now)
		card = r.card
		ivl_history.append(_ivl_days(card))
		now = card.due

	_check(ivl_history == [0, 2, 11, 46, 163, 498, 0, 0, 2, 4, 7, 12, 21],
		"ivl_history = %s" % str(ivl_history))

	var parameters2 := [
		0.1456, 0.4186, 1.1104, 4.1315, 5.2417, 1.3098, 0.8975, 0.0010,
		1.5674, 0.0567, 0.9661, 2.0275, 0.1592, 0.2446, 1.5071, 0.2272,
		2.8755, 1.234, 0.56789, 0.1437, 0.2,
	]
	var desired_retention2 := 0.85
	var maximum_interval2 := 3650
	var scheduler2 := FSRSScheduler.new(parameters2, desired_retention2, [60.0, 600.0], [600.0], maximum_interval2)

	_check(scheduler2.parameters == parameters2, "parameters set")
	_check(scheduler2.desired_retention == desired_retention2, "desired_retention set")
	_check(scheduler2.maximum_interval == maximum_interval2, "maximum_interval set")


func test_retrievability() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()

	_check(card.state == FSRSState.Learning, "new card is Learning")
	var retrievability := scheduler.get_card_retrievability(card)
	_check(retrievability == 0, "new card retrievability == 0")

	var r := scheduler.review_card(card, FSRSRating.Good)
	card = r.card
	_check(card.state == FSRSState.Learning, "still Learning")
	retrievability = scheduler.get_card_retrievability(card)
	_check(retrievability >= 0 and retrievability <= 1, "0 <= R <= 1 (learning)")

	r = scheduler.review_card(card, FSRSRating.Good)
	card = r.card
	_check(card.state == FSRSState.Review, "now Review")
	retrievability = scheduler.get_card_retrievability(card)
	_check(retrievability >= 0 and retrievability <= 1, "0 <= R <= 1 (review)")

	r = scheduler.review_card(card, FSRSRating.Again)
	card = r.card
	_check(card.state == FSRSState.Relearning, "now Relearning")
	retrievability = scheduler.get_card_retrievability(card)
	_check(retrievability >= 0 and retrievability <= 1, "0 <= R <= 1 (relearning)")


func test_good_learning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	var created_at := Time.get_unix_time_from_system()
	var card := FSRSCard.new()

	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 0, "step 0")

	var r := scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(card.state == FSRSState.Learning, "still Learning")
	_check(card.step == 1, "step 1")
	_check(roundi((card.due - created_at) / 100.0) == 6, "due in ~10 minutes")

	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	_check(card.step == null, "step null")
	_check(roundi((card.due - created_at) / 3600.0) >= 24, "due in over a day")


func test_again_learning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	var created_at := Time.get_unix_time_from_system()
	var card := FSRSCard.new()

	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 0, "step 0")

	var r := scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Learning, "still Learning")
	_check(card.step == 0, "step 0")
	_check(roundi((card.due - created_at) / 10.0) == 6, "due in ~1 minute")


func test_hard_learning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	var created_at := Time.get_unix_time_from_system()
	var card := FSRSCard.new()

	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 0, "step 0")

	var r := scheduler.review_card(card, FSRSRating.Hard, card.due)
	card = r.card
	_check(card.state == FSRSState.Learning, "still Learning")
	_check(card.step == 0, "step 0")
	_check(roundi((card.due - created_at) / 10.0) == 33, "due in ~5.5 minutes")


func test_easy_learning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	var created_at := Time.get_unix_time_from_system()
	var card := FSRSCard.new()

	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 0, "step 0")

	var r := scheduler.review_card(card, FSRSRating.Easy, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	_check(card.step == null, "step null")
	_check(roundi((card.due - created_at) / DAY) >= 1, "due in at least 1 full day")


func test_review_state() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false
	var card := FSRSCard.new()

	var r := scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card

	_check(card.state == FSRSState.Review, "Review")
	_check(card.step == null, "step null")

	var prev_due: float = card.due
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "still Review")
	_check(roundi((card.due - prev_due) / 3600.0) >= 24, "due in at least 1 full day")

	prev_due = card.due
	r = scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(roundi((card.due - prev_due) / 60.0) == 10, "due in 10 minutes")


func test_relearning() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false
	var card := FSRSCard.new()

	var r := scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card

	var prev_due: float = card.due
	r = scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 0, "step 0")
	_check(roundi((card.due - prev_due) / 60.0) == 10, "due in 10 minutes")

	prev_due = card.due
	r = scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "still Relearning")
	_check(card.step == 0, "step 0")
	_check(roundi((card.due - prev_due) / 60.0) == 10, "due in 10 minutes")

	prev_due = card.due
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	_check(card.step == null, "step null")
	_check(roundi((card.due - prev_due) / 3600.0) >= 24, "due in at least 1 full day")


func test_fuzz() -> void:
	# seed 1
	FSRSScheduler.seed(42)
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()
	var r := scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	card = r.card
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	var prev_due: float = card.due
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(_ivl_days(card) == FUZZ_SEED_42_DAYS, "seed 42 interval == %d (got %d)" % [FUZZ_SEED_42_DAYS, _ivl_days(card)])

	# seed 2
	FSRSScheduler.seed(12345)
	card = FSRSCard.new()
	r = scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	card = r.card
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	prev_due = card.due
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(_ivl_days(card) == FUZZ_SEED_12345_DAYS, "seed 12345 interval == %d (got %d)" % [FUZZ_SEED_12345_DAYS, _ivl_days(card)])


func test_no_learning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.learning_steps = []
	_check(scheduler.learning_steps.size() == 0, "no learning steps")

	var card := FSRSCard.new()
	var r := scheduler.review_card(card, FSRSRating.Again, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	_check(_ivl_days(card) >= 1, "interval >= 1")


func test_no_relearning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.relearning_steps = []
	_check(scheduler.relearning_steps.size() == 0, "no relearning steps")

	var card := FSRSCard.new()
	var r := scheduler.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Learning, "Learning")
	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	r = scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "still Review")
	_check(_ivl_days(card) >= 1, "interval >= 1")


func test_one_card_multiple_schedulers() -> void:
	var s_two_learning := FSRSScheduler.new()
	s_two_learning.learning_steps = [60.0, 600.0]
	var s_one_learning := FSRSScheduler.new()
	s_one_learning.learning_steps = [60.0]
	var s_no_learning := FSRSScheduler.new()
	s_no_learning.learning_steps = []

	var s_two_relearning := FSRSScheduler.new()
	s_two_relearning.relearning_steps = [60.0, 600.0]
	var s_one_relearning := FSRSScheduler.new()
	s_one_relearning.relearning_steps = [60.0]
	var s_no_relearning := FSRSScheduler.new()
	s_no_relearning.relearning_steps = []

	var card := FSRSCard.new()

	_check(s_two_learning.learning_steps.size() == 2, "two learning steps")
	var r := s_two_learning.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 1, "step 1")

	_check(s_one_learning.learning_steps.size() == 1, "one learning step")
	r = s_one_learning.review_card(card, FSRSRating.Again, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 0, "step 0")

	_check(s_no_learning.learning_steps.size() == 0, "no learning steps")
	r = s_no_learning.review_card(card, FSRSRating.Hard, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	_check(card.step == null, "step null")

	_check(s_two_relearning.relearning_steps.size() == 2, "two relearning steps")
	r = s_two_relearning.review_card(card, FSRSRating.Again, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 0, "step 0")

	r = s_two_relearning.review_card(card, FSRSRating.Good, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 1, "step 1")

	_check(s_one_relearning.relearning_steps.size() == 1, "one relearning step")
	r = s_one_relearning.review_card(card, FSRSRating.Again, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 0, "step 0")

	_check(s_no_relearning.relearning_steps.size() == 0, "no relearning steps")
	r = s_no_relearning.review_card(card, FSRSRating.Hard, Time.get_unix_time_from_system())
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	_check(card.step == null, "step null")


func test_maximum_interval() -> void:
	var maximum_interval := 100
	var scheduler := FSRSScheduler.new(FSRSScheduler.DEFAULT_PARAMETERS, 0.9, [60.0, 600.0], [600.0], maximum_interval)

	var card := FSRSCard.new()
	for rating in [FSRSRating.Easy, FSRSRating.Good, FSRSRating.Easy, FSRSRating.Good]:
		var r := scheduler.review_card(card, rating, card.due)
		card = r.card
		_check(_ivl_days(card) <= scheduler.maximum_interval, "interval <= max")


func test_class_repr() -> void:
	var card := FSRSCard.new()
	_check(str(card).length() > 0, "card repr non-empty")

	var scheduler := FSRSScheduler.new()
	_check(str(scheduler).length() > 0, "scheduler repr non-empty")

	var r := scheduler.review_card(card, FSRSRating.Good)
	_check(str(r.review_log).length() > 0, "review_log repr non-empty")


func test_unique_card_ids() -> void:
	var card_ids := {}
	for i in range(1000):
		var card := FSRSCard.new()
		card_ids[card.card_id] = true
	_check(card_ids.size() == 1000, "1000 unique card ids (got %d)" % card_ids.size())


func test_stability_lower_bound() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()
	for i in range(1000):
		var r := scheduler.review_card(card, FSRSRating.Again, card.due + DAY)
		card = r.card
		if not _check(card.stability >= FSRSScheduler.STABILITY_MIN, "stability >= STABILITY_MIN"):
			return


func test_scheduler_parameter_validation() -> void:
	_check(FSRSScheduler.validate_parameters(FSRSScheduler.DEFAULT_PARAMETERS) == "", "default params valid")

	var too_high := FSRSScheduler.DEFAULT_PARAMETERS.duplicate()
	too_high[6] = 100
	_check(FSRSScheduler.validate_parameters(too_high) != "", "param too high invalid")

	var too_low := FSRSScheduler.DEFAULT_PARAMETERS.duplicate()
	too_low[10] = -42
	_check(FSRSScheduler.validate_parameters(too_low) != "", "param too low invalid")

	var two_bad := FSRSScheduler.DEFAULT_PARAMETERS.duplicate()
	two_bad[0] = 0
	two_bad[3] = 101
	_check(FSRSScheduler.validate_parameters(two_bad) != "", "two bad params invalid")

	_check(FSRSScheduler.validate_parameters([]) != "", "zero params invalid")

	var one_too_few := FSRSScheduler.DEFAULT_PARAMETERS.slice(0, FSRSScheduler.DEFAULT_PARAMETERS.size() - 1)
	_check(FSRSScheduler.validate_parameters(one_too_few) != "", "one too few invalid")

	var too_many := FSRSScheduler.DEFAULT_PARAMETERS.duplicate()
	too_many.append_array([1.0, 2.0, 3.0])
	_check(FSRSScheduler.validate_parameters(too_many) != "", "too many invalid")


func test_class_eq_methods() -> void:
	var scheduler1 := FSRSScheduler.new()
	var scheduler2 := FSRSScheduler.new(FSRSScheduler.DEFAULT_PARAMETERS, 0.91)
	var scheduler1_copy := FSRSScheduler.from_dict(scheduler1.to_dict())

	_check(not scheduler1.equals(scheduler2), "scheduler1 != scheduler2")
	_check(scheduler1.equals(scheduler1_copy), "scheduler1 == copy")

	var card_orig := FSRSCard.new()
	var card_orig_copy := card_orig.clone()
	_check(card_orig.equals(card_orig_copy), "card == copy")

	# Explicit, distinct review datetimes: get_unix_time_from_system() has coarse
	# resolution on some platforms, so two back-to-back default-now reviews can
	# produce identical logs. py-fsrs relies on datetime.now() advancing.
	var t0 := Time.get_unix_time_from_datetime_string("2022-11-29T12:30:00")
	var r1 := scheduler1.review_card(card_orig, FSRSRating.Good, t0)
	var card_review_1 := r1.card
	var review_log_1 := r1.review_log
	var review_log_1_copy := FSRSReviewLog.from_dict(review_log_1.to_dict())

	_check(not card_orig.equals(card_review_1), "orig != reviewed")
	_check(review_log_1.equals(review_log_1_copy), "review_log == copy")

	var r2 := scheduler1.review_card(card_review_1, FSRSRating.Good, t0 + 600.0)
	var review_log_2 := r2.review_log
	_check(not review_log_1.equals(review_log_2), "review_log_1 != review_log_2")


func test_learning_card_rate_hard_one_learning_step() -> void:
	var first_learning_step := 600.0  # 10 minutes
	var scheduler := FSRSScheduler.new()
	scheduler.learning_steps = [first_learning_step]

	var card := FSRSCard.new()
	var initial_due := card.due

	var r := scheduler.review_card(card, FSRSRating.Hard, card.due)
	card = r.card
	_check(card.state == FSRSState.Learning, "Learning")

	var interval_length: float = card.due - initial_due
	var expected: float = first_learning_step * 1.5
	_check(absf(interval_length - expected) <= 1.0, "hard 1-step interval = 1.5x")


func test_learning_card_rate_hard_second_learning_step() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.learning_steps = [60.0, 600.0]

	var card := FSRSCard.new()
	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 0, "step 0")

	var r := scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 1, "step 1")

	var due_after_first := card.due
	r = scheduler.review_card(card, FSRSRating.Hard, due_after_first)
	card = r.card
	_check(card.state == FSRSState.Learning, "Learning")
	_check(card.step == 1, "step 1")

	var interval_length: float = card.due - due_after_first
	_check(absf(interval_length - 600.0) <= 1.0, "hard second-step interval = step")


func test_long_term_stability_learning_state() -> void:
	var scheduler := FSRSScheduler.new()
	var card := FSRSCard.new()
	_check(card.state == FSRSState.Learning, "Learning")

	var r := scheduler.review_card(card, FSRSRating.Easy, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")

	r = scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")

	var late := card.due + DAY  # a full day after due
	r = scheduler.review_card(card, FSRSRating.Good, late)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")


func test_relearning_card_rate_hard_one_relearning_step() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.relearning_steps = [600.0]

	var card := FSRSCard.new()
	var r := scheduler.review_card(card, FSRSRating.Easy, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")

	r = scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 0, "step 0")

	var prev_due: float = card.due
	r = scheduler.review_card(card, FSRSRating.Hard, prev_due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 0, "step 0")

	var interval_length: float = card.due - prev_due
	_check(absf(interval_length - 600.0 * 1.5) <= 1.0, "hard 1-relearn-step = 1.5x")


func test_relearning_card_rate_hard_two_relearning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.relearning_steps = [60.0, 600.0]

	var card := FSRSCard.new()
	var r := scheduler.review_card(card, FSRSRating.Easy, card.due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")

	r = scheduler.review_card(card, FSRSRating.Again, card.due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 0, "step 0")

	var prev_due: float = card.due
	r = scheduler.review_card(card, FSRSRating.Hard, prev_due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 0, "step 0")

	var interval_length: float = card.due - prev_due
	_check(absf(interval_length - (60.0 + 600.0) / 2.0) <= 1.0, "hard step0 two-relearn avg")

	r = scheduler.review_card(card, FSRSRating.Good, card.due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 1, "step 1")

	prev_due = card.due
	r = scheduler.review_card(card, FSRSRating.Hard, prev_due)
	card = r.card
	_check(card.state == FSRSState.Relearning, "Relearning")
	_check(card.step == 1, "step 1")

	interval_length = card.due - prev_due
	_check(absf(interval_length - 600.0) <= 1.0, "hard step1 = second step")

	r = scheduler.review_card(card, FSRSRating.Easy, prev_due)
	card = r.card
	_check(card.state == FSRSState.Review, "Review")
	_check(card.step == null, "step null")


func test_reschedule_card_same_scheduler() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false
	var card := FSRSCard.new()

	var review_logs: Array = []
	for rating in TEST_RATINGS_1:
		var r := scheduler.review_card(card, rating, card.due)
		card = r.card
		review_logs.append(r.review_log)

	var rescheduled := scheduler.reschedule_card(card, review_logs)
	_check(card != rescheduled, "different objects")
	_check(card.equals(rescheduled), "card == rescheduled")


func test_reschedule_card_different_parameters() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false
	var card := FSRSCard.new()

	var review_logs: Array = []
	for rating in TEST_RATINGS_1:
		var r := scheduler.review_card(card, rating, card.due)
		card = r.card
		review_logs.append(r.review_log)

	var different_parameters := [
		0.12340357383516173, 1.2931, 2.397673571899466, 8.2956, 6.686820427099132,
		0.45021679958387956, 3.077875127553957, 0.053520395733247045, 1.6539992229052127,
		0.1466206769107436, 0.6300772488850335, 1.611965002575047, 0.012840136810798864,
		0.34853762746216305, 1.8878958285806287, 0.8546376191171063, 1.8729,
		0.6748536823468675, 0.20451266082721842, 0.22622814695113844, 0.46030603398979064,
	]
	_check(scheduler.parameters != different_parameters, "params differ")
	var scheduler_diff := FSRSScheduler.new(different_parameters)
	scheduler_diff.enable_fuzzing = false
	var rescheduled := scheduler_diff.reschedule_card(card, review_logs)

	_check(card.card_id == rescheduled.card_id, "card_id equal")
	_check(card.state == rescheduled.state, "state equal")
	_check(card.step == rescheduled.step, "step equal")
	_check(card.stability != rescheduled.stability, "stability differs")
	_check(card.difficulty != rescheduled.difficulty, "difficulty differs")
	_check(card.last_review == rescheduled.last_review, "last_review equal")
	_check(card.due != rescheduled.due, "due differs")


func test_reschedule_card_different_desired_retention() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false
	var card := FSRSCard.new()

	var review_logs: Array = []
	for rating in TEST_RATINGS_1:
		var r := scheduler.review_card(card, rating, card.due)
		card = r.card
		review_logs.append(r.review_log)

	var different_retention := 0.8
	_check(scheduler.desired_retention != different_retention, "retention differs")
	var scheduler_diff := FSRSScheduler.new(FSRSScheduler.DEFAULT_PARAMETERS, different_retention)
	scheduler_diff.enable_fuzzing = false
	var rescheduled := scheduler_diff.reschedule_card(card, review_logs)

	_check(card.card_id == rescheduled.card_id, "card_id equal")
	_check(card.state == rescheduled.state, "state equal")
	_check(card.step == rescheduled.step, "step equal")
	_check(card.stability == rescheduled.stability, "stability equal")
	_check(card.difficulty == rescheduled.difficulty, "difficulty equal")
	_check(card.last_review == rescheduled.last_review, "last_review equal")
	_check(card.due < rescheduled.due, "due later (lower retention)")


func test_reschedule_card_different_learning_steps() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false
	var card := FSRSCard.new()

	var review_logs: Array = []
	for rating in TEST_RATINGS_1:
		var r := scheduler.review_card(card, rating, card.due)
		card = r.card
		review_logs.append(r.review_log)

	var different_steps: Array = []
	for i in range(review_logs.size()):
		different_steps.append(60.0)
	_check(scheduler.learning_steps != different_steps, "learning_steps differ")
	var scheduler_diff := FSRSScheduler.new()
	scheduler_diff.enable_fuzzing = false
	scheduler_diff.learning_steps = different_steps
	var rescheduled := scheduler_diff.reschedule_card(card, review_logs)

	_check(card.card_id == rescheduled.card_id, "card_id equal")
	_check(card.state != rescheduled.state, "state differs")
	_check(card.step != rescheduled.step, "step differs")
	_check(card.stability == rescheduled.stability, "stability equal")
	_check(card.difficulty == rescheduled.difficulty, "difficulty equal")
	_check(card.last_review == rescheduled.last_review, "last_review equal")
	_check(card.due > rescheduled.due, "due earlier (short learning steps)")


func test_reschedule_card_wrong_review_logs() -> void:
	var scheduler := FSRSScheduler.new()
	scheduler.enable_fuzzing = false
	var card := FSRSCard.new()

	var review_logs: Array = []
	for rating in TEST_RATINGS_1:
		var r := scheduler.review_card(card, rating, card.due)
		card = r.card
		review_logs.append(r.review_log)

	var different_card_id := 123
	_check(card.card_id != different_card_id, "card_id differs from 123")
	review_logs[0].card_id = different_card_id

	var result := scheduler.reschedule_card(card, review_logs)
	_check(result == null, "reschedule returns null on mismatched card_id")
