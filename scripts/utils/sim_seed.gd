class_name SimSeed
## One seed for the whole run.
##
## Every run is seeded and says so on its first line of output. Pass the
## printed number back to replay the same random stream:
##
##   godot --headless --path . --audio-driver Dummy --fixed-fps 60 \
##       res://scenes/main/headless_sim.tscn -- --seed=1234 --days=2
##
## The seed fixes the heuristic path only. Model output is not reproducible,
## and neither is frame timing unless the engine runs with --fixed-fps, so a
## replay that must match line for line needs both: heuristic brains and a
## fixed frame rate. EventBus._init() applies it, before any other autoload
## can draw a number.

## The seed in force. Random when none was passed, but always known.
static var value: int = 0
## True when the seed came from the command line rather than the dice.
static var explicit: bool = false

static var _applied: bool = false


static func apply() -> void:
	if _applied:
		return
	_applied = true
	var parsed := parse(OS.get_cmdline_user_args())
	explicit = parsed >= 0
	value = parsed if explicit else int(randi())
	seed(value)
	print("[seed] %d%s" % [value, "" if explicit else "  (replay with: -- --seed=%d)" % value])


static func parse(args: PackedStringArray) -> int:
	## The value of the last well-formed --seed=N in `args`, or -1 for none.
	## Negative, empty and non-numeric values are ignored rather than read
	## as zero: a typo must not silently pin the run to seed 0.
	var found := -1
	for arg in args:
		if not arg.begins_with("--seed="):
			continue
		var text := arg.trim_prefix("--seed=")
		if text.is_valid_int() and int(text) >= 0:
			found = int(text)
	return found
