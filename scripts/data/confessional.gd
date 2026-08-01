class_name Confessional
extends RefCounted
## A single reality-TV style "talking head" confessional line from an agent
## (or the host), captured in reaction to a dramatic event.

var speaker: String = ""        # Agent name, or "" for host/narrator lines
var line: String = ""           # The first-person confessional quip
var kind: String = ""           # Event kind that triggered it (romance, tragedy, rivalry, host, ...)
var day: int = 0
var timestamp: String = ""
var color: Color = Color(0.85, 0.85, 0.9)  # Speaker color (for UI accent)
var is_host: bool = false       # True for host/narrator recap lines


func to_dict() -> Dictionary:
	return {
		"speaker": speaker,
		"line": line,
		"kind": kind,
		"day": day,
		"timestamp": timestamp,
		"color": [color.r, color.g, color.b],
		"is_host": is_host,
	}


static func from_dict(data: Dictionary) -> Confessional:
	var c := Confessional.new()
	c.speaker = data.get("speaker", "")
	c.line = data.get("line", "")
	c.kind = data.get("kind", "")
	c.day = int(data.get("day", 0))
	c.timestamp = data.get("timestamp", "")
	var col: Array = data.get("color", [0.85, 0.85, 0.9])
	c.color = Color(col[0], col[1], col[2])
	c.is_host = bool(data.get("is_host", false))
	return c
