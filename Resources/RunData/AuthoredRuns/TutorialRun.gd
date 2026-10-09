extends RunDefinition

func get_run_id() -> String:
	return "tutorial"

func get_display_name() -> String:
	return "tutorial"

# Heat still builds during the tutorial, but crossing thresholds does nothing.
func is_escalation_enabled() -> bool:
	return false

# Feed sections and the runner's route, in (cell, lane) waypoints.
# Feed 1 covers the yard and security hall. At the end of the hall the route
# turns down a service stair and the feed cuts to the service corridor, where
# the runner hugs the top wall to slip past cam_04's sweep.
func get_sections() -> Array[FacilitySection]:
	return [
		section("approach", -3.0, 17.0) \
			.label("LOADING YARD // SECURITY HALL") \
			.path([
				Vector2(-3.0, 3.6),
				Vector2(-0.8, 3.0),
				Vector2(2.2, 2.0),
				Vector2(16.6, 2.0),
				Vector2(16.6, 5.6),
			]) \
			.build(),

		section("interior", 17.0, 82.0) \
			.label("SERVICE CORRIDOR") \
			.path([
				Vector2(16.0, 2.0),
				Vector2(21.5, 2.0),
				Vector2(22.3, 0.4),
				Vector2(24.0, 0.4),
				Vector2(24.7, 2.0),
				Vector2(82.0, 2.0),
			]) \
			.build(),
	]

# Floorplan. Room boundaries line up with the doors the route passes
# through; walls get doorways automatically wherever the route crosses them.
func get_rooms() -> Array[FacilityRoom]:
	return [
		# --- Feed 1: approach ---
		room("perimeter", -3.0, 6.5) \
			.label("PERIMETER // LOADING YARD") \
			.exterior() \
			.lanes(-1.0, 5.0) \
			.prop(0.2, 1.6, 3.3, 4.6, "", &"van") \
			.prop(5.6, 6.4, -0.9, 0.9, "", &"guard_booth") \
			.build(),

		room("security_hall", 6.5, 17.0) \
			.label("SECURITY HALL") \
			.lanes(-0.5, 4.5) \
			.opening("top", 11.6, 12.4) \
			.opening("bottom", 16.2, 17.0) \
			.prop(7.6, 9.4, -0.5, 0.35, "", &"reception") \
			.prop(12.6, 13.4, 3.6, 4.5, "", &"lockers") \
			.build(),

		# Decorative: offices off the top of the hall, mostly off-screen.
		room("admin_wing", 10.4, 13.6) \
			.label("ADMIN") \
			.lanes(-4.0, -0.5) \
			.opening("bottom", 11.6, 12.4) \
			.build(),

		# The corner: the route leaves the hall down this stair.
		room("service_stair", 16.2, 17.0) \
			.label("") \
			.lanes(4.5, 7.5) \
			.opening("top", 16.2, 17.0) \
			.build(),

		# --- Feed 2: interior ---
		# Where the stair comes out, entering the corridor from the left.
		room("stair_landing", 15.4, 17.0) \
			.label("") \
			.lanes(1.45, 2.55) \
			.in_section("interior") \
			.build(),

		room("service_corridor", 17.0, 33.0) \
			.label("SERVICE CORRIDOR") \
			.lanes(-0.5, 4.5) \
			.opening("top", 22.0, 22.8) \
			.opening("bottom", 26.2, 27.0) \
			.prop(18.5, 19.5, 3.6, 4.5, "", &"carts") \
			.build(),

		# Decorative side spaces off the corridor.
		room("vent_access", 21.9, 22.9) \
			.label("") \
			.lanes(-3.0, -0.5) \
			.opening("bottom", 22.0, 22.8) \
			.build(),

		room("janitorial", 25.4, 28.0) \
			.label("JANITORIAL") \
			.lanes(4.5, 7.5) \
			.opening("top", 26.2, 27.0) \
			.build(),

		room("lab_access", 33.0, 40.5) \
			.label("LAB ACCESS") \
			.lanes(0.2, 3.8) \
			.prop(37.0, 39.5, 0.2, 0.75, "", &"decon_shower") \
			.prop(37.0, 39.5, 3.25, 3.8, "", &"decon_shower") \
			.build(),

		room("clean_lab", 40.5, 48.5) \
			.label("CLEANROOM // R&D") \
			.lanes(-0.8, 4.8) \
			.prop(42.9, 46.1, -0.8, 0.45, "FAB BAY") \
			.prop(42.9, 46.1, 3.55, 4.8, "COOLANT RACK") \
			.prop(46.0, 47.0, 1.45, 2.55, "", &"plinth") \
			.build(),

		room("exit_hall", 48.5, 59.0) \
			.label("EXIT HALL") \
			.lanes(-0.5, 4.5) \
			.opening("top", 51.6, 52.6) \
			.build(),

		room("security_office", 50.6, 54.0) \
			.label("SECURITY OFFICE") \
			.lanes(-4.0, -0.5) \
			.opening("bottom", 51.6, 52.6) \
			.build(),

		room("drone_bay", 59.0, 75.0) \
			.label("DRONE BAY") \
			.lanes(-0.8, 4.8) \
			.opening("top", 64.8, 66.2) \
			.opening("bottom", 68.8, 70.2) \
			.prop(60.0, 63.0, -0.8, -0.1, "", &"charging_rack") \
			.prop(60.0, 63.0, 4.1, 4.8, "", &"charging_rack") \
			.prop(73.0, 74.0, 1.45, 2.55, "", &"plinth") \
			.build(),

		room("extraction", 75.0, 82.0) \
			.label("EXTRACTION") \
			.exterior() \
			.lanes(-1.0, 5.0) \
			.build(),
	]

# Map-mode tuning: lanes are 90px apart on the facility map (54px on the old
# timeline strip), so side lanes sit further from the runner's path.
# - Vertical patrollers move at 0.25 cells/s (0.15 * 90/54) to keep their
#   original crossing timing, with longer sensor cones to cover the same lanes.
# - Side/wall cameras reach a little further.
func get_spawns() -> Array[Dictionary]:
	return [
		spawn(BASIC_CAMERA, 3.5) \
			.id("cam_00") \
			.lane(0) \
			.facing(-10) \
			.build(),

		spawn(BASIC_CAMERA, 4.5) \
			.id("cam_01") \
			.lane(2) \
			.build(),

		spawn(BASIC_DOOR, 6.5) \
			.lane(2) \
			.add_puzzle("sniff", 1) \
			.build(),

		spawn(PANNING_CAMERA, 11.5) \
			.id("cam_02") \
			.lane(3) \
			.vision(30.0, 1.25) \
			.add_ic_custom("reboot", {"reboot_time": 10.0}) \
			.build(),

		spawn(BASIC_DRONE, 14.5) \
			.id("drone_01") \
			.lane(3) \
			.add_ic_custom("reboot", {"reboot_time": 3.0}) \
			.move_speed(0.2) \
			.patrol([0.0, -2, 1, 0], [1.0, -2, 1, 0], [1.0, 0, 1, 0], [0.0, 0, 1, 0]) \
			.build(),

		spawn(BASIC_DISRUPTOR, 14.5) \
			.id("coolant_vent_01") \
			.lane(4) \
			.build(),
		
		# pre-lab gauntlet (38.5 - 59.5)
		# top-lane panning camera, dodgeable with timing
		spawn(PANNING_CAMERA, 20.5) \
			.id("cam_03") \
			.lane(0) \
			.vision(20.0, 1.0) \
			.detection_sweep([-1, 3], [180, 3]) \
			.add_ic_custom("reboot", {"reboot_time": 3.0}) \
			.build(),

		# bottom-lane panning camera, dodgeable with timing
		spawn(PANNING_CAMERA, 23.5) \
			.id("cam_04") \
			.lane(4) \
			.vision(20.0, 1.2) \
			.detection_sweep([1, 3.5], [180, 3.5]) \
			.add_ic_custom("reboot", {"reboot_time": 10.0}) \
			.build(),

		# long-distance patrol drone
		spawn(BASIC_DRONE, 25.0) \
			.id("drone_02") \
			.lane(1) \
			.add_ic_custom("reboot", {"reboot_time": 10.0}) \
			.patrol([0.0, 0, 3, 0], [6.0, 0, 3, 0]) \
			.build(),

		spawn(BASIC_CAMERA, 26.5) \
			.id("cam_05") \
			.lane(0) \
			.vision(20.0, 1.2) \
			.detection_sweep([-1, 3.5], [180, 3.5]) \
			.add_ic_custom("reboot", {"reboot_time": 15.0}) \
			.build(),

		spawn(PANNING_CAMERA, 29.5) \
			.id("cam_06") \
			.lane(4) \
			.vision(20.0, 1.2) \
			.detection_sweep([1, 3.5], [180, 3.5]) \
			.add_ic_custom("reboot", {"reboot_time": 3.0}) \
			.build(),

		# middle-lane front facing camera, can't be avoided without hacking
		spawn(BASIC_CAMERA, 35.5) \
			.id("cam_07") \
			.lane(2) \
			.vision(20.0, 1.0) \
			.add_ic_custom("reboot", {"reboot_time": 10.0}) \
			.add_ic_custom("bouncer", {"time_to_disconnect": 3.0}) \
			.build(),

		spawn(BASIC_DRONE, 31.0) \
			.id("drone_03") \
			.lane(3) \
			.vision(60.0, 0.65) \
			.patrol([0.0, 0, 3, 0], [-6, 0, 3, 0]) \
			.build(),

		spawn(BASIC_DISRUPTOR, 27.5) \
			.id("coolant_vent_00") \
			.lane(4) \
			.build(),

		spawn(BASIC_DISRUPTOR, 29.5) \
			.id("breaker_panel_02") \
			.lane(0) \
			.build(),

		spawn(BASIC_DISRUPTOR, 31.5) \
			.id("nano_fabricator_00") \
			.lane(4) \
			.build(),

		spawn(BASIC_DOOR, 40.5) \
			.id("lab_door") \
			.lane(2) \
			.add_puzzle_custom("sniff", {"difficulty": 1, "config": load("res://Resources/PuzzlePrefabs/null_spike_door_puzzle.tres")}) \
			.build(),

		spawn(BASIC_DISRUPTOR, 43.5) \
			.id("coolant_vent_02") \
			.lane(0) \
			.build(),

		spawn(BASIC_DISRUPTOR, 44.5) \
			.id("nano_fabricator_01") \
			.lane(0) \
			.build(),

		spawn(BASIC_DISRUPTOR, 45.5) \
			.id("coolant_vent_04") \
			.lane(0) \
			.build(),

		spawn(BASIC_DISRUPTOR, 43.5) \
			.id("coolant_vent_05") \
			.lane(4) \
			.build(),

		spawn(BASIC_DISRUPTOR, 44.5) \
			.id("nano_fabricator_02") \
			.lane(4) \
			.build(),

		spawn(BASIC_DISRUPTOR, 45.5) \
			.id("coolant_vent_06") \
			.lane(4) \
			.build(),

		spawn(BASIC_TERMINAL, 46.5) \
			.id("null_terminal") \
			.add_puzzle("decrypt", 0) \
			.build(),

		spawn(BASIC_DOOR, 48.5) \
			.id("lab_exit") \
			.lane(2) \
			.build(),

		spawn(BASIC_CAMERA, 55.5) \
			.id("cam_08") \
			.lane(0) \
			.facing(-10) \
			.build(),

		spawn(BASIC_CAMERA, 55.5) \
			.id("cam_09") \
			.lane(4) \
			.facing(10) \
			.build(),

		spawn(COMBAT_DRONE, 57.5) \
			.id("c_drone_01") \
			.lane(2) \
			.patrol([0.0, 0, 1, 0], [-9.0, 0, 1, 0]) \
			.add_puzzle_custom("sniff", {"difficulty": 1, "config": load("res://Resources/PuzzlePrefabs/killer_drone_puzzle.tres")}) \
			.add_ic_custom("faraday", {"max_runner_distance_cells": 2.0}) \
			.build(),

		spawn(BASIC_DISRUPTOR, 54.5) \
			.id("coolant_vent_07") \
			.lane(3) \
			.build(),
		
		# final gauntlet
		spawn(COMBAT_DRONE, 65.5) \
			.id("c_drone_02") \
			.lane(1) \
			.move_speed(0.25) \
			.vision(60.0, 0.8) \
			.patrol([0.0, -1, 3, 0], [0.0, 2, 3, 0]) \
			.add_ic_custom("faraday", {"max_runner_distance_cells": 3.0}) \
			.build(),

		spawn(COMBAT_DRONE, 67.5) \
			.id("c_drone_03") \
			.lane(2) \
			.move_speed(0.25) \
			.vision(60.0, 0.8) \
			.patrol([0.0, -1, 3, 0], [0.0, 2, 3, 0]) \
			.add_puzzle("sniff", 1) \
			.build(),

		spawn(BASIC_DISRUPTOR, 68.5) \
			.id("coolant_vent_08") \
			.lane(0) \
			.build(),

		spawn(COMBAT_DRONE, 69.5) \
			.id("c_drone_04") \
			.lane(3) \
			.move_speed(0.25) \
			.vision(60.0, 0.8) \
			.patrol([0.0, -2, .5, 0], [0.0, 0, .5, 0]) \
			.add_ic_custom("reboot", {"reboot_time": 3.0}) \
			.build(),

		spawn(BASIC_DISRUPTOR, 70.5) \
			.id("nano_fabricator_03") \
			.lane(4) \
			.build(),

		# final obstacle before door
		spawn(COMBAT_DRONE, 71.5) \
			.id("c_drone_05") \
			.lane(4) \
			.move_speed(0.25) \
			.vision(60.0, 0.8) \
			.patrol([0.0, -4, 3, 0], [0.0, 0, 3, 0]) \
			.add_puzzle("sniff", 1) \
			.build(),
		
		# horizontal patroller
		spawn(COMBAT_DRONE, 71.5) \
			.id("c_drone_06") \
			.lane(2) \
			.patrol([0.0, 0, 1, 0], [-3.0, 0, 1, 0]) \
			.add_ic_custom("reboot", {"reboot_time": 10.0}) \
			.build(),
		
		spawn(BASIC_TERMINAL, 73.5) \
			.id("override_terminal") \
			.build(),
	]
