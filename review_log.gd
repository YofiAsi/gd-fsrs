## fsrs.review_log
## ----------------
## Represents the log entry of a Card object that has been reviewed.
##
## Mirrors fsrs/review_log.py. `review_datetime` is stored as a UTC Unix
## timestamp (float seconds). `review_duration` is `int | None` in py-fsrs,
## so it is left untyped (Variant) here to faithfully hold `null`.
class_name FSRSReviewLog
extends RefCounted

var card_id: int
var rating: int
var review_datetime: float  ## UTC unix timestamp (seconds)
var review_duration ## int | null (milliseconds)


func _init(
	p_card_id: int,
	p_rating: int,
	p_review_datetime: float,
	p_review_duration = null,
) -> void:
	card_id = p_card_id
	rating = p_rating
	review_datetime = p_review_datetime
	review_duration = p_review_duration


func to_dict() -> Dictionary:
	return {
		"card_id": card_id,
		"rating": int(rating),
		"review_datetime": review_datetime,
		"review_duration": review_duration,
	}


static func from_dict(source_dict: Dictionary) -> FSRSReviewLog:
	return FSRSReviewLog.new(
		int(source_dict["card_id"]),
		int(source_dict["rating"]),
		float(source_dict["review_datetime"]),
		int(source_dict["review_duration"]) if source_dict["review_duration"] != null else null,
	)


func to_json(indent = null) -> String:
	return JSON.stringify(to_dict(), _indent_string(indent), true, true)


static func from_json(source_json: String) -> FSRSReviewLog:
	return from_dict(JSON.parse_string(source_json))


func equals(other) -> bool:
	if other == null or not (other is FSRSReviewLog):
		return false
	return (
		card_id == other.card_id
		and rating == other.rating
		and review_datetime == other.review_datetime
		and review_duration == other.review_duration
	)


func _to_string() -> String:
	return "FSRSReviewLog(%s)" % str(to_dict())


static func _indent_string(indent) -> String:
	if indent == null:
		return ""
	if indent is int:
		return " ".repeat(indent)
	return str(indent)
