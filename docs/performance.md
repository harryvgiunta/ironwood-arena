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
| `--legacy=1` | Runs against a tree from before this work, for an A/B. |

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
already in reach — thinks every second tick. Everything else thinks every
third tick inside 22 m, every sixth out to 55 m, and every twelfth beyond. A
decimated tick scales `delta`, so speeds, cooldowns and state timers stay in
real time. The distinction matters: a hundred devils standing in a ring around
one ranger are a hundred orbits, not a hundred fights.

Spacing is a soft constraint on top of that: it is re-measured one frame in six
and the result reused, staggered per mob so a hundred bodies do not all measure
on the same frame.

### The rigs are culled and slowed with distance

Past 45 m a mob's body stops drawing and its clip stops writing bone tracks;
between 12 m and 45 m the sampler runs every other frame. Nobody can read a walk
cycle through the treeline, and the animation of every distant devil was a
third of a frontier frame.

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

`devil_mobs_regression` and `forest_mobs_regression` pin both halves: a body in
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

## What it costs now

Medians of three runs; "before" is the same suite against the same scene at
`main`'s commit. Frame figures move by about eight percent between runs on this
machine, so treat the last digit as noise; the idle frontier has measured
between 2.28 and 2.50 ms across runs.

| Scenario | Before | After | Change |
| --- | --- | --- | --- |
| Headless, frontier idle | 9.14 ms | 2.44 ms | −73% |
| Headless, 175 mobs fighting | 36.13 ms | 8.17 ms | −77% |
| Windowed (GTX 1080), frontier idle | 19.14 ms | 6.55 ms | −66% |
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

Three suites fail on `main` as well as here, and are not regressions:
`devil_regression` (2: the cinder devil's death clip and corpse head drop),
`corpse_regression` (1: the procedural delve devil killed in the air) and
`network_input_regression` (27).

At 175 mobs fighting, the largest remaining costs are the state machines and
sight rays of the bodies in reach (about 4 ms), the rigs of the bodies inside
the animation range (about 1.7 ms), and the cost of a hundred and seventy-five
bodies existing at all. The physics server is not among them: kept bodies cost
0.05 ms.

## What is left

### Where the budget actually is

Freeing every frontier mob leaves **0.92 ms** — the world, the ranger and the
loop. The seventy-five mobs cost the rest: **1.91 ms** before rigs were
released and **1.35 ms** after, which is **18 µs per body per frame** — about
12 µs of script and the remainder engine, now that only the bodies in view
carry a rig.

That is the whole picture, and it has a blunt consequence: `main`'s frame was
9.14 ms, so a ninety percent cut is 0.91 ms — **the world's cost with no mobs
in it at all**. Hitting it by optimising mobs one at a time is not reachable
however far the per-mob cost falls; it needs a cheaper *model* of a mob.

In rough order of payoff, for whoever picks this up:

- **Stop paying for a body to exist at all.** Releasing distant rigs recovered
  the skinned half; what is left is the physics body and the scene node
  (roughly 6 µs of the 18).
- **A cheaper mob model altogether** — instanced or aggregate bodies for the
  rank and file, with full nodes only for the ones in reach. This is what a
  ninety percent cut actually looks like.
- **One brain for a pack.** A hundred mobs in one room do a hundred sight rays,
  a hundred spacing walks and a hundred state machines to produce what is, in
  practice, one fight.

Measured and dismissed, so nobody repeats them:

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
