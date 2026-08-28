class_name SecretState
extends RefCounted
## One private truth belonging to one agent.
##
## A secret lives in two places at once: here (who knows, was it admitted,
## is it out) and as a protected memory on the holder with thread
## "secret_<id>" — which is what the RumorMill trust-gates, what
## get_secrets() finds, and what the producer's leak dilemma reads. The
## memory is the substance; this is the bookkeeping.

var agent_name: String = ""
var id: String = ""            # e.g. "job_hunt"; memory thread is "secret_" + id
var text: String = ""          # the truth, phrased mid-sentence ("is quietly interviewing elsewhere")
var created_day: int = 0
var known_by: PackedStringArray = []  # names that learned it (confide or rumour)
var admitted_on_camera: bool = false  # the player has seen the booth admission
var exposed: bool = false             # the office knows; it stops being a secret


func thread() -> String:
	return "secret_%s" % id


func is_hidden() -> bool:
	return not exposed


func to_dict() -> Dictionary:
	return {
		"agent_name": agent_name,
		"id": id,
		"text": text,
		"created_day": created_day,
		"known_by": Array(known_by),
		"admitted_on_camera": admitted_on_camera,
		"exposed": exposed,
	}


static func from_dict(data: Dictionary) -> SecretState:
	var secret := SecretState.new()
	secret.agent_name = str(data.get("agent_name", ""))
	secret.id = str(data.get("id", ""))
	secret.text = str(data.get("text", ""))
	secret.created_day = int(data.get("created_day", 0))
	for name in data.get("known_by", []):
		secret.known_by.append(str(name))
	secret.admitted_on_camera = bool(data.get("admitted_on_camera", false))
	secret.exposed = bool(data.get("exposed", false))
	return secret
