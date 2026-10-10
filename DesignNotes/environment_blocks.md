# Environment Blocks

Working list of environments to paste together into missions. Each block lists
the props that sell the space (wireframes, mostly non-interactive), the
connected devices that would naturally live there (candidate signals), and an
optional set-piece hook. No mechanics here on purpose; this is a vocabulary.

## Fiction notes

- The player is not watching camera footage. The runner wears a **relay** that
  maps the surrounding network space and sends it back. The map is the relay's
  reconstruction of the area.
- **Section transitions = the relay mapping a new area.** The runner moves out of
  mapped space (around a corner, down a stair, into an elevator) and the relay
  rebuilds the picture of wherever they've arrived. Spaces that naturally break
  line-of-network (stairwells, elevators, ramps, airlocks, tunnels, thick walls)
  are the diegetic excuse for a transition.
- **Non-networked machinery can still appear** on the map (the relay infers it
  from power draw, RF noise, structure scans). Dumb props are fine.
- **Flavor-only signals:** small, low-key signals that need no action and don't
  clutter the player's view. Used to make a space feel inhabited (a vending
  machine's sales log, an aquarium's feeding schedule, a car alarm).

## Approach / exterior

**Loading Yard** (in the tutorial already)
- Props: box trucks, dock bays with roll-up doors, pallets, dumpsters, guard booth
- Devices: dock door controllers, gate arm, plate-reader camera, yard floodlights, autonomous forklift
- Hook: a delivery truck backs in; the runner moves in its shadow

**Parking Structure**
- Props: rows of cars, pillars, ramps, ticket booth, EV chargers
- Devices: motion-zoned lighting, barrier arms, plate readers, car alarms, chargers
- Hook: lights click on zone by zone just ahead of a patrol, so its path is readable from the lights. Ramps are natural transitions between levels.

**Rooftop**
- Props: HVAC units, water tank, antenna mast, skylights, helipad markings
- Devices: weather station, aviation beacon, comm dish, drone landing pad
- Hook: insertion from above; a delivery drone lands mid-route

**Service Alley / Utility Trench**
- Props: transformer box, conduit runs, manholes, steam grates, junk
- Devices: smart meters, transformer monitor, steam valve actuators, a cheap doorbell camera on the back door

**Public Plaza / Street Front**
- Props: planters, benches, fountain, transit turnstiles, kiosks
- Devices: digital billboards, vending machines, wifi kiosks, retractable bollards
- Hook: a hijacked billboard pulls everyone's attention, guards included

## Thresholds

**Lobby / Reception**
- Props: reception desk, turnstile bank, waiting seats, corporate sculpture, elevator doors
- Devices: turnstiles, visitor kiosk, badge printer, holographic receptionist AI, smart-glass doors
- Hook: the receptionist AI greets the runner by a name that isn't his

**Security Checkpoint**
- Props: guard booth, scanner arch, x-ray conveyor, bollards, holding cell
- Devices: body scanner, weapons detector, intercom, blast shutter
- Natural Sentinel killbox

**Airlock / Decon** (decon_shower model exists)
- Props: gowning bench, lockers, shower stall between two doors
- Devices: interlocked doors (one won't open until the other closes), pressure sensors, UV lamps
- Hook: runner stuck between the doors while something's coming

**Mantrap / Vault Antechamber**
- Props: short corridor, two heavy doors, weight-plate floor, camera dome
- Devices: weight sensor, time lock, biometric panel

## Connectors

**Service Corridor** (exists)
- Props: pipe runs, cable trays, carts, janitor closets
- Devices: cleaning bot, magnetic fire-door holders, emergency lighting, junction boxes

**Elevator / Stairwell** (purpose-built transition)
- Props: elevator car, shaft, call panel, stair landings
- Devices: elevator controller, in-car camera, floor indicator
- Hook: the ride itself as a short interstitial map of just the car while the relay maps the destination; the elevator stops at a floor nobody pressed

**Catwalk Over a Work Floor**
- Narrow grated path along one edge with the factory/warehouse spread out below
- Props: railings, grating, hanging lamps, crane rails
- Hook: the runner is above the threats rather than among them

**Skybridge**
- Glass walkway between towers, open space on both sides
- Devices: smart glass (tint/opaque), wind and occupancy sensors

**Freight Tunnel / Underground Line**
- Props: track bed, cargo pods, maintenance alcoves
- Devices: pod controllers, signal lights, track switches
- Hook: an automated cargo pod rolls through on schedule

## Work spaces

**Open-Plan Office**
- Props: desk clusters, meeting pods, printers, plants, coffee bar
- Devices: printers, conference displays, hot-desk sensors, smart lights, coffee machine, cleaning robot
- Hook: after hours, dark except for motion-zone pools of light

**Executive Suite**
- Props: big desk, private bar, aquarium, art on plinths, private elevator
- Devices: wall safe, voice assistant, smart aquarium, personal security drone
- Natural paydata spot

**Lab / Cleanroom** (exists) - Luxon home turf
- Props: benches, fume hoods, centrifuges, cryo freezers, specimen tanks
- Devices: fume-hood monitors, freezer alarms, autoclave, sample-handling robot arms

**Server Hall** - Celestial home turf
- Rack rows run along the lanes (aisles for free)
- Props: racks, cooling units, cable ladders, cage partitions
- Devices: rack management controllers, cooling units, fire suppression, cage locks
- Hook: fire-suppression dump with evacuation siren and countdown

**Factory Floor** - Ragnarok home turf
- Props: conveyors, robot arms, presses, hazard-striped forklift lanes
- Devices: line controllers, robot arms, crusher, andon status lights
- Hook: the line starts up and the arms swing on a rhythm

**Automated Warehouse**
- Props: tall rack blocks, pick stations, floor grid
- Devices: shuttle bots running the grid (patrollers with an obvious reason to move)

**Drone Bay / Hangar** (exists)
- Props: charging racks, maintenance cradles, parts bins
- Devices: chargers, launch controller, diagnostic terminal

**Clinic / Augment Ward** - Luxon
- Props: beds, curtain dividers, IV stands, nurse station
- Devices: infusion pumps, patient monitors, medication dispenser, auto-surgeon

**Control Room / Security Office**
- Props: video wall, console desks, coffee mugs, weapons locker
- Devices: video wall, PA system, lockdown console
- Hook: the security staff are watching their own feeds of the runner's area

**Trading Floor / Vault** - Kronos
- Props: ticker walls, terminal rows, vault door, deposit-box walls
- Devices: tickers, vault time lock, audit terminal

**Hackerspace / Squat** - Ember
- Props: junk workbenches, couches, floor mural (decal), 3D printers, scrap server cluster
- Devices: everything jury-rigged and badly named

## Facility states (applied on top of any block)

- **Active:** people, lights on, clutter in use
- **After hours:** dark, motion-zone lighting, cleaning bots out
- **Lockdown:** shutters down, red lighting, things sealed
- **Ghost / derelict:** automation still running routines for nobody (cafeteria
  serving trays to empty tables, cleaning bot polishing a cracked floor,
  receptionist AI greeting dust). Fits the "old AI husks" flavor.

## Design notes

- Most props should be dumb. If only a fraction of objects are signals, signals
  read as notable and rooms read as real places.
- Room shape carries mood: narrow corridors squeeze the lanes, wide halls open
  them. Vary width between blocks for pacing.
- Transitions want a diegetic network break (see Fiction notes).
