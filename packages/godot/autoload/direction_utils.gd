extends Node
## DirectionUtils — Shared 8-direction vector helpers.
## Avoid duplicating _vector_to_direction across enemy, companion, and animators.

const DIRECTIONS := [
	"south", "south-west", "west", "north-west",
	"north", "north-east", "east", "south-east"
]

## Convert a movement vector (non-zero) to an 8-direction name.
## Returns last direction if the vector is near-zero.
static func vector_to_direction(vec: Vector2, last_dir: String = "south") -> String:
	if vec.length() < 0.1:
		return last_dir
	var deg := fmod(rad_to_deg(vec.angle()) + 360.0, 360.0)
	if deg < 22.5 or deg >= 337.5:
		return "east"
	elif deg < 67.5:
		return "south-east"
	elif deg < 112.5:
		return "south"
	elif deg < 157.5:
		return "south-west"
	elif deg < 202.5:
		return "west"
	elif deg < 247.5:
		return "north-west"
	elif deg < 292.5:
		return "north"
	else:
		return "north-east"
