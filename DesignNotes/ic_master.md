- punish overcommitment
- forced wait windows
- shortened safe windows
- make interpretation harder
- muddy what is true
- tax attention
- fuzzy scans
- false readouts
- misleading subprocess names
- partial signal visibility
- gate entry to systems
- force prerequisites
- create routing or sequencing friction
- captcha / checksum barriers
- proximity restrictions
- linked systems that require earlier setup
- punish brute force
- punish impatience
- raise cost for wrong reads
- tripwires
- honeypots
- retaliatory heat spikes
- progress resets after obvious misuse
- windows or overlays block parts of the timeline or other useful information

### Tier 1:

!Reboot: Reboots a disabled signal after a delay.
- Player must wait to disable the threat.

!Faraday: Prevents a signal from interacted with until it is close to the runner.
- Player must wait to deal with the threat. More dangerous than reboot if there's a minigame attached.

!Bouncer: Force-disconnects a player after a short delay.
- Forces the player to execute commands quickly once connected.

!Fuzzy: Greatly delays scan progress.
- Requires tying up time or RAM to gain information. May force player to operate blind.

!Callback: Have to echo a somewhat complicated passphrase back to the terminal.
- Taxes time and attention, punishes carelessness.


Stickler: No shortcuts or aliases allowed. Player must manually type full commands, can't click to connect to signals, etc.
- Tests memory and accuracy, potentially creates time pressure. Potentially dangerous combo with Bouncer or Faraday.

Shy: After a short delay, re-hides scanned information.
- Forces player to remember a signal's setup or have to act immediately while it's still in mind.

Lag: Adds artificial input delay to everything you type into the terminal.
- Commands can be buffered, but forces the player to trust they got it right.

Spammer: Randomly opens popups all over the screen.

Failsafe: Signal presists for X seconds after being disabled.


### Tier 2:

Backdoor: Can only connect to signal by running ACCESS from another signal. (Maybe needs special command or flag? Possibly can chain through multiple signals?)
- Delays access, diverts attention.

Tripwire: Triggers heat spike if disabled.
- Punishes carelessness and bad scouting.

Trace: Starts a timer as soon as you connect; causes a massive heat spike if you don't disconnect before the time runs out. - (More dangerous bouncer)

Cloak: Signal is completely invisible (maybe a mild shimmer cue) until close enough to the runners.

False Flag: Always last IC layer. Gives the signal fake IC and lock data that clears on full scan.
- Makes a signal look much scarier than it is, tricking the player into dedicating time and resources.

Lockout: After running a command, locks all terminal commands for a brief period.
- Forces the player to choose their actions carefully. More relevant with subprocesses and properties.

Firewall: Bounces your connection and locks you out briefly, requiring you to remember and reconnect to access it.
- Tests task-switching attention and memory.

Degrade: Randomly artifacts characters in the terminal, including the command line. Maybe ramps up and forces a disconnect to reset to normal.
- Might be less relevant before subprocesses/properties require close terminal reading.

Flood: Floods terminal with noise making it harder to read

Leech: Ties up a portion of your RAM for a long duration, limiting the software you can run.

Spoof: Disguises a dangerous signal as a harmless one (or vice versa) until fully scanned.

Blind: No terminal feedback, including command prompt.

Solo/Exclusive: Ice cancels all other connections OR requires all other sessions be closed


### Tier 3:
Blackout: On connect, temporarily hides the entire signal timeline, forcing you to rely on memory and audio cues.

Jumpscare: On, connect temporarily fake-fast-forwards the timeline.

Monitor: checks on other nearby signals, causing heat gain if it detects tampering

Necromancer: Reboots nearby signals

Swap: linked to another signal, commands are sent to the other

Bloodhound: Something tracks your cursor, you have to play keepaway or get a heat spike.


### Global?:
Efficiency: punishes you for inactive sessions

__________
UNSORTED:

Feedback: Manually disconnecting from a terminal or abandoning a hack mid-puzzle triggers a heat spike. (Require explicit logoff sequence?)


Fork: Rapidly fills your RAM with junk processes that must be manually targeted and killed via program interface.

Glitch: The signal visually jumps between a real and fake position on the timeline.

Honeypot: Successfully hacking this signal triggers a trap/negative effect elsewhere on the board (e.g., locking a door or waking a drone).

Mirror Image: Spawns multiple decoy copies of a signal on the timeline that must be scanned to find the real one.


Throttle: Slows down the internal mechanics of a minigame (e.g., cipher keys arrive slower, grids refresh slower).


Tripwire: Triggers a negative effect (like an alert or heat spike) specifically when you attempt to scan the signal, punishing information-gathering.


UI Disruptors: Creates visual/interface interference, such as spawning fake popup windows that block your view, adding static, or flipping your controls.

Sync: Must connect to a terminal session for X seconds before your commands are accepted

Phalanx / Eclipse:
Behavior: Projects a "Faraday" shield backward up the timeline, protecting the two signals immediately behind it. You cannot target or scan the shielded signals until the Phalanx is broken.



Prey: Signal drifts around the timeline, have to keep mouseover to lock down
Quantum: As above, but teleports, have to click multiple times to interact

Matroyshka: Have to repeat the same hack sequence multiple times... migrating subprocess?

Invert: Timeline position is mirrored (signal appears behind player and triggers when reaches other side)

?Version Control: The signal requires you to input a specific command. However, every time you hack a Celestial node, the required syntax slightly changes (e.g., override_door -> ovr_door_v2 -> door_sys_v3). Taxes short-term memory and reading comprehension.

Vandal / Graffiti: Alters the text in your terminal window. The instructions for the minigames are suddenly written in leetspeak, upside-down, or replaced with anarchist slogans ([DECRYPT] becomes [D3STR0Y_TH3_ST4T3]). You have to decipher the UI to know what button to press.

Amnesia/Gaslight: Once you scan this signal, it slowly fades out of visibility on the timeline, becoming completely invisible just before it hits the interaction zone. You have to remember exactly where it is and time your hack based on a mental clock.

Conformity: screen goes grayscale, all signal icons appear the sams


Sleeper: linked signals, one or more disabled, wake up if linked signals detect runner

Funhouse: signal timeline lanes swap around (visual only). Can this be done with view cones and tooltips crossing lanes?
exclusive: closes all other windows when you connect OR forces you to close all other windows before you can connect


- IC type: Chain - linked signals that trigger each other?

Adaptive: Minigame difficulty scales up with each failed attempt or reconnection.

Daemon: Installs a persistent version of certain other IC effects, even after connection is broken.

Deflect: connecting to signal bounces you to another?


Tripwire: Can have variable triggers, linked to nastier IC as a primer

Ransom: ransomware type effect?

????Honeypot: the apparent best target is bait???

_______

NEWEST:
- Tether: Two linked signals, both have to be disabled within a window or they reboot
- Leash: Linked signals, only one can be inactive at a time - OR hacking a signal resets leashed signal to default state
- Siphon: While connected to this signal, others get buffed
- Chorus: IC only active if multiple connections
- Parasite: IC migrates to other signals when killed
- Mimic: Copies another signal's scan data
- Desync: State changes are not reflected on the timeline
- Repeater: Commands run on this signal are automnatically run on the next signal you connect to
- Inflation: All RAM costs increased by 1 while connected. Like a super leech.
- Audit: Recurring checksum
- Split: Connecting to this signal forces your terminal to split into two panes. Commands randomly go to one pane or the other. Output appears in the wrong pane. You're playing a "which terminal am I actually typing into" game while also trying to hack.???
- Shuffle: Tabs are obfuscated
- Palimpsest: Enhanced Shy: rewrites scan data with MISNINFORMATION
- Siren: Fakes a "runner damaged" event
- Crosstalk: Commands input into other sessions leak into this one
- Keepalive: Requires periodic keypress to maintain connection.
- PlayDead: Reboots when player disconnects.
- Tinnitus: Audio-only disruptor.
- Tar Pit: Extends the duration of any cleanup? Maybe forces active programs into cleanup?
- Dead Man's Switch: If connected when <trigger>, causes heat spike or other badness
- Symbiote: Hidden. "Replaces" a program in your toolbar, causing it to occasionally fail or fail on next use.
- Relay Feedback: Causes negative effect on the runner
- Proximity Mine: Subverts standard triggers, replacing with a proximity trigger.
- Redact: Partially Censors names of other IC
- Dyslexia: Rearranges letters. Maybe only in some words?
- Haunted cursor - Cursor jumps to a random position after each character
- Booster: Increases capabilities of thing (faster camera movement)
- Lockon: Causes detection to lock-on



Globals:
- Poltergeist: Special IC package that jumps around signals on the timeline.



Luxon IC: mutate, evolve
disruption on data? like you're stealing data and have to "egg carry" it?


### Sniff hooks

- false target signatures
- delayed clarity
- noisy grid state

### Decrypt hooks

- rekey
- noise injection
- linked keyspaces
- blocked autofill
- candidate obfuscation

### Fuzz hooks

- shrinking probe windows
- false positives
- instability after repeated failed pushes


# IC Expansion — New Ideas and Corp-Specific Variants

Your existing list is strong and well-organized. The design rules are sound — particularly "IC should create decisions, not just downtime" and the red flag about IC that removes play rather than redirecting it. I'm going to work within those principles.

I'll start with new general IC concepts, then get into corp-specific variants where existing IC types mutate based on who built them.

---

## New General IC Concepts

### Tether

**Domain:** Access / Timing

**Behavior:** While connected to this signal, you cannot connect to any other signal. You're locked in until you finish the hack or manually disconnect (which may trigger Feedback-type consequences).

**Why it works:** Forces commitment. Most of the game is about triage and switching between problems. Tether removes that freedom at a specific, critical moment. You have to *decide* whether to engage, knowing that everything else on the timeline will be unmanaged while you do. The decision point is *before* you connect, not during the hack. It transforms a routine action into a gamble about what else might happen while you're occupied.

**The interesting case:** Your runner is approaching a tethered signal and a new threat appears further up the timeline. Do you handle the tether now (safe, but you can't help with the incoming threat) or skip it and deal with the incoming threat first (but now the tether is closer and your window is tighter)?

---

### Cascade

**Domain:** Punishment / Access

**Behavior:** When this signal is disabled, it immediately activates or strengthens an adjacent signal. KILLing camera A wakes up drone B. Disabling lock A adds a second encryption layer to lock B. The act of solving one problem creates another.

**Why it works:** Turns the signal landscape into a chain of consequences. The player has to read the cascade *before* acting — "if I KILL this, what wakes up?" — which rewards scanning and planning while punishing the instinct to just clear obstacles as they appear. Different from Honeypot because the connection is visible (if you scan) and the logic is spatial/causal rather than deceptive.

**The interesting case:** A cascade chain of three or four signals where disabling each one activates the next. The player has to figure out the right *order* — or find a way to break the chain entirely by approaching from a different angle.

---

### Heartbeat

**Domain:** Timing

**Behavior:** The signal periodically "pings" its network. If the signal has been disabled or tampered with when a ping occurs, an alert triggers. But between pings, the signal can be safely disabled. The player has to time their hack to land *between* heartbeats, and their runner has to pass through during the window before the next ping detects the tampering.

**Why it works:** Creates a rhythmic timing puzzle layered on top of the existing hack. It's not enough to disable the signal — you have to disable it at the *right moment* and then execute within the safe window. Different from Reboot because the signal isn't recovering — it's being *checked on* by something external.

**The interesting case:** Multiple heartbeat signals with offset timing. The safe windows don't overlap. The runner has to stop, wait, move, stop, wait, move — threading through a rhythm that requires the operator to track multiple timers simultaneously.

---

### Quarantine

**Domain:** Access / Punishment

**Behavior:** When triggered (by detection, failed hack, or high heat), this IC seals off a section of the timeline. Signals in the quarantined zone become inaccessible — you can't connect to anything inside it. Your runner can still physically move through, but you're blind and powerless. They're on their own until they clear the quarantine zone.

**Why it works:** Temporarily strips the player's core ability — overwatch — and forces the runner to survive on whatever preparations the player made *before* the quarantine triggered. It's not a fail state; it's a consequence that changes the nature of play for a duration. The player watches, helpless, while their runner navigates by instinct and whatever doors the player pre-opened.

**The interesting case:** The player *knows* a quarantine zone is coming and has to pre-clear the path — unlocking doors, disabling cameras, creating a safe corridor that the runner can traverse without operator support. The actual quarantine section becomes a test of how well you prepared, not how well you react.

---

### Siphon

**Domain:** Timing / Punishment

**Behavior:** While you're connected to this signal, your heat *passively rises*. Not a spike — a slow, steady bleed. The longer you stay connected, the more heat you accumulate. Fast hackers barely notice it. Slow hackers find themselves in audit/alert territory before they finish.

**Why it works:** Puts time pressure on the hack itself without adding a hard timer. The player can take as long as they want — but "as long as they want" has an escalating cost. Creates a tension between speed and accuracy: rush the hack and risk mistakes, or take your time and risk heat. Different from Trace because there's no hard cutoff — just mounting consequences.

**The interesting case:** A siphon on a complex decrypt. The cipher is solvable, but it takes time. Every second you spend working the puzzle, heat bleeds up. Do you commit to solving it cleanly, or do you input partial solutions and brute-force the rest, accepting the risk of errors?

---

### Ghost Signal

**Domain:** Information / Timing

**Behavior:** A signal that appears on the timeline, behaves like a real obstacle, but doesn't actually exist. It's residual data — an echo of a system that's been decommissioned or relocated. Scanning it reveals it as a ghost (if you have time to scan). But if you don't scan and react to it as real — KILLing it, routing your runner around it — you've wasted resources and time on nothing.

**Why it works:** Taxes the player's information-gathering discipline. In a low-pressure moment, ghosts are free information: scan, identify, ignore. In a high-pressure moment when you're triaging multiple threats and don't have time to scan everything, ghosts become attention traps that waste your most precious resource. The decision is always: "Can I afford to scan this, or do I have to assume it's real?"

**The interesting case:** A dense section with multiple signals, some real, some ghosts. The player who scans everything is safe but slow. The player who acts on assumption is fast but might waste heat on phantoms — or worse, might assume a real threat is a ghost and let it hit their runner.

---

### Deadman

**Domain:** Punishment / Timing

**Behavior:** This signal is *currently suppressing* something else. A deadman camera is keeping a door unlocked. A deadman relay is keeping drones in standby. KILL the deadman signal and the thing it was suppressing *activates*. The counterintuitive move is to leave it alone — but it might still be an obstacle in other ways (blocking your runner's path, generating heat passively, etc.).

**Why it works:** Inverts the player's default instinct. The whole game trains you to disable obstacles. Deadman signals punish that instinct. The correct play might be to hack *around* the deadman without touching it, which requires different routing and different tools. It makes the player ask a question they don't usually ask: "What happens if I *don't* hack this?"

**The interesting case:** A deadman signal in a narrow corridor. Your runner can't get past without dealing with it. But KILLing it releases something worse. The player has to find a third option — maybe OPERATing it differently, maybe finding another route, maybe timing the KILL so precisely that the runner is past the released threat before it fully activates.

---

### Piggyback

**Domain:** Access / Information

**Behavior:** This signal can't be connected to directly. Instead, you have to connect to an *adjacent* signal first and then laterally move your connection to the target. You're piggybacking through a system that's networked to the one you actually want.

**Why it works:** Changes the player's relationship to the signal landscape. Normally, every signal is an independent problem. Piggyback forces you to see connections between signals and use one as a stepping stone to another. The "easy" camera you already passed might be the access point for the "impossible" server three signals ahead. It rewards players who pay attention to the whole timeline, not just the immediate threat.

**The interesting case:** The stepping-stone signal has its own IC. You have to hack through the intermediary's defenses *and then* pivot to the actual target — all while maintaining the connection chain and managing whatever other threats are on the timeline.

---

## Corp-Specific IC Variants

This is where things get flavorful. The same *concept* of IC should feel different depending on who built it. A Sentinel Reboot and a Luxon Reboot shouldn't just be the same mechanic with a different skin — they should reflect the corporation's philosophy and create different problems.

### Sentinel Variants

**Sentinel Reboot → "Failsafe Protocol"**
Standard Reboot, but when the signal reboots, it comes back at a *higher alert state*. The camera reboots with a wider arc. The drone reboots with a faster patrol. The door reboots with stronger encryption. You can disable it again, but it'll be harder, and when it reboots *again*, it'll be harder still. Sentinel's philosophy: every breach is a lesson, and the system learns from it.

**Sentinel Cascade → "Escalation Doctrine"**
When a signal is disabled, it doesn't just activate an adjacent signal — it upgrades the security *posture* of the entire local area. All nearby signals get slightly harder. IC gets faster. Patrol routes tighten. It's not one-to-one cause-and-effect; it's systemic escalation. This is Sentinel's layered defense philosophy made mechanical: every action you take degrades your overall position.

**Sentinel-specific: "Overwatch"**
A signal that doesn't block your runner directly but *monitors other signals*. If an overwatch signal detects that adjacent signals have been tampered with, it triggers a coordinated response — multiple alerts simultaneously. The overwatch itself is often well-protected (hardened IC, difficult position). The choice: do you spend resources taking out the overwatch first (reducing future risk but costing time and heat now), or do you try to slip through its monitored zone and hope you're clean enough not to trigger it?

---

### Luxon Variants

**Luxon Reboot → "Regeneration"**
The signal doesn't just come back — it comes back *different*. A camera that reboots might change its arc pattern. A lock that reboots might change its encryption type. A drone that reboots might change its patrol route. You can't predict what the rebooted signal will look like because Luxon's biotech-derived systems don't restore from a fixed template; they *regrow*. Everything you learned about that signal before the reboot is now potentially wrong.

**Luxon Fuzzy → "Mutagenic Scan"**
Scanning a Luxon signal doesn't just take longer — it gives you information that *changes*. You scan a camera and it reads as basic. You scan it again and now it reads as having ICE. A third scan shows different ICE. The signal's properties are genuinely shifting, or the signal is actively interfering with your scan, and you can't tell which. At some point you just have to commit to an action based on incomplete and contradictory information.

**Luxon-specific: "Symbiote"**
A secondary IC that *attaches* to your connection when you hack a Luxon signal. After you disconnect, the symbiote remains in your system — a persistent effect that mildly degrades your performance. Maybe your scans are slightly slower across the board, or your heat dissipation rate decreases, or your minigame timers are slightly shorter. Each symbiote stacks. Over the course of a Luxon run, you accumulate a growing burden of symbiotic IC that makes *everything* progressively harder. Not any single one is threatening — but the accumulation is.

---

### Kronos Variants

**Kronos Reboot → "Service Contract"**
The signal reboots, but on a *predictable, published schedule*. The reboot timer is visible and consistent. Kronos doesn't hide information — they standardize it. This makes Kronos Reboots less about surprise and more about scheduling. You know exactly how long you have. The question is whether that window fits into your larger timing plan.

**Kronos Honeypot → "Loss Leader"**
A signal that's *extremely easy* to hack. Suspiciously easy. No IC, no encryption, practically begging to be KILLed. Doing so gives you a small immediate benefit (reduced local heat, an unlocked shortcut) but triggers a *delayed* cost — an audit timer that starts ticking down somewhere you can't see. Kronos giveth, and then Kronos audits. The loss leader tests whether the player can resist a bargain that's too good to be true.

**Kronos-specific: "Invoice"**
When you trigger an alert on a Kronos system, the response isn't immediate. Instead, you receive an "invoice" — a visible timer that counts down to the consequence. The consequence is always the same (audit/lockdown of a section), but the timer gives you a window to *mitigate* it. Clear heat, disable the system that issued the invoice, or just rush your runner through the affected area before the lockdown hits. Kronos doesn't ambush you. Kronos sends you the bill, and the bill is always due.

---

### Ember Variants

**Ember Reboot → "Community Patch"**
The signal doesn't reboot on a timer — it reboots when a white-hat notices it's down and manually restores it. This means the reboot timing is *unpredictable*. Could be two seconds, could be twenty, depends on whether an active white-hat is in the area and paying attention. Sometimes a signal stays down forever because nobody noticed. Sometimes it's back before you've moved three feet.

**Ember Tripwire → "Snitch Wire"**
Triggers an alert not to a central security system but to the *Ember community*. Instead of heat, it spawns or alerts a white-hat hacker somewhere on the network. The consequence isn't mechanical escalation — it's a new adversary who's now looking for you. And unlike automated systems, they might follow you between sections, adapt to your tactics, and warn other white-hats about your approach.

**Ember-specific: "Freeware"**
A signal that's been hacked open by someone *before you*. The security is already bypassed — but whoever did it left their own modifications in place. The door is unlocked, but it's also been rigged to log everyone who passes through. The camera is down, but its data feed has been rerouted to someone else's terminal. Freeware signals are *gifts with strings attached*. Using them is free and fast, but you're creating a trail that someone else controls.

---

### Celestial Variants

**Celestial Reboot → "Archival Restore"**
When a signal reboots, it doesn't just come back — it *reverts the entire local state* to its last known good configuration. Doors you unlocked relock. Cameras you repositioned snap back. Routes you cleared close. It's not just one signal rebooting; it's the system restoring from backup. The scope is limited (local area, not the whole facility), but within that scope, it can undo *minutes* of careful work.

**Celestial Cascade → "Integrity Chain"**
Every signal in a Celestial facility is part of a verification chain. When you tamper with one signal, adjacent signals *check on it* — and if they detect the tampering, they tighten their own security. But if you disable the adjacent signals *first*, there's nothing to check, and the cascade doesn't propagate. The puzzle is figuring out the right order to disable a cluster of interconnected signals so that each one goes down before it can alert its neighbors.

**Celestial-specific: "Checksum Verification"**
Periodically, the entire facility runs a global integrity check. Every signal is briefly pinged. Any signal that's been tampered with, disabled, or altered is flagged. If the number of flagged signals exceeds a threshold, a facility-wide lockdown triggers. The player has to keep their *total footprint* below the threshold at any given time — which might mean allowing some disabled signals to reboot before disabling new ones. You're managing a *budget* of simultaneous intrusions, and the checksum is the audit.

---

### Ragnarok Variants

**Ragnarok Reboot → "Hard Reset"**
No timer, no nuance. When a Ragnarok signal goes down, a physical breaker trips and a human technician is dispatched to manually reset it. This takes a long time (longer than any other corp's reboot) but is *completely unstoppable*. You can't hack a guy with a wrench. The signal will come back, and when it does, it's fully restored with no degradation. Ragnarok reboots are rare but absolute.

**Ragnarok Tripwire → "Dead Switch"**
When triggered, activates a physical hazard — not a security response, but an *industrial* response. Steam vents, emergency doors, conveyor shutdowns, power surges. The facility itself convulses. It's not targeted; it's environmental. Everything in the affected zone gets hit, including things that might have been helping you (like a distraction you set up, or a path you cleared).

**Ragnarok-specific: "Analog Lock"**
A signal that *can't be hacked at all*. It's mechanical. No network connection, no digital interface, no IC because there's nothing to intrude *on*. Your runner has to deal with it physically — pick it, break it, find the key. During this time, you're doing pure overwatch with no ability to help with the obstacle itself. Your job is keeping everything else at bay while your runner does manual labor.

**Ragnarok-specific: "Furnace Cycle"**
An environmental hazard that operates on a fixed, mechanical timer — completely independent of the security system. Every X seconds, a section of the facility becomes lethal (extreme heat, crushing machinery, electrical discharge). It's not IC. It's not security. It's just the facility *doing its job*. The cycle is visible, predictable, and absolutely non-negotiable. Thread the window or die. Combined with other obstacles, it creates the Ragnarok signature: simple problems made lethal by environmental context.

---

<details>
<summary><strong>How IC Complexity Should Scale</strong></summary>

One thing your design document implies but doesn't state explicitly: IC types should be introduced in a **carefully controlled vocabulary expansion**, like learning a language.

**Early game:**
- Reboot, basic Tripwire, Captcha/Checksum, Fuzzy
- Single IC per signal
- Corp-agnostic versions (no unique variants yet)

**Mid game:**
- Honeypot, Faraday, Cascade, Heartbeat, Trace, Siphon
- IC starts appearing in *combinations* (Reboot + Fuzzy on the same signal)
- Corp-specific variants begin appearing (Sentinel reboots are now Failsafe Protocol, Luxon fuzzy is now Mutagenic)
- First Ghost Signals in non-husk environments

**Late game:**
- Quarantine, Tether, Deadman, Piggyback, Symbiote, Checksum Verification
- Complex IC combinations (Tethered signal with Siphon and Cascade)
- Corp-specific IC is fully differentiated
- White-hat hackers in Ember runs become sophisticated adversaries
- Husk runs introduce IC that doesn't fit *any* known category — truly alien countermeasures from AI-designed systems

The principle: **every new IC type should feel like a revelation, not a burden.** The player should encounter a new type and think "oh, *that's* what this does" — a moment of understanding that expands their model of the game. Not "oh great, another thing to memorize."

Each new IC type should make the player *better*, not just make the game harder. Learning Cascade teaches you to read signal relationships. Learning Heartbeat teaches you rhythmic timing. Learning Deadman teaches you that not every obstacle should be destroyed. The IC vocabulary is also a *skill* vocabulary — and by late game, the player should feel like a fundamentally different (and more capable) operator than they were at the start.

</details>