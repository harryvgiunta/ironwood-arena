# Performance

The frontier, the arena and the delve all run on one frame budget: sixty
physics ticks a second, with the host's network clock, every mob's brain and
every ranger's animation sampled on that same tick. This file records how the
budget is measured, what it cost, and what was changed to bring it down.

## The suite

`tests/perf_suite.gd` is the benchmark. It runs the real `main.tscn` headless
under `--fixed-fps 60`, so every iteration simulates exactly one sixtieth of a
second and the wall-clock cost of that iteration is the frame's real price.
Costs are therefore comparable across runs and additive across scopes.

```
& $Godot --headless --path . --fixed-fps 60 \
    --script res://tests/perf_suite.gd -- --mode=crowd --mobs=100
```

| Mode | What it measures |
| --- | --- |
| `baseline` | The shipped frontier, idle: the control. |
| `spawn` | `--mobs` devils added in one frame, then the frames that follow. |
| `crowd` | `--mobs` devils packed around an invulnerable ranger and fighting. |
| `net` | The host replication path over that crowd: snapshot building, datagram packing, lag history. |
| `all` | All four in one process. |

Flags: `--mobs=N`, `--seconds=S`, `--budget=MS` (report PASS/FAIL against a
frame budget).

Attribution knobs, for finding where a cost actually lives:

| Flag | What it switches off |
| --- | --- |
| `--isolated=1` | Mobs stop colliding with each other. |
| `--ghost=1` | Mobs collide with nothing at all. |
| `--stub=1` | The added bodies exist but run no AI. |
| `--freezeall=1` | Every `AnimationPlayer` in the scene stops writing tracks. |
| `--novisual=1` | The added mobs' rigs stop drawing and animating. |
| `--noshape=1` | The added mobs lose their collision shape. |
| `--noshadow=1`, `--shadowdist=M` | The sun's shadow pass, or its range. |
| `--msaa=N` | The viewport's anti-aliasing level. |
| `--nomobs=1` | Every frontier mob is freed: the world's own frame, which is the floor. |
| `--noscopes=1` | The frame clock only. A begin/end pair per mob per frame is not free, and the headline numbers are taken this way. |
| `--legacy=1` | Runs against a tree from before this work, for an A/B. |

**Two modes, used for different things.** Scopes *on* for attribution — every
table in this file came from a scoped run. Scopes *off* (`--noscopes=1`) for
the headline frame times, because the profiler itself costs about **0.11 ms,
5.6% of a frontier frame**, mostly from the per-mob scopes. Mixing the two
overstates the game.

`--headless` uses a dummy renderer, which is exactly what the CPU half of the
frame is; drop it to include rendering. Compare like with like: the draw-call
and primitive counters only mean anything with a device attached.

## The profiler

`scripts/perf_probe.gd` is a frame-accurate scope profiler. Godot's editor
profiler needs the editor running, cannot be scripted headless, and reports
samples rather than "what one hundred simultaneous mobs cost in a second", so
the hot entry points call `Perf.begin(name)` / `Perf.end()` and every call of
that name folds into one bucket. Scopes nest and report both inclusive time and
own time.

Reported scopes:

| Scope | What it wraps |
| --- | --- |
| `main.physics`, `main.process` | `main.gd`'s physics and idle ticks. |
| `player.slide`, `player.cover`, `player.combat`, `player.loot` | The parts of the player's tick: the body step, cover, combat, and the loot and footfall pass. |
| `rig` | The ranger rig's animation sampling. |
| `mob.ai`, `legacy.ai`, `clone.ai` | One tick of each mob family's brain. |
| `mob.senses`, `mob.state`, `mob.separate`, `mob.drive`, `mob.slide`, `mob.steer`, `mob.visual` | The parts of that tick: sight, the state machine, spacing, steering, the ground step and presentation. |
| `mob.anim` | A mob's presentation sampler. |
| `net.host`, `net.build`, `net.pack`, `net.seats`, `net.lag` | The host's replication work. |
| `spawn.mob`, `spawn.visual`, `spawn.instantiate`, `spawn.materials` | The cost of adding one monster. |
| `world.build` | The world's construction. |

A scope's cost when the profiler is off is a single static-var read.

## What it cost before

Measured on a Ryzen 9 9950X, 75 mobs in the shipped frontier (before any of the
work below):

| Scenario | Frame | Notes |
| --- | --- | --- |
| Headless, frontier idle | 9.14 ms | `move_and_slide` for every mob was 35% of it. |
| Headless, 175 mobs fighting | 36.13 ms | 27 fps. |
| Windowed (GTX 1080), frontier idle | 19.14 ms | 52 fps, 3490 draw calls, 1.30 M primitives. |
| Adding 30 monsters in one frame | 40.7 ms | One frame. The frames after it never recovered. |
| Host upload with 133 mobs in view | 33.8 KB per send | 507 KB/s at the mob send rate. |

The finding that drove everything else: **a `CharacterBody3D` step costs about
90 µs per mob per frame on this world**, and a mob spent it whether it was
chasing a ranger or standing at its home. Two thirds of a frontier frame was
bodies asking the physics server to slide them a centimetre across the ground.

## What changed

Every change below was measured with the suite before and after.

### Mobs walk on the world instead of through the physics server

`scripts/mob_ground.gd`. The terrain is already an analytic height field
(`RangeWorld.terrain_height`) and the props are marked in a square-metre
navigation grid built while the world is built (`RangeWorld.is_blocked`), so a
mob's next step is a few array reads: **1.6 µs instead of 90 µs**, fifty times
cheaper. Mobs keep their `CollisionShape3D` on the hit layer, so blades, arrows
and spells still find them; they simply never ask the physics server to move
them. The trade is deliberate: a mob no longer slides along a wall at a grazing
angle, so it stops and tries the other axis, and it cannot be pushed by a body
heavier than itself — spacing is handled by the mob's own neighbour pass
instead.

A body that is already inside a marked cell is let out rather than walled in, so
nothing can be trapped by its own spawn, and an authored placement that lands in
an obstacle is nudged onto the nearest open ground.

### Mobs think on a stride

`scripts/mob_lod.gd`. Sight, spacing, the state machine and the ground step are
per-tick costs, and none of them need sixty hertz. A mob that is inside its
swing window — winding up, striking or recovering, or ready to swing and
already in reach — thinks every second tick (30 Hz). Everything else thinks
every fourth tick inside 22 m (15 Hz), every twelfth out to 55 m (5 Hz), and
every forty-eighth beyond (2 Hz). A decimated tick scales `delta`, so speeds, cooldowns and state timers
stay in real time.

**Movement is not decimated, and it has its own clock.** A decimated tick
carries two deltas: the accumulated one for timers, state clocks and cooldowns,
and the real frame for motion. Moving by the accumulated delta is what used to
make a coarse think rate stutter — a mid-range body travelled 41 cm every
eighth frame and stood still in between, and after the first attempt at this
it travelled 56 cm every eighth frame because the motion step inherited the
scaled delta. Both are gone: measured over ninety frames a body in the middle
tier now advances **7 cm on every single frame**.

On the frames between decisions a body keeps travelling toward the velocity it
last chose. A body with nothing to do — an idle monster at its home — does not
even take that step.

The distinction inside the stride matters too: a hundred devils standing in a
ring around one ranger are a hundred orbits, not a hundred fights, and only the
ones actually swinging get the fine rate.

Spacing is a soft constraint on top of that: it is re-measured one frame in six
and the result reused, staggered per mob so a hundred bodies do not all measure
on the same frame.

### A mob no longer asks the physics server for anything

Its body walks on the analytic ground, so its `collision_mask` was only ever
asking to be paired with every other mob and with the ranger in the broadphase:
seventy-five bodies in a room made a couple of thousand pairs that nothing
resolved. The mask is zero now — arrows and the ranger still find the body,
because pairing is decided by the *querying* body's mask and the mob keeps its
layer. Dense scenes drop about three percent; the frontier is unchanged
because its bodies are spread out.

### Rig animation is culled by the camera

Being in range and being *seen* are different questions. A monster within 45 m
owns its rig, but if the viewer's frustum does not contain it the clip stops
advancing and the body stops drawing — a freeze, not a release, so turning the
camera back does not rebuild a mesh. Nineteen of a hundred mobs in a ring are
in view at any moment, and that is worth about six percent of the dense case.

It only applies where this peer's camera is the only viewer — offline, or on a
client, whose camera is the one drawing the replicas. A host with remote peers
cannot know what they can see. Ranger clones are exempt outright: the bow draw
they time their release against lives in their rig, so a clone keeps animating
even when the camera has left it (the suite caught exactly that).

### Bodies nobody can see are not ticked

A mob's own tick costs it about six microseconds a frame before it decides
there is nothing to do: the distance test, the stride, the presentation pass.
Doing that seventy-five times a second to learn that nothing is happening is
the definition of waste, so the scene answers the question once for all of
them — four times a second, because a ranger closing at a sprint has more than
a second of margin against a threshold twelve metres beyond the rig-release
range — and each body reads one boolean at the top of its tick.

In the shipped frontier that skips **38 of 75 bodies entirely**. A culled body
keeps its node, its collision shape and its snapshot slot; it just stops
thinking, moving and presenting until a ranger is within seventy metres again.
Corpses are never culled, so they still fall and hold.

### The rigs are culled and slowed with distance

Past 45 m a mob's body stops drawing and its clip stops writing bone tracks.
Inside that range the sampler runs at **thirty hertz** rather than sixty: the
frames between skip it, so the clip advances the same time over a longer gap
and the skeleton is only touched when it actually moves. Thirty-hertz character
animation is the standard trade and it measures at 5% of a frontier frame — the
faster near tier that used to exist was deleted once that was measurable rather
than assumed to be below noise.

### The world's bodies are indexed once per frame

`scripts/mob_space.gd`. Every mob's spacing pass used to scan the whole
`wild_mobs` group — with 175 bodies that is thirty thousand distance tests and a
fresh array per mob per frame, four milliseconds of the frame. The same pass
against a square-metre bucket grid reads the nine cells around the body.

### The first blow of a session no longer stalls

Two things were built lazily and paid for in the middle of a fight: the blood
atlas (procedural, once) and the garment measurement of every species
(~17 ms each). Both are now built while the world loads — `main._warm_mob_blood`
touches `BloodFx.soak_material(0)` and measures one body per structure — which
costs **0.26 s of load** and removes the first-contact stutter: the worst frame
in a hundred-mob brawl went from **154 ms to 38 ms**, and the first landed blow
from **135 ms to 28 ms**.

### A distant body has no rig at all

A skinned body costs about **fourteen microseconds a frame simply by
existing** — a physics body, a scene node, a render instance and a skeleton —
and freezing its clip does not remove any of that. So past **58 m** a mob's
presentation subtree is *freed*, not frozen, and rebuilt when it comes back
inside **45 m**. The gap between those two numbers is hysteresis: a body pacing
the boundary must not build and free a rig every second.

The rebuilt rig starts at the top of its idle clip on the frame the ranger
comes back, which is the one visible cost of the trade and it happens at the
edge of the treeline. Replicas on a client run the same culling — they own the
only copy of a mob a client draws, so they get the same saving.

`mob_motion_regression` pins the motion/time split directly: every frame a walking body moves, and evenly. `devil_mobs_regression` and `forest_mobs_regression` pin both halves of the rig contract: a body in
view has its imported visual, a body past the release range has none, and a
released body that comes back rebuilds it and is playing a clip.

### Blood on a body no longer costs a frame

Measuring a rig to lay blood on it — every visible skinned vertex binned into
its dominant bone, then into 288 radial cells — allocated two small arrays for
every vertex and re-extracted every mesh surface for every body. The first
blow on each devil therefore cost **20-37 ms inside the hit**, and a room of
them stalled on every new attacker. Three changes:

- the per-vertex array pair became scalars, which is most of the cost;
- the rig sample is capped at eight thousand vertices, still far more than the
  288 cells a profile can hold;
- extracted surface arrays are cached per mesh, and the measurement itself is
  shared by **structure** rather than by instance — every devil of a species
  has the same garment, so it is measured once and the copy handed out is
  rebound to the caller's own skeleton.

The first bleed of each species still pays for its own measurement; every body
after it does not.

### The status block runs at thirty hertz

`hud.update_status` rewrites six formatted strings and three meters every
frame — 0.11 ms, more than five percent of the frontier — to show numbers a
player reads at human speed. It now runs every other frame (`hud.status` 0.109
→ 0.058 ms). The reticle, the world-space prompts and the camera stay per
frame.

### The ranger's own tick stopped rebuilding its pose for nothing

`main.physics` is the largest single scope in a frontier frame, and its largest
part was two of the rig's setters: `set_roll` and `set_step` rebuild the whole
pose every frame to be told "not rolling, not stepping". They now return early
when the state has not changed — the animation clock refreshes the pose anyway —
which is **0.17 ms a frame**, nearly ten percent of the frontier, for a guard on
two ifs.

### Monsters are cheaper to add

Tuned materials are shared per species instead of duplicated per body (a quarter
of the cost of adding a monster), the delve warms each imported species at load
so the first wave does not pay a third of a second for resource creation, and
the delve's wave budget adds at most three bodies per frame instead of however
many entries fell due in one tick.

### Mob snapshots are fifteen floats

`scripts/mob_wire.gd`. A mob used to travel as a nine-key dictionary: 244
encoded bytes each, 32 KB per send for the mobs in view, half a megabyte a
second of upstream — past what a residential connection carries, after which
the host's queue backs up and ENet starts dropping the snapshots that own the
smoothness. The same body packs into fifteen floats: 68 bytes, a third of the
traffic, one allocation instead of a dictionary and nine values.

`NetLimits.size` counts a packed float array arithmetically instead of encoding
it first, which halves the work of sizing a wave.

### Shadows reach sixty metres

The sun's shadow range was a hundred and ten metres, which spent a fifth of the
frame's draw calls on shadow-pass geometry nobody can pick out past the
treeline. Sixty still covers every weapon's useful range and the whole town
square. `world_style.gd` authors this per region
(`sun_shadow_distance`).

## Multiplayer, measured

`--net-diag` prints one line a second on both peers. For mob replication it now
carries `mobs`, `starved` (replicas the render buffer had to dead-reckon that
second, i.e. the snapshot stream ran dry) and `restarts` (bodies that had to be
snapped rather than interpolated). Run a host and a client and read the client:

```
& $Godot --headless --path . res://main.tscn -- --world-host --world-port 7831 --net-diag
& $Godot --headless --path . res://main.tscn -- --world-join 127.0.0.1 --world-port 7831 --net-diag --net-jitter 40
```

Measured over twenty-two seconds with all seventy-five frontier mobs
replicating:

| Link | starved mob-frames | teleport restarts | seat corrections |
| --- | --- | --- | --- |
| 40 ms jitter | **0** | **0** | 0 |
| 120 ms lag + 80 ms jitter | **0** | **0** | 1 |

No mob was ever dead-reckoned at four times a bad connection's jitter, which is
what "jittery multiplayer" looked like before: 507 KB/s of mob upload pushed the
host's queue past what a home connection carries, and every starved replica
snapped. The upload is now 152 KB/s and the buffer never empties.

## What it costs now

Medians of three runs; "before" is the same suite against the same scene at
`main`'s commit. Frame figures move by about eight percent between runs on this
machine, so treat the last digit as noise; the idle frontier has measured
between 2.00 and 2.50 ms across runs.

| Scenario | Before | After | Change |
| --- | --- | --- | --- |
| Headless, frontier idle | 9.14 ms | 1.75 ms | −81% |
| Headless, 175 mobs fighting | 36.13 ms | 6.50 ms | −82% |
| Windowed (GTX 1080), frontier idle | 19.14 ms | 6.08 ms | −68% |
| Draw calls | 3490 | 1940 | −44% |
| Primitives | 1.30 M | 0.87 M | −33% |
| Adding one monster | 1.36 ms | ~1.1 ms | −20% |
| The first blow of a session | 135 ms | 28 ms | −79% |
| The first blow after that | 20-37 ms | ~3 ms | −90% |
| Worst frame, 175 mobs fighting | 154 ms | 38 ms | −75% |
| Worst frame, frontier idle | 22 ms | 3.9 ms | −82% |
| Host upload, 133 mobs | 507 KB/s | 152 KB/s | −70% |

The frame rate that matters to a player — the windowed frontier — went from
**52 fps to about 153 fps**.

### Certified suites

All forty-seven suites were run against the tree the numbers above were taken
from:

| Clean | Pre-existing failures |
| --- | --- |
| 44 suites, ~34,000 checks | `devil_regression` 78/80, `corpse_regression` 69/70, `network_input_regression` |

Those three fail identically on unmodified `main` and are not regressions: the
cinder devil's death clip and corpse head drop, the procedural delve devil
killed in the air, and the arena's four-process input suite.

At 175 mobs fighting, the largest remaining costs are the state machines and
sight rays of the bodies in reach (about 4 ms), the rigs of the bodies inside
the animation range (about 1.7 ms), and the cost of a hundred and seventy-five
bodies existing at all. The physics server is not among them: kept bodies cost
0.05 ms.

## The budget, itemised

A frontier frame, one ranger and seventy-five monsters, scopes off, each row
measured by taking one thing away and re-measuring:

| | ms | how it was measured |
| --- | --- | --- |
| World, ranger and loop, no mobs | 0.75 | every mob freed |
| Body, node and rig, all seventy-five | 0.67 | every mob's tick stopped |
| The tick itself (decisions, sight, motion, presentation) | 0.31 | that number minus the one below it |
| **Total** | **~1.75** | |

The rigs inside the first row were priced separately: freeing the presentation
subtree of every mob moves a headless frame by **0.15-0.24 ms** depending on the
scene, and most of that is the per-frame calls *into* the sampler rather than
the rig's own processing — with a dummy renderer there is no skinning or draw to
save. A monster's rig is a **rendering** cost: it shows up in the windowed
numbers, where freezing the offscreen ones was worth 0.16 ms, not in the
headless ones. A body with an *empty* scripted tick and a collision shape
measures **0.19 µs** — Godot's per-node cost is not what any of this is.

So a monster near the ranger costs 17-27 µs, split roughly three ways between
its rig, its tick and the script inside that tick, and every one of those parts
is per-node-per-frame work. There is no single line item to delete.

Ninety percent of the original 9.14 ms is **0.91 ms**, which leaves **0.16 ms
for every monster** — about 2 µs a body. Nothing in this model reaches that by
tuning; every path to it is a different shape of object.

## What a monster costs, by how close it is

`--keep=N` frees everything but the N nearest frontier mobs, so the frame can be
plotted against population (`--noscopes`, median of the run):

| mobs kept | nearest is | median frame |
| --- | --- | --- |
| 0 | — | 0.75 ms |
| 10 | inside ~25 m | 1.06 ms |
| 20 | inside ~40 m | 1.32 ms |
| 30 | inside ~55 m | 1.62 ms |
| 45 | inside ~80 m | 1.71 ms |
| 60 | inside ~110 m | 1.80 ms |
| 75 | the whole frontier | 1.78 ms |

The knee is at about thirty. **The first thirty monsters cost 0.87 ms — 29 µs
each — and the next forty-five cost 0.16 ms, 3.5 µs each.** That is the culling
and rig release working exactly as intended: a monster nobody can see is nearly
free, and the price of the frontier is set by the handful standing near the
ranger, not by how many were authored.

In a room where every monster is close — the hundred-mob benchmark — the same
bodies cost closer to 55 µs each, because they are all in reach, fighting, and
separating, so more of them run at the thirty-hertz fight rate.

This is the number the ninety-percent question actually turns on: the target
leaves 0.16 ms for monsters, which is about five nearby bodies in the current
model, or one that costs a seventh as much.

## What is left

In rough order of payoff, for whoever picks this up:

- **Stop paying 14.7 µs a body.** Releasing distant rigs recovered the skinned
  half; the floor for a bare body here is 0.41 µs, so the rest is the scripted
  node and what surrounds it.
- **A cheaper mob model altogether** — instanced or aggregate bodies for the
  rank and file, with full nodes only for the ones in reach. This is what a
  ninety percent cut actually looks like.
- **One brain for a pack.** A hundred mobs in one room do a hundred sight rays,
  a hundred spacing walks and a hundred state machines to produce what is, in
  practice, one fight.

Measured and dismissed, so nobody repeats them:

- **Hoisting `global_position` out of the mob tick** — the tick used to read its
  own transform a dozen times and the target's as many again. Threaded through
  as local arguments it made no measurable difference: mobs are children of the
  scene root, so the lookup is short. Reverted.
- **Streaming far bodies out entirely** — freeing every mob past 72 m and
  rebuilding it from a record was built and measured: 25 of 75 bodies slept and
  the frame moved 0.05 ms, because releasing their rigs had already taken the
  far-body cost. It was reverted rather than carried.
- **Driving the `AnimationPlayer` by hand to make the thirty-hertz stride real**
  — `set_process(false)` plus `advance(delta)` on the sampled frames made the
  frame *worse* (1.79 → 1.90 ms and 7.0 → 7.7 ms in the room): Godot's own
  player update is cheaper than an explicit `advance` per sampled frame. Only
  freeing the rig removes the clip cost.
- **A tighter or slower animation range** — 45 m to 24 m, and half-rate
  everywhere instead of only past 12 m, both moved the frame by less than the
  run-to-run noise. The animation that remains is the ranger's own rig and the
  handful of bodies actually near him, and that is content, not waste.
- **A cheaper HUD frame** — `main._process` costs 0.17 ms with the whole status
  block, the reticle, the map and the interaction probe in it.
- **Replacing the mob bodies with analytic hitboxes** — the shapes cost 0.05 ms
  across 175 bodies once locomotion stopped querying the physics server.
- **Coarser scatter chunks** — 44 m to 96 m moved draw calls by 4% and grew the
  primitive count by 16%; the frontier is not chunk-bound.
- **Turning anti-aliasing off** — 0.33 ms for the whole frame at 4x MSAA,
  because the GPU is not the bottleneck on this scene.
