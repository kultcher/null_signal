extends RunDefinition

# Straight corridor with one bay per IC added in the IC expansion pass:
# Tripwire, Siphon, Heartbeat, Tether, Shy. Each bay is set up so the IC
# matters, with plenty of space between them so they can be tried one at a time.

func get_run_id() -> String:
	return "ic_test"

func get_display_name() -> String:
	return "IC test corridor"

# Keep heat from spawning escalation signals so each IC can be judged on its own.
func is_escalation_enabled() -> bool:
	return false

func get_rooms() -> Array[FacilityRoom]:
	return [
		room("ic_test_corridor", -3.0, 42.0) \
			.label("IC TEST CORRIDOR") \
			.lanes(-0.5, 4.5) \
			.prop(3.0, 6.0, 3.9, 4.5, "BAY 1 // TRIPWIRE") \
			.prop(9.0, 12.0, 3.9, 4.5, "BAY 2 // SIPHON") \
			.prop(15.0, 18.0, 3.9, 4.5, "BAY 3 // HEARTBEAT") \
			.prop(21.0, 26.0, 3.9, 4.5, "BAY 4 // TETHER") \
			.prop(29.0, 32.0, 3.9, 4.5, "BAY 5 // SHY") \
			.build(),
	]

func get_spawns() -> Array[Dictionary]:
	return [
		# Bay 1 - Tripwire: camera dead ahead. KILL it and eat the tripwire
		# spike, or let it see you (or hustle through) and take camera heat.
		spawn(BASIC_CAMERA, 4.5) \
			.id("cam_trip") \
			.lane(2) \
			.add_ic("tripwire", 2) \
			.build(),

		# Bay 2 - Siphon: locked door, so you have to stay connected while
		# you work the SNIFF puzzle. Heat bleeds the whole time.
		spawn(BASIC_DOOR, 10.5) \
			.id("door_siphon") \
			.lane(2) \
			.add_puzzle("sniff", 1) \
			.add_ic("siphon", 2) \
			.build(),

		# Bay 3 - Heartbeat: camera on the path. KILL right after a pulse for
		# the full window; kill just before one and it comes straight back.
		spawn(BASIC_CAMERA, 16.5) \
			.id("cam_heart") \
			.lane(2) \
			.add_ic("heartbeat", 2) \
			.build(),

		# Bay 4 - Tether: the door holds your session while you SNIFF it, but
		# a panning camera covers the approach. Deal with the camera before
		# connecting to the door, or you can't touch it until the door is open
		# (disconnecting early costs heat at this tier).
		spawn(PANNING_CAMERA, 22.0) \
			.id("cam_tether_watch") \
			.lane(4) \
			.vision(20.0, 1.2) \
			.detection_sweep([1, 2.5], [180, 2.5]) \
			.build(),

		spawn(BASIC_DOOR, 24.5) \
			.id("door_tether") \
			.lane(2) \
			.add_puzzle("sniff", 1) \
			.add_ic("tether", 2) \
			.build(),

		# Bay 5 - Shy: camera with Reboot plus Shy. Scan it to learn the reboot
		# time, then act before the scan data scrubs itself.
		spawn(BASIC_CAMERA, 30.5) \
			.id("cam_shy") \
			.lane(2) \
			.add_ic_custom("reboot", {"reboot_time": 6.0}) \
			.add_ic("shy", 2) \
			.build(),

		spawn(BASIC_TERMINAL, 38.5) \
			.id("exit_terminal") \
			.lane(2) \
			.build(),
	]
