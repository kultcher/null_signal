extends RunDefinition

# NIGHT AUDIT // Kronos Industries, Records Annex 7
# Early-game job: pull one ledger off the archive server of a half-empty
# office tower. Kronos flavour: lots of cheap obstacles, almost no IC, guards
# on strict schedules. The building is a ghost run by its management AI
# (the "Concierge") as if it were still full.
#
# Relay maps (sections):
#   1. B2 parking       ramp in, cross the aisle, down the stairwell
#   2. 14F open plan    around the meeting pods and the break area
#   3. Records wing     narrow corridor, antechamber, archive (objective)
#   4. Freight elevator interstitial while the relay maps the dock
#   5. Loading dock     out through the roll-up door into the yard
#
# Rough first pass: layout and signal placement only. Not tuned.
# TODO (needs new mechanics):
#   - Flavor-only signals for the Concierge (car alarm logging "armed" with a
#     dead battery, charger billing a car for 1,400 days, the nightly
#     "Q3 SYNERGY REVIEW" booking, plant waterer on plastic plants).
#   - Motion-zone lighting in the parking level as a patrol tell.
#   - THE AUDIT: heat threshold in the records wing flips every display to a
#     running cost tally and starts shutters closing (extraction race).

func get_run_id() -> String:
	return "night_audit"

func get_display_name() -> String:
	return "Night Audit"

func get_sections() -> Array[FacilitySection]:
	return [
		# Down the ramp from the street, along the drive aisle, then through an
		# empty bay to the stairwell door at the bottom wall.
		section("parking", -1.0, 15.0) \
			.label("B2 // PARKING") \
			.path([
				Vector2(0.0, -2.6),
				Vector2(0.0, -0.4),
				Vector2(1.0, 2.2),
				Vector2(12.5, 2.2),
				Vector2(12.5, 5.6),
			]) \
			.build(),

		# Out of the stairwell, south of the meeting pods (squeezed against the
		# desks), back to the main aisle, north around the break area, and on to
		# the records door.
		section("office", 15.0, 41.0) \
			.label("14F // OPEN PLAN") \
			.path([
				Vector2(14.6, 2.0),
				Vector2(19.2, 2.0),
				Vector2(19.8, 3.4),
				Vector2(24.6, 3.4),
				Vector2(25.2, 2.0),
				Vector2(30.2, 2.0),
				Vector2(30.8, 0.6),
				Vector2(34.0, 0.6),
				Vector2(34.6, 2.0),
				Vector2(41.0, 2.0),
			]) \
			.build(),

		# Straight down the records corridor, through the antechamber, past the
		# archive terminal, then up into the freight lobby.
		section("records", 41.0, 56.0) \
			.label("RECORDS WING") \
			.path([
				Vector2(40.6, 2.0),
				Vector2(52.6, 2.0),
				Vector2(53.4, 1.0),
				Vector2(54.6, 1.0),
				Vector2(54.6, -2.0),
			]) \
			.build(),

		# Interstitial: just the freight car while the relay maps the dock.
		section("freight", 56.0, 58.0) \
			.label("FREIGHT ELEVATOR // DESCENDING") \
			.path([
				Vector2(56.6, 2.0),
				Vector2(57.3, 2.0),
			]) \
			.build(),

		# Out of the freight elevator, across the dock, through the roll-up door
		# and out of the yard.
		section("dock", 58.0, 74.0) \
			.label("LOADING DOCK") \
			.path([
				Vector2(59.4, -1.6),
				Vector2(59.4, 2.0),
				Vector2(74.0, 2.0),
			]) \
			.build(),
	]

func get_rooms() -> Array[FacilityRoom]:
	return [
		# --- Map 1: B2 parking ---
		room("ramp", -0.9, 0.9) \
			.label("RAMP") \
			.lanes(-3.0, -0.5) \
			.build(),

		# Top bank nose-in to the wall (empty bays have chargers); bottom row
		# parallel parked, with the car alarm signal in the gap at 6.0.
		room("parking_b2", -1.0, 13.4) \
			.label("LEVEL B2 // PARKING") \
			.lanes(-0.5, 4.5) \
			.place(&"barrier_arm", 0.0, -0.3) \
			.place(&"ticket_booth", -0.5, 1.0) \
			.row(&"car", 1.4, 10.8, 0.5, 19, 3, [3, 8, 9, 15]) \
			.place(&"ev_charger", 2.97, -0.3) \
			.place(&"ev_charger", 5.58, -0.3) \
			.place(&"ev_charger", 6.1, -0.3) \
			.place(&"ev_charger", 9.23, -0.3) \
			.row(&"car", 1.2, 10.8, 4.0, 9, 0, [4]) \
			.row(&"pillar", 2.0, 12.0, 1.75, 6) \
			.row(&"pillar", 2.0, 12.0, 3.35, 6) \
			.prop(11.6, 13.4, 3.0, 4.5, "STAIRS") \
			.build(),

		room("stairwell", 12.1, 12.9) \
			.label("") \
			.lanes(4.5, 7.5) \
			.place(&"stairs", 12.5, 5.6, 1) \
			.build(),

		# --- Map 2: 14F open plan ---
		room("stair_landing", 14.2, 15.0) \
			.label("") \
			.lanes(1.45, 2.55) \
			.in_section("office") \
			.build(),

		# Desks top and bottom; the route squeezes south of the glass meeting
		# pods, then swings north around the break-area island.
		room("open_plan", 15.0, 41.0) \
			.label("14F // KRONOS RECORDS DIV.") \
			.lanes(-0.5, 4.5) \
			.opening("top", 26.6, 27.4) \
			.row(&"desk_cluster", 15.8, 29.4, 0.05, 12, 0, [9]) \
			.prop(19.9, 22.0, 0.75, 2.95, "", &"meeting_pod") \
			.prop(22.2, 24.3, 0.75, 2.95, "", &"meeting_pod", 2) \
			.row(&"desk_cluster", 15.8, 18.4, 4.05, 3) \
			.row(&"desk_cluster", 20.0, 24.2, 4.1, 5) \
			.row(&"filing_cabinet", 27.4, 29.6, 4.25, 5) \
			.prop(31.0, 33.8, 1.45, 3.0, "BREAK AREA") \
			.place(&"coffee_bar", 31.8, 1.75) \
			.place(&"sofa", 33.0, 2.7, 2) \
			.place(&"vending_machine", 33.55, 1.75) \
			.place(&"water_cooler", 31.2, 2.7) \
			.row(&"desk_cluster", 30.6, 34.4, 4.05, 5) \
			.row(&"plant", 30.6, 34.4, -0.3, 4) \
			.row(&"desk_cluster", 35.4, 39.4, 0.05, 4) \
			.row(&"desk_cluster", 35.4, 39.4, 4.05, 4) \
			.prop(36.2, 38.6, 2.65, 3.45, "KRONOS // TIME IS MONEY") \
			.place(&"plant", 15.4, 0.9) \
			.place(&"plant", 25.0, 4.2) \
			.place(&"plant", 40.4, 0.4) \
			.place(&"plant", 40.4, 3.6) \
			.build(),

		room("conference_b", 25.4, 29.6) \
			.label("CONF B") \
			.lanes(-3.2, -0.5) \
			.opening("bottom", 26.6, 27.4) \
			.place(&"meeting_table", 27.5, -1.6) \
			.place(&"conference_display", 29.4, -1.6, 1) \
			.build(),

		# --- Map 3: records wing ---
		room("records_corridor", 41.0, 46.5) \
			.label("RECORDS WING") \
			.lanes(1.3, 2.7) \
			.opening("top", 42.8, 43.6) \
			.build(),

		room("copy_room", 42.0, 44.6) \
			.label("COPY RM") \
			.lanes(-0.9, 1.3) \
			.opening("bottom", 42.8, 43.6) \
			.place(&"printer", 42.5, -0.4) \
			.place(&"scanner_station", 43.8, -0.4) \
			.place(&"shredder", 44.3, 0.8) \
			.build(),

		room("antechamber", 46.5, 48.5) \
			.label("SECURE") \
			.lanes(0.4, 3.6) \
			.place(&"vault_door", 48.35, 1.0) \
			.build(),

		room("archive", 48.5, 56.0) \
			.label("ARCHIVE // COLD STORAGE") \
			.lanes(-0.5, 4.5) \
			.row(&"filing_stacks", 49.6, 54.4, 3.9, 4) \
			.prop(49.2, 52.6, -0.45, 0.95, "", &"cage") \
			.row(&"server_rack", 49.6, 52.2, 0.25, 7) \
			.place(&"filing_cabinet", 55.6, 3.0, 2) \
			.build(),

		room("freight_lobby", 53.8, 55.4) \
			.label("FREIGHT") \
			.lanes(-2.6, -0.5) \
			.place(&"elevator_car", 54.6, -1.6, 1) \
			.build(),

		# --- Map 4: inside the freight car ---
		room("freight_car", 56.2, 57.8) \
			.label("FREIGHT CAR 2") \
			.lanes(0.8, 3.2) \
			.place(&"pallet_stack", 57.45, 1.2) \
			.place(&"crate", 57.5, 2.9) \
			.place(&"carts", 56.9, 3.0) \
			.build(),

		# --- Map 5: loading dock ---
		room("freight_landing", 58.8, 60.0) \
			.label("") \
			.lanes(-2.6, -0.5) \
			.place(&"elevator_car", 59.4, -1.6, 1) \
			.build(),

		room("loading_dock", 58.0, 68.0) \
			.label("LOADING DOCK") \
			.lanes(-0.5, 4.5) \
			.opening("bottom", 61.0, 62.0) \
			.opening("bottom", 63.2, 64.2) \
			.opening("bottom", 65.4, 66.4) \
			.place(&"dock_leveler", 61.5, 4.0, 1) \
			.place(&"dock_leveler", 63.7, 4.0, 1) \
			.place(&"dock_leveler", 65.9, 4.0, 1) \
			.row(&"shelving_rack", 60.8, 66.8, -0.25, 4) \
			.row(&"pallet_stack", 60.6, 62.4, 0.6, 3) \
			.place(&"carts", 67.2, 3.4) \
			.row(&"pallet_stack", 66.7, 67.6, 0.7, 2) \
			.build(),

		room("dock_apron", 58.0, 68.0) \
			.label("") \
			.exterior() \
			.lanes(4.5, 9.0) \
			.place(&"box_truck", 61.5, 6.6, 3) \
			.place(&"box_truck", 65.9, 6.6, 3) \
			.build(),

		room("yard", 68.0, 74.0) \
			.label("YARD // EXIT") \
			.exterior() \
			.lanes(-1.0, 5.0) \
			.place(&"van", 69.8, 0.4, 2, "KRONOS COURIER") \
			.place(&"dumpster", 69.4, 4.1) \
			.place(&"dumpster", 70.0, 4.1) \
			.place(&"barrier_arm", 72.6, 1.2, 1) \
			.place(&"guard_booth", 73.4, 0.0) \
			.build(),
	]

func get_spawns() -> Array[Dictionary]:
	return [
		# --- Map 1: B2 parking ---
		# Plate reader watching the bottom of the ramp.
		spawn(BASIC_CAMERA, 1.2) \
			.id("plate_cam") \
			.lane(0) \
			.facing(170) \
			.vision(30.0, 1.0) \
			.build(),

		# Rent-a-cop on a fixed loop along the bottom of the aisle.
		spawn(BASIC_GUARD, 9.0) \
			.id("guard_b2") \
			.lane(3) \
			.patrol([0.0, 0, 2, 180], [-4.5, 0, 2, 0]) \
			.build(),

		# Distraction: a parked car's alarm, in the gap in the bottom row.
		spawn(BASIC_DISRUPTOR, 6.0) \
			.id("car_alarm_01") \
			.lane(4) \
			.build(),

		spawn(BASIC_DOOR, 12.5) \
			.id("stair_door") \
			.lane(4) \
			.build(),

		# --- Map 2: 14F open plan ---
		# Night cleaning bot doing laps of the south aisle.
		spawn(BASIC_DRONE, 17.0) \
			.id("cleaning_bot_01") \
			.lane(3) \
			.vision(50.0, 0.6) \
			.move_speed(0.1) \
			.patrol([0.0, 0, 1, 0], [7.0, 0, 1, 180]) \
			.build(),

		# Guard A: paces the aisle past CONF B on a strict schedule.
		spawn(BASIC_GUARD, 26.5) \
			.id("guard_14f_a") \
			.lane(1) \
			.patrol([0.0, 0, 2, 0], [3.0, 0, 2, 180]) \
			.build(),

		# Distraction for guard A.
		spawn(BASIC_DISRUPTOR, 26.0) \
			.id("printer_14f") \
			.lane(4) \
			.build(),

		spawn(BASIC_CAMERA, 28.5) \
			.id("cam_14f_01") \
			.lane(0) \
			.facing(150) \
			.vision(40.0, 1.5) \
			.detection_sweep([135, 3], [180, 3]) \
			.build(),

		# Guard B crosses the floor north-south right where the route rejoins.
		spawn(BASIC_GUARD, 34.0) \
			.id("guard_14f_b") \
			.lane(0) \
			.move_speed(0.25) \
			.patrol([0.0, 0, 2, 90], [0.0, 4, 2, 270]) \
			.build(),

		# Distraction for guard B: the break-area coffee machine.
		spawn(BASIC_DISRUPTOR, 32.5) \
			.id("coffee_14f") \
			.lane(2) \
			.build(),

		spawn(BASIC_CAMERA, 39.5) \
			.id("cam_14f_02") \
			.lane(4) \
			.facing(200) \
			.vision(30.0, 1.2) \
			.build(),

		spawn(BASIC_DOOR, 40.8) \
			.id("records_door") \
			.lane(2) \
			.add_puzzle("sniff", 1) \
			.build(),

		# --- Map 3: records wing ---
		# Looks straight back down the corridor: no way around it.
		spawn(BASIC_CAMERA, 45.8) \
			.id("cam_records") \
			.lane(2) \
			.vision(20.0, 2.0) \
			.build(),

		spawn(BASIC_CAMERA, 47.5) \
			.id("cam_antechamber") \
			.lane(1) \
			.facing(90) \
			.vision(60.0, 0.8) \
			.build(),

		spawn(BASIC_DOOR, 48.5) \
			.id("vault_cage") \
			.lane(2) \
			.add_ic("tripwire", 1) \
			.build(),

		# Objective.
		spawn(BASIC_TERMINAL, 51.4) \
			.id("archive_terminal") \
			.lane(3) \
			.add_puzzle("decrypt", 1) \
			.build(),

		spawn(BASIC_DOOR, 54.6) \
			.id("freight_call") \
			.lane(0) \
			.build(),

		# --- Map 5: loading dock ---
		spawn(BASIC_GUARD, 65.0) \
			.id("guard_dock") \
			.lane(3) \
			.patrol([0.0, 0, 3, 180], [-3.0, 0, 3, 0]) \
			.build(),

		spawn(BASIC_DISRUPTOR, 64.4) \
			.id("forklift_01") \
			.lane(1) \
			.model(&"forklift") \
			.build(),

		spawn(BASIC_DOOR, 68.0) \
			.id("dock_rollup") \
			.lane(2) \
			.build(),

		spawn(BASIC_CAMERA, 71.5) \
			.id("yard_cam") \
			.lane(0) \
			.facing(150) \
			.vision(30.0, 1.5) \
			.build(),
	]
