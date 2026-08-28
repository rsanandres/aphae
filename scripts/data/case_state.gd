class_name CaseState
extends RefCounted
## One open Mole case: who is doing it, what has happened, how it ended.
##
## The case's evidence is not stored here — it lives where all evidence
## lives, in agent memories threaded "secret_mole_<n>", spread by the
## RumorMill and spilled by the booth. This is only the scoreboard.

enum Status { OPEN, CAUGHT, MOLE_WON }

var case_number: int = 1
var mole_name: String = ""
var status: Status = Status.OPEN
var opened_day: int = 0
var incidents: int = 0
var last_incident_day: int = 0
var wrongful_votes: int = 0
var resolved_day: int = -1


func thread() -> String:
	return "secret_mole_%d" % case_number


func secret_id() -> String:
	return "mole_%d" % case_number


func is_open() -> bool:
	return status == Status.OPEN


func to_dict() -> Dictionary:
	return {
		"case_number": case_number,
		"mole_name": mole_name,
		"status": int(status),
		"opened_day": opened_day,
		"incidents": incidents,
		"last_incident_day": last_incident_day,
		"wrongful_votes": wrongful_votes,
		"resolved_day": resolved_day,
	}


static func from_dict(data: Dictionary) -> CaseState:
	var case := CaseState.new()
	case.case_number = int(data.get("case_number", 1))
	case.mole_name = str(data.get("mole_name", ""))
	case.status = int(data.get("status", Status.OPEN)) as Status
	case.opened_day = int(data.get("opened_day", 0))
	case.incidents = int(data.get("incidents", 0))
	case.last_incident_day = int(data.get("last_incident_day", 0))
	case.wrongful_votes = int(data.get("wrongful_votes", 0))
	case.resolved_day = int(data.get("resolved_day", -1))
	return case
