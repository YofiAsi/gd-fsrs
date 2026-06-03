class_name FSRSCard
extends RefCounted

var card_id: int
var state: int
var step  ## int | null
var stability  ## float | null
var difficulty  ## float | null
var due: float  ## UTC unix timestamp (seconds)
var last_review  ## float | null (UTC unix timestamp)


func _init(
	p_card_id = null,
	p_state: int = FSRSState.Learning,
	p_step = null,
	p_stability = null,
	p_difficulty = null,
	p_due = null,
	p_last_review = null,
) -> void:
	if p_card_id == null:
		# epoch milliseconds of when the card was created
		p_card_id = int(Time.get_unix_time_from_system() * 1000.0)
		# wait 1ms to prevent potential card_id collision on next Card creation
		OS.delay_msec(1)
	card_id = p_card_id

	state = p_state

	if state == FSRSState.Learning and p_step == null:
		p_step = 0
	step = p_step

	stability = p_stability
	difficulty = p_difficulty

	if p_due == null:
		p_due = Time.get_unix_time_from_system()
	due = p_due

	last_review = p_last_review


## Shallow copy, equivalent to Python's copy.copy(card).
func clone() -> FSRSCard:
	return FSRSCard.new(card_id, state, step, stability, difficulty, due, last_review)


func to_dict() -> Dictionary:
	return {
		"card_id": card_id,
		"state": state,
		"step": step,
		"stability": stability,
		"difficulty": difficulty,
		"due": due,
		"last_review": last_review,
	}


static func from_dict(source_dict: Dictionary) -> FSRSCard:
	var src_stability = source_dict["stability"]
	var src_difficulty = source_dict["difficulty"]
	var src_last_review = source_dict["last_review"]
	return FSRSCard.new(
		int(source_dict["card_id"]),
		int(source_dict["state"]),
		int(source_dict["step"]) if source_dict["step"] != null else null,
		float(src_stability) if src_stability != null else null,
		float(src_difficulty) if src_difficulty != null else null,
		float(source_dict["due"]),
		float(src_last_review) if src_last_review != null else null,
	)


func to_json(indent = null) -> String:
	# full_precision=true so float fields (due, stability, difficulty) round-trip exactly.
	return JSON.stringify(to_dict(), _indent_string(indent), true, true)


static func from_json(source_json: String) -> FSRSCard:
	return from_dict(JSON.parse_string(source_json))


func equals(other) -> bool:
	if other == null or not (other is FSRSCard):
		return false
	return (
		card_id == other.card_id
		and state == other.state
		and step == other.step
		and stability == other.stability
		and difficulty == other.difficulty
		and due == other.due
		and last_review == other.last_review
	)


func _to_string() -> String:
	return "FSRSCard(%s)" % str(to_dict())


static func _indent_string(indent) -> String:
	# Mirrors json.dumps(indent=...): an int means that many spaces.
	if indent == null:
		return ""
	if indent is int:
		return " ".repeat(indent)
	return str(indent)
