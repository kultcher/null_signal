# PuzzleComponent.gd
# Component for adding puzzles to a Signal

class_name PuzzleComponent extends Resource

enum Type { NONE, SNIFF, FUZZ, DECRYPT }

@export var puzzle_type: Type = Type.NONE
@export var difficulty: int = 1
@export var encryption_key: String = "" # For decryption puzzles
@export var puzzle_locked: bool = false
@export var puzzle_config: Resource

var base_difficulty: int = 0
var uses_escalation_difficulty: bool = true

var puzzle_dict = {
	Type.NONE: "Open",
	Type.SNIFF: "Unauthorized",
	Type.DECRYPT: "Encrypted",
	Type.FUZZ: "Vulnerable"
}

func _init():
	pass

func set_difficulty(value: int) -> void:
	base_difficulty = value
	difficulty = value
	uses_escalation_difficulty = true

func apply_escalation(escalation_level: int) -> void:
	if not uses_escalation_difficulty:
		return
	if base_difficulty == 0:
		return
	difficulty = base_difficulty + escalation_level
	ensure_puzzle_generated()

func set_custom_fixed() -> void:
	print("custom")
	uses_escalation_difficulty = false

func ensure_initial_lock_state():
	if puzzle_type != Type.NONE:
		puzzle_locked = true
	ensure_puzzle_generated()

func ensure_puzzle_generated() -> void:
	match puzzle_type:
		Type.FUZZ:
			if not puzzle_config is FuzzPuzzleConfig:
				puzzle_config = FuzzPuzzleConfig.new()
		Type.SNIFF:
			var sniff_config := get_sniff_config()
			if sniff_config == null:
				sniff_config = SniffPuzzleConfig.new()
				puzzle_config = sniff_config
			sniff_config.ensure_generated(difficulty)
		Type.DECRYPT:
			var decrypt_config := get_decrypt_config()
			if decrypt_config == null:
				decrypt_config = DecryptPuzzleConfig.new()
				puzzle_config = decrypt_config
			decrypt_config.ensure_generated(difficulty)
			encryption_key = str(decrypt_config.mapping_offset)

func get_sniff_config() -> SniffPuzzleConfig:
	return puzzle_config as SniffPuzzleConfig

func get_decrypt_config() -> DecryptPuzzleConfig:
	return puzzle_config as DecryptPuzzleConfig

func get_fuzz_config() -> FuzzPuzzleConfig:
	var fuzz := puzzle_config as FuzzPuzzleConfig
	return fuzz.for_difficulty(difficulty) if fuzz != null else null

func process_solve(active_sig: ActiveSignal):
	print("Puzzle Component: Puzzle Solved!")
	puzzle_locked = false
	if active_sig.instance_node:
		active_sig.instance_node.refresh_lock_status()

func is_locked() -> bool:
	return puzzle_type != Type.NONE and puzzle_locked

func get_desc():
	if puzzle_type == Type.NONE:
		return "OVERRIDDEN"
	elif !puzzle_locked:
		return "HACKED"
	return puzzle_dict[puzzle_type]
	
