# SignalData.gd
# Modular base signal class, add components for specific functionality

class_name SignalData extends Resource

enum Type { DOOR, CAMERA, TRAP, DRONE, GUARD, INFO, DISRUPTOR, TERMINAL, ESCALATION, MISC }
enum VisualState { HIDDEN, UNKNOWN, SPOOFED, REVEALED }

var identity_dict = {
	Type.DOOR: "Door | Mech",
	Type.CAMERA: "Camera | Mech",
	Type.DRONE: "Drone | Mech",
	Type.GUARD: "Guard | Bio",
	Type.DISRUPTOR: "Disruptor | Mech",
	Type.TERMINAL: "Terminal | Mech",
	Type.ESCALATION: "Escalation | IC",
 }

# IDENTIFIERS
@export var type: Type = Type.MISC
@export var lane: int = 2 # 0=Top, 4=Bottom
@export var system_id: String = "unknown"
@export var display_name: String = ""
@export var spoof_id: String = ""
@export var facing_deg: float = 180.0

# STATE
@export var visual_state: VisualState = VisualState.REVEALED
@export var clearance_level: int = 0
@export var visuals: SignalVisuals
@export var alternate_visuals: SignalVisuals
@export var use_alternate_visuals: bool = false
@export var door_locked: bool = true
# Wireframe drawn under the signal on the facility map (WireframeModels).
# Empty = inferred from system_id.
@export var map_model: StringName = &""

# COMPONENTS
@export var hackable: HackableComponent
@export var detection: DetectionComponent
@export var response: ResponseComponent
@export var puzzle: PuzzleComponent
@export var ic_modules: ICComponent
@export var mobility: MobilityComponent
@export var disruptor: DisruptorComponent
@export var escalation: EscalationComponent
