## fsrs.rating
## ------------
## Enum representing the four possible ratings when reviewing a card.
##
## Mirrors fsrs/rating.py (IntEnum: Again=1, Hard=2, Good=3, Easy=4).
class_name FSRSRating
extends RefCounted

enum {
	Again = 1,
	Hard = 2,
	Good = 3,
	Easy = 4,
}
