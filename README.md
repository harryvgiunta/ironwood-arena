# Ironwood — Town, Frontier, Arena and the Endless Sunken Delve

A Godot 4 third-person action game with one in-game world: a main menu, a walkable PvE town with three keepers, a stash and an arena portal, a seamless woodland frontier, an **open world you can host for up to four rangers** (town and frontier together), a four-combatant multiplayer arena, and an endless two-room survival delve beneath the town. The ranger carries a **15-slot backpack**, a **20-slot stash** and **ten independent equipment slots**. A textured, rigged male Ranger with authored human animation, swappable bows, swords, daggers, shields, staffs, foci and jewelry, dual wield and armor, free-aim archery, thrown swords and daggers, contact-driven melee attacks, and directional jump-rolls.

## Windows quick start

Requires Windows x64, PowerShell, and [Git](https://git-scm.com/download/win). No Godot installation, Node.js, paid assets, or game account is required.

```powershell
git clone https://github.com/harryvgiunta/ironwood-arena.git
cd ironwood-arena
.\Setup.cmd
.\Play.cmd
```

`Setup.cmd` downloads **Godot 4.7.2 stable** from its official GitHub release, verifies the pinned SHA-256 checksum, and installs it inside the ignored `.runtime/godot` directory. No administrator access or system-wide installation is needed. Running setup again reuses the verified-version installation. The game launchers also run setup automatically if the managed engine is missing.

The launchers import the bundled character assets before starting the game, so a fresh checkout does not need an existing `.godot` cache. Subsequent launches reuse imported assets. Blender is not required to play.

- **Play.cmd:** opens the main menu (**Start New Game**, **Load Saved Game**, **Host Open World**, **Join Game**).
- **Arena.cmd:** opens the standalone multiplayer lobby directly, or solo practice against bots. Its **Return to Town** button loads the PvE town.
- **Host World.cmd:** starts the town/frontier as an open world on UDP 7777 with your Windows user name, so friends can join without a delve or arena. **Host Open World** in the main menu does the same on the remembered port.
- **Host Tailscale.cmd:** starts the town/frontier in delve-host mode on UDP 7777 with your Windows user name. Walk into the **Wayfarer Inn** and jump into the Sunken Delve hatch to host on that port. Friends join with the main menu's **Join Game** form, choosing **Delve party**.

Set `GODOT_PATH` to use another existing Godot executable. Linux/macOS users can install Godot 4.7.2, import `project.godot`, and run `title.tscn`, `main.tscn`, `arena.tscn` or `delve.tscn`; the Windows setup script does not install engines for those platforms.

## Main menu and the town

Every launch opens the **main menu** with four doors:

| Menu action | Result |
| --- | --- |
| **Start New Game** | Resets the ranger to the starter kit, purse and empty stash, then starts at the south gate of Hearthstead. |
| **Load Saved Game** | Restores `user://player_state.json` and starts at the town gate. Disabled when no save exists. |
| **Host Open World** | Opens the current town and frontier as a four-ranger host on the remembered UDP port (default 7777). Friends join it with **Join Game**. |
| **Join Game** | Opens the cached name/address/port form and joins an **arena match**, **delve party** or **open world**. |

There is no out-of-game depot. **Hearthstead** is the staging town inside the open PvE world, and every service is a real object you walk up to and press **G** on:

| Town service | Where | What it does |
| --- | --- | --- |
| **Smith Brann** | ForesterHouse, behind the forge counter | Swords, daggers and shields |
| **Storekeeper Orla** | FletcherWorkshop, behind the counter | Bows, staves and trail goods |
| **Quartermaster Vey** | HearthsteadStore, behind the counter | 20 armor pieces plus foci, necklaces and rings |
| **Town Stash** | Open market awning | 20-slot long-term storage, beside your 15-slot backpack |
| **Arena Portal** | Green west of the Wayfarer Inn | Hosts a local four-seat arena on the first free UDP port |
| **Hearthstead Campfire** | Town square | Restores health and stamina |
| **Sunken Delve hatch** | Inside the Wayfarer Inn | A real hole in the floor: jump in to fall into the delve |

The starter kit is the five Ranger leather pieces plus the shortbow in the main hand, **every catalog weapon in the backpack**: three bows, three swords, the iron dagger, two staffs and three shields, and **99,999** credits. The tab buttons in the town shops are **STORE**, **SMITH** and **QUARTERMASTER**. Bought gear needs a free backpack slot; selling pays 60% of the purchase price.

Press **I** anywhere in the world to open the **inventory** (15 backpack slots plus the ground strip). Press **P** to open the **equipment paperdoll** (10 equipment slots: head, chest, hands, legs, feet, neck, ring 1, ring 2, main hand and off-hand). Right-click a backpack item to equip it to its natural slot, a paperdoll item to return it to the pack, a stash item to take it, or a ground item to pick it up. While a keeper or the stash is open, the same overlay adds their stock or the 20-slot stash beside the pack; **EQUIP**, **TO STASH**, **TO INVENTORY**, **SELL** and **DROP** act on the selected piece. Drag-free controls: click a slot, then use the action buttons.

**TAB swaps one bound weapon pair.** The starter bind is the equipped shortbow against the shortsword and buckler, so TAB alternates ranged and sword-and-board out of the box. The outgoing pair becomes the new bind, so the same key toggles back. Any legal main/off combination works: bow, one- or two-handed sword, dagger, staff, shield, focus or a dual-wield pair. To bind a different pair, equip it, open **P**, select the main or off-hand slot, and press **BIND SWAP**; the paperdoll shows the active bind and every swap is written to the save. Both pairs must be carried in the backpack or hands; a stashed piece blocks the swap with a message.

Dropping a piece in town, the frontier or the delve spawns a physical world pickup at the ranger's feet. It arms only after you step clear, so the dropper cannot scoop it straight back up. Arena drops fall back to the persistent ground list. Every successful change is written to `user://player_state.json` immediately; equipment is stored separately from the backpack, and the main/off hands plus five armor pieces become the starting loadout in every mode. Deleting that file restores the starter kit.

Loot is tuned to **a tenth of its old rate**: a weapon-carrying devil leaves the piece it held 10% of the time, the frontier gear rotation drops on 5% of eligible kills, and a delve cache has a 10% chance of an item. Cache gold, kill gold and waystone rewards are unchanged.

**New-game vs. load:** Start New Game overwrites the save with the starter kit; Load Saved Game re-reads the saved kit, stash, ground items and purse. The delve is an in-session endless run, so it has no resume checkpoint.

### Item taxonomy and hand rules

| Category | Legal slots | Examples |
| --- | --- | --- |
| One-handed (`1h`) | Main hand or off-hand | Shortsword, arming sword, iron dagger |
| Two-handed (`2h`) | Main hand only; locks the off-hand | Greatsword |
| Bow | Main hand only | Shortbow, recurve, longbow |
| Staff | Main hand only; locks the off-hand | Ember Staff, Bone Staff |
| Shield | Off-hand only | Buckler, kite shield, tower shield |
| Focus | Off-hand only | Ash Tome, Bone Skull, Skull of Life, Skull of Death |
| Armor | Its own head / chest / hands / legs / feet slot | Leather, mail, plate and Emberweave pieces |
| Jewelry | Neck, or either ring slot | Ember Charm, Amulet of Energy Shield, seventeen rings |

- Right-click routing sends one-handers to the **main hand**, shields and foci to the **off-hand**, armor to its own slot, a necklace to the neck and a ring to the first empty ring slot (then ring 1). Alt+right-click and drags onto a slot choose the hand explicitly.
- Equipping a two-handed weapon, bow or staff **overrides both hands**: an existing main-hand and off-hand item are both returned to the backpack. If the backpack has room for only one, the second displaced item lands on the floor.
- Equipping a shield or focus while a two-handed weapon, bow or staff is in the main hand **returns that weapon to the backpack** and leaves the main hand empty.
- Two one-handers may occupy the main and off hand together. The loadout enters dual wield only when a one-handed sword is in the main hand and a dagger or another one-handed sword is in the off hand, with no shield, focus or staff involved.
- The shield pairs with **any one-handed sword or the dagger**, including the shortsword. A bow, greatsword, staff or dual wield stows it. Staffs keep the greatsword's damage and swing clock but use their own **middle grip**, shaft length and 1.6/1.5 m cleave reach; foci are held and cosmetic.
- Dragging between two paperdoll slots moves a piece into an empty legal slot or swaps two pieces. Illegal moves (a ring to the neck, a two-hander to the off-hand) are rejected. Unequipping returns a piece to the backpack; dropping it sends it to the floor.

### Trinkets: necklaces, rings and the held skulls

A **neck** piece, either **ring** and the **off hand** can change the ranger's numbers. `scripts/trinket_stats.gd` is the single table; the controllers only read its aggregate, so a new trinket is one catalog row plus one entry there.

| Slot | Item | Effect |
| --- | --- | --- |
| Neck | **Amulet of Energy Shield** | Grants **ENERGY SHIELD** on **SHIFT + 3**: a yellow bubble that absorbs **50%** of every hit and takes **twice** that share from stamina instead. Lasts **60 s**, the bubble pops when the pool cannot pay |
| Ring | **Ring of Dash** | Grants **DASH** on **SHIFT + 3** (double speed for 1 s, down the crosshair) |
| Off hand | **Skull of Life** | **+15 life** on every kill you land |
| Off hand | **Skull of Death** | **+15 stamina** on every kill you land |
| Ring | **Ring of Health** | +25 max health |
| Ring | **Ring of Ironhide** | +20 max health, +2% damage reduction |
| Ring | **Ring of Ranged Damage** | +10% ranged damage (arrows, bow skills, spells) |
| Ring | **Ring of Melee Damage** | +10% melee damage (blades, blade skills, backstab) |
| Ring | **Ring of Throwing** | +25% thrown weapon damage |
| Ring | **Ring of the Swift** | +8% movement speed |
| Ring | **Ring of Haste** | +12% attack speed (bow draw and swing clocks) |
| Ring | **Ring of Vigor** | +150 max stamina |
| Ring | **Ring of the Tide** | +30% stamina regeneration |
| Ring | **Ring of Warding** | +6% damage reduction, added to the armor total |
| Ring | **Ring of Grit** | -25% stagger suffered |
| Ring | **Ring of Bounty** | +25% gold from kills |
| Ring | **Ring of Echoes** | -15% skill cooldown |

- The three worn trinkets add up: two health rings and the ironhide band give **145** max health on a 100 base.
- The **necklace wins the third ability slot**, then ring 1, then ring 2, so a kit always resolves one skill deterministically. A stat-only ring leaves that tile hidden and **SHIFT + 3** inert.
- **Skulls pay out in the frontier, the arena and the delve** — the killer is recorded on every mob, and only that ranger's own skulls refill. Both skulls are off-hand holds, so they are unavailable while a bow, staff, greatsword, shield or dual-wield pair is out.
- The plain **Ember Charm**, **Bone Talisman** and the three cheap rings remain flavor pieces with no combat effect.
- Health and stamina maxima are per-actor now: **125/125** and **1150** read that way on every HUD, and a removed ring clamps the live pool back down instead of leaving an over-full bar.

### Looting in the frontier

Frontier enemies can drop **physical gear** on death. Walk within **1.6 m** of a drop to pick it up; the pickup enters the **backpack first** and is never auto-equipped. A **full backpack leaves the item on the ground**, and a second attempt still refuses it. Loot covers swords, daggers, shields, staffs, foci, armor, necklaces and rings. **A cinder devil carrying a weapon always drops that exact piece** — iron dagger, shortsword or recurve bow — and the corpse releases the mesh; the same rule covers the delve devils' daggers and swords. Claw devils and wolves keep the rotating gear drop. Carry loot back to town, open **I**, and equip or sell it at a keeper; unwanted gear can also be dropped at the ranger's feet and picked back up from the world.

Dropping gear from the **inventory** (**I**) in town, the frontier or the delve likewise spawns a `LootPickup` at the ranger's feet. That drop starts **unarmed**: it only arms after the dropper steps out of the 1.6 m pickup radius, so walking back over it later banks it into the backpack normally. The delve copy keeps the same arming rule and local pickup list; a full backpack still leaves it on the ground.

### Armor: four sets, five slots

Armor is equipped **per slot**, so a cloth hood can sit over a mail hauberk, leather gloves and plate legs. Every set supplies a head, chest, hands, legs and feet piece:

| Set | Head | Chest | Hands | Legs | Feet | Full-set guard |
| --- | --- | --- | --- | --- | --- | --- |
| Ranger leather | Hood 10 | Jerkin 15 | Gloves 8 | Trousers 12 | Boots 10 | 0% |
| Sentinel mail | Coif 35 | Hauberk 55 | Mittens 25 | Chausses 40 | Sabatons 25 | 15% |
| Warden plate | Sallet 65 | Cuirass 90 | Gauntlets 45 | Cuisses 80 | Sabatons 40 | 30% |
| Emberweave cloth | Hood 25 | Robe 45 | Wraps 20 | Skirt 35 | Boots 15 | 0% |

The leather outfit is the imported Ranger mesh split by region; mail is riveted ring weave, plate is blackened articulated steel, and Emberweave is a layered mage robe with a torn hem and brass trim. Each piece renders on the same 65-bone skeleton as the ranger and follows the authored idle, draw, swing, crouch, slide, roll and cover poses. A dark hose underlayer fills the shin whenever the short leather trousers are mixed with short sabatons.

Each piece contributes its own guard: mail head 3% / chest 5% / hands 2% / legs 3% / feet 2%; plate head 7% / chest 9% / hands 4% / legs 6% / feet 4%. Mixed kits add the pieces actually worn, capped at 45%. The town Quartermaster sells all 20 pieces alongside the four foci, three necklaces and seventeen rings; old whole-set items from earlier saves are migrated to the five slots on load.

In a match, the arena's session panel lists five slot buttons (**HEAD / CHEST / HANDS / LEGS / FEET**). Click a slot to cycle Leather → Mail → Plate → Cloth for that session. Session changes are not written back; only the equipment paperdoll's pieces persist.

## Play with friends over Tailscale

All players should use the same current checkout and be connected to a tailnet that permits them to reach the host.

### Open world (shared town and frontier)

Press **Host Open World** in the main menu, or run `Host World.cmd`, to open the PvE town and frontier on UDP 7777. The HUD's top-left line reports the session (`OPEN WORLD / UDP 7777 / 2 RANGERS`). Friends pick **Join Game → Open world**, enter the host's Tailscale IP and the port from that line, and arrive at the Hearthstead gate as their own saved ranger. Up to four rangers share the world.

The host is authoritative for every ranger and mob. Clients send movement, aim and action intents, never damage, charge or positions. Mobs chase and strike the nearest ranger they can see (sight cone, range, line of sight and a 15 s pursuit memory; see `scripts/mob_senses.gd`); kills, arrows, thrown weapons, loot drops, waystone restorations and gold are replicated to every peer. Keepers, the stash and the backpack stay **per player**: each peer trades against its own `user://player_state.json`, and a world drop is granted to whichever ranger picks it up on their own machine. Only the host can restore a waystone or step into the arena portal. The hatch is host-led: when the host drops through the inn hatch, the live ENet party follows into a hosted delve on the same port, and a client that drops in alone is set back on the inn floor instead of leaving the world. If the host closes the game, clients see the connection message and continue alone with live mobs. There is no host migration.

### Host

```powershell
.\Arena.cmd -- --arena-host --arena-port 7777 --arena-name Host
```

Keep the host window open. Find the address to send privately to your friends:

```powershell
tailscale ip -4
```

For a delve party, run **`Host Tailscale.cmd`** instead. It starts the frontier with `--delve-host --delve-port 7777 --delve-name "%USERNAME%"`: the host walks into the Wayfarer Inn in Hearthstead and jumps into the Sunken Delve hatch, which hosts the delve on the requested port. The host window must stay open through the descent. An **Open World** host needs no extra launcher: dropping through the hatch carries its live party into a hosted delve on the world's port.

### Join

Replace `HOST_TAILSCALE_IP` with the address supplied by the host:

```powershell
.\Arena.cmd -- --arena-join HOST_TAILSCALE_IP --arena-port 7777 --arena-name Buddy
```

Or enter the address and port in the arena lobby and click **Join Game**. Use `127.0.0.1` only when both instances run on the same computer. Host addresses are not stored in this repository.

There are four seats: the host and up to three joining humans. Empty seats use bots. Joining replaces a bot; disconnecting restores one. A fifth human is refused. Health, movement, attacks, thrown weapons, damage, kill/death scores, and respawns are host-authoritative. Clients send input and aim points, not damage or charge claims. The host leaving returns clients to the lobby; there is no host migration or matchmaking service.

The delve uses the same ENet transport. A delve host needs no lobby: the party falls into the chamber and waits at the altar until any survivor presses **G**. A host launched with **`Host Tailscale.cmd`** starts in town and opens the party from the inn hatch, which reports the same requested port. A client joining during a wave drops into the chamber; a client joining after a clear lands beside the cache. A fifth ranger is refused. The host owns depth, wave, seal, cache, rope, hole and wipe state; clients only send movement and action intents. If the host leaves, clients see **Connection Lost** and can return to town. An open-world host that leads the party through the hatch keeps the same ENet peers and port, so nobody reconnects; a rider who falls in alone is set back on the inn floor. While the host is in a delve that came from its open world, friends join with **Delve party** on that port.

### Connection troubleshooting

- Confirm the host is actually hosting: an open-world session shows `OPEN WORLD / UDP <port> / N RANGERS` at the top left; for an arena it must be in a match rather than merely the lobby, and for a delve after the hatch/descend press rather than still standing in the frontier or on the landing.
- Run `tailscale ping HOST_TAILSCALE_IP` from the joining PC. This checks tailnet connectivity, not the game's UDP port.
- Permit UDP **7777** in any custom tailnet access policy and allow the host executable through its local firewall.
- If necessary, run `Allow Tailscale Host.ps1` in an elevated PowerShell on the **host only**. It creates a narrowly scoped rule for this engine, UDP 7777, the Tailscale adapter, and Tailscale IPv4 addresses. It is optional and never runs automatically.
- **Tailscale needs no router port forwarding.** Direct public-IP play without Tailscale requires the host to arrange forwarding and firewall access.
- After pulling updates, restart all game instances. An old running host cannot use newly changed scripts or network contracts.

See [Tailscale's firewall guidance](https://tailscale.com/docs/reference/faq/firewall-ports).

### Networking configuration

There is no separate config file. The session hand-off lives in `scripts/session.gd` (default UDP **7777**), the remembered player name, address, port and join mode in `scripts/net_cache.gd` (`user://net_cache.json`), and each mode creates its own `ENetMultiplayerPeer`: the open world in `main.gd` (`world-host`/`world-join`, host + 3 peers), the arena in `arena.gd` (4 fighters), the delve in `delve.gd`. Fighters snapshot at **20 Hz**, frontier mobs at **15 Hz**, and a whole delve wave shares one tick across as many datagrams as it needs.

Every packet is clamped by `scripts/net_limits.gd`: **1200-byte `MTU`**, a **1100-byte payload budget** after the RPC/ENet envelope. Godot exposes no MTU setting on `ENetMultiplayerPeer` (and `SceneMultiplayer.max_sync_packet_size` only governs `MultiplayerSynchronizer`, which this project does not use), so the clamp is applied where payloads are built — multi-body batches are sized by encoded bytes rather than a fixed body count, and the fighter snapshot's animation, cover and ability blocks travel as value arrays instead of keyed dictionaries. A maximal-name fighter snapshot measures **~1.07 KB**, the heaviest mob or clone **~0.6 KB**, and a 30-body delve wave splits into 4 datagrams. `tests/net_limits_regression.gd` fails if any of them crosses the budget.

### Prediction, reconciliation and lag compensation

Movement is **client-side predicted and server reconciled** (`scripts/net_replication.gd`, `scripts/lag_compensation.gd`). The peer that owns a ranger integrates its own movement frame immediately — the same `_resolve_motion`/`_integrate` pair the host runs — and records every frame in a bounded ring buffer. Each intent carries its frame number, the server tick the peer was drawing, and the previous three frames, so a dropped datagram cannot leave the host permanently short of that peer's travel. The host queues the frames and simulates exactly one per tick, draining any backlog in the same tick; a tick that brought no frame holds the pose instead of repeating the last intent, because a repeated intent walks the authority ahead of the frames that own the body and every invented frame comes back as a correction. It then acknowledges the newest consumed frame with the pose that frame produced.

The owner compares its own recorded pose for the following frame. Agreement within a couple of frames of its own travel — the steady state, since the authority names a tick and a tick either side of the peer's frame is legitimate — moves nothing. A larger disagreement is applied as a **displacement**: the authority's pose minus the pose this peer recorded for the same instant, added to the present body, with the unacknowledged ring dropped. It is not re-simulated frame by frame: replaying from the authoritative pose cannot reproduce a path the local simulation produced through collisions and slopes the replay never met, and every mismatch came back as a pop of the whole window. Nothing here calls `move_and_slide()` — outside the physics frame it integrates against the idle frame's delta, which is what launched bodies across the map — and the correction is applied inside the physics frame rather than in the RPC callback. A body a peer's frames drive also **holds** its pose on a tick that brought no frame (repeating the last intent walked it ahead of the frames that own it), and each movement packet repeats the previous three frames so a lost datagram cannot leave the host permanently short of that travel.

What the player sees is separated from that: the model is drawn at its previous pose and moved toward the corrected one at most 0.35 m a frame, so a correction reads as the character stepping into place. The third-person boom zooms toward its collision-resolved length at 18 m/s in and 5 m/s out instead of adopting it, because snapping it in whenever a trunk crossed the line and back out when it cleared shook the whole view. Under a simulated 80 ms ± 15 ms link with a mob on the ranger, the model moves at most 0.17–0.35 m a frame, the boom at most 1.5 m, and the body (which takes the authority's verdict at once) at most ~1.4 m.

Everyone else is drawn **in the past**: a fighter, mob, devil or clone keeps a short buffer of server states and renders a delay behind the newest one, interpolating between two known poses and dead-reckoning along the last velocity when a packet drops. The playout clock is nudged toward its delay target (widening the delay when arrivals are irregular) rather than snapped, so a late packet slows the body for a moment instead of teleporting it; only a genuine discontinuity — a revive, a backstab blink, a scene hand-off — restarts the buffer. Mobs derive a velocity from their own sample spacing when the wire carries none, so a stream without velocities still extrapolates.

Localhost hides all of this: at 0.1 ms the past and the present are the same frame, so broken prediction, interpolation and rewind look correct. `--net-lag <ms>` with `--net-jitter <ms>` turns on `NetReplication.LagQueue`, which holds every high-frequency stream (`_world_move`, `_world_action`, `_world_seat`, `_world_mobs`) for that long before applying it. `--net-diag` prints one `NET_DIAG` line a second — role, slot, corrections, drift, the worst model and boom step of that second, unacknowledged frames — so a report from a real match carries numbers. Pass the flags to both peers:

```
Play.cmd res://main.tscn -- --world-host --world-port 7777 --world-name "you" --net-lag 80 --net-jitter 15
Play.cmd res://main.tscn -- --world-join 100.101.102.103 --world-port 7777 --net-lag 80 --net-jitter 15
```

Strikes are judged against the world the client saw. The host records one second of every damageable body's real capsule, and an action that arrives with its owner's view tick is resolved first against the present world and then against that history: a body that stepped out of the cut still takes the blow it saw land, and a precision contact the shooter's own frame cannot explain is refused. Projectiles carry the shooter's view lag and check it at impact, so a shaft only stops on a body that was under it on the shooter's screen. `tests/net_prediction_regression.gd` drives the real primitives and two real ENet processes; `tests/world_network_regression.gd` checks the open-world client predicts and is acknowledged.

## Controls

| Control | Action |
| --- | --- |
| WASD | Move relative to the camera; slide along the surface while in cover |
| Shift | Run, or slide faster while in cover; consumes stamina |
| Space | Jump |
| Shift + Space | Immediately jump-roll in the movement direction, or forward if stationary |
| F | Post up against nearby solid cover / leave cover |
| Hold right mouse with a sword | Guard. The first 0.25 s is a parry; holding longer standard-blocks each hit and spends stamina |
| Hold right mouse with a dagger | Weak guard only: no parry, and blocked hits deal half damage while spending more stamina |
| Hold right mouse with a shield | Raise the shield. Full front block, no parry, **18 stamina**; arrows that hit it deal no damage and stick in the shield |
| Hold right mouse in cover | Guard and peek over low cover or around the selected edge of tall cover |
| X | Swap shoulder camera and select the left/right lookout while in cover |
| 1 | Equip the selected bow |
| 2 | Equip the selected sword |
| 3 | Equip the dagger |
| 4 | Equip or stow the shield (any one-handed sword or the dagger) |
| 5 | Dual-wield the selected one-handed sword in the right hand and the dagger in the left; press again to return to the sword |
| TAB | Swap the equipped main/off pair with the bound quick-swap pair; the displaced pair becomes the new bind |
| 6 | Use a bandage: three-second channel, then 35 health over the next three seconds |
| 7 | Drink a healing potion: half-second channel, then 50 health |
| Mouse movement | Mouse-look with a fixed center crosshair; no aim assistance |
| Hold left mouse with bow | Raise and draw while aiming; automatically expose from cover |
| Release left mouse with bow | Launch one arrow; cover shots wait for exposure without gaining charge |
| Click left mouse with sword or dagger | Break sticky cover and cut diagonally from the current camera shoulder; accepted cuts alternate sides, and X resets the next side |
| Scroll wheel up with sword or dagger | Forward stab along the crosshair |
| Scroll wheel down with sword or dagger | Authored overhead chop (dagger uses its precision stab) |
| Hold T with a sword or dagger | Charge a throw while aiming. Damage scales with charge, and a bow-style recovery follows the release |
| Release T with a sword or dagger | Hurl the equipped weapon as a projectile. The endless supply keeps the same weapon equipped |
| Click left mouse while dual wielding | Left-hand diagonal cut from the left |
| Click right mouse while dual wielding | Right-hand diagonal cut from the right; never a guard |
| Q / E | Side-step left / right with the shoulders turning into the move; grounded, short cooldown, 7 stamina |
| Shift + 1 / Shift + 2 / Shift + 3 | Cast the skill granted by the equipped main hand / off-hand shield / worn trinket; each costs 1 stamina for testing |
| G | Interact with a keeper, the stash, the campfire or a waystone; open a wave cache, descend, or ascend |
| I | Open or close the in-world inventory (15 backpack slots plus the ground strip); while open it owns the cursor and blocks movement, attacks and interactions |
| P | Open or close the equipment paperdoll (ten equipped slots); while open it owns the cursor and blocks movement, attacks and interactions |
| F8 | Toggle the frame-performance overlay: measured frame time and fps, worst frame and 1% low, the engine's process/physics clocks, draw calls, primitives, objects, node/resource/memory counts, the frontier's live/skipped/rigged/drawn mob split, and the live `Perf` scope table. It works in the frontier, the arena and the delve, including while joining, and turns the profiler on only while it is open |
| Escape | Close the inventory, paperdoll, keeper or stash panel first; otherwise free the cursor for equipment clicks, cancel a held attack, or toggle the captured cursor in the arena and delve |
| Click the world / right mouse | Resume captured mouse-look; right mouse also raises a sword guard |
| Mouse wheel | Select the melee variant when armed; hold Ctrl to zoom |
| C | Toggle crouch while grounded; slide when pressed during a sprint |

### Abilities and stamina

The base stamina pool is **1000**. Sprinting and sliding drain **19/s**, standing recovery is **13/s**, and guarding pauses recovery; block and step costs are unchanged. The HUD shows the pool and three ability slots: **SHIFT + 1** for the main hand, **SHIFT + 2** for the off-hand shield and **SHIFT + 3** for the worn trinket, each with its icon, stamina cost and cooldown.

Abilities are data-driven and item-granted by `scripts/ability_rules.gd`: equipping a weapon grants its skill to the main hand, equipping a shield grants its skill to the off hand, and wearing the amulet or the dash ring grants its skill to the trinket slot. A definition carries the granting item, hand slot, keybind, stamina cost, cooldown, durations, travel window, a `move` flag, animation clip, lean or spin, sound, icon and an effect block; `scripts/ability_runner.gd` owns eligibility, spend, cooldown, committed travel, timed effect cues and replication. Every weapon skill currently costs **1 stamina** and has a short cooldown so the set can be exercised back to back. Swapping the granted weapon clears that slot's trailing cooldown; the cooldown exists so swapping cannot become a free damage loop. An empty main hand keeps the legacy unarmed **Charge** (10 stamina, 200% walk speed for one second).

`move` decides what the feet do. **Double Slash, Lunging Thrust, Spinning AOE Spin, Headbutt, Shield Charge and Ground Shield Slam** keep normal walking input; **Barrage, Triple Fan Volley, Long Piercing Shot, Fireball, Bone Spear**, the unarmed **Charge** and **Backstab** stay planted. Committed travel still wins during its window (**0.24 s** lunge, **0.16 s** headbutt, **0.48 s** shield charge), and the walk resumes once it ends; no ability allows sprinting or jumping. A definition's `aim` flag makes that committed step travel down the live crosshair instead of the heading the key was pressed from, so the lunge, the headbutt and the shield charge all turn the body onto the crosshair and dash along it. Skills that cannot be performed from a crouch — every blade, shield and dagger skill plus the unarmed Charge — are performed standing: activating one cancels a manual crouch, snaps the capsule upright and only spends the skill once the body has headroom to stand, so the authored clip always owns the whole pose. The planted bow and staff casts still layer over a crouch.

| Main hand | Skill | Feet | Effect |
| --- | --- | --- | --- |
| Shortbow | **BARRAGE** | Planted | Six rapid arrows at 50% damage, each leaving along the live crosshair in a 4° fan |
| Recurve | **TRIPLE FAN VOLLEY** | Planted | Three arrows in one wide fan at 70% damage |
| Longbow | **LONG PIERCING SHOT** | Planted | One heavy arrow at 200% that punches through three bodies |
| Shortsword | **DOUBLE SLASH** | Walks | Two fast front-arc cuts at 90% each, landing at 0.26 s and 0.52 s |
| Arming sword | **LUNGING THRUST** | Walks | A 0.24 s dash at 405% travel (5.34 m at 22.3 m/s) that cuts its whole 1.35 m lane once, then a 180% thrust |
| Greatsword | **SPINNING AOE SPIN** | Walks | A 0.3166667 s full turn that cuts everything within 2.9 m, trailed by a steel-cyan blade trail and a dim warm dust ring |
| Iron Dagger | **BACKSTAB** | Planted | Blinks behind the aimed foe in a black smoke burst and plunges for 28 (2x dagger), bypassing a front guard |
| Ember Staff | **FIREBALL** | Planted | A burning orb that bursts for 80 damage in a 3 m blast |
| Bone Staff | **BONE SPEAR** | Planted | A spectral lance at 180% that impales three bodies |
| Buckler (off hand) | **HEADBUTT** | Walks | A boss-first head shove that damages and staggers the front arc |
| Kite Shield (off hand) | **SHIELD CHARGE** | Walks | A shield-first drive that bowls over the front arc |
| Tower Shield (off hand) | **GROUND SHIELD SLAM** | Walks | A ground slam that damages and staggers everything within 2.9 m |

Barrage, volley and piercing shots solve both bow arms from a data draw curve, so every shot visibly reaches full draw and releases on its cue. The greatsword spin turns the visual model a full turn while the data-ring damages all around; replicas derive the same turn from the ability clock. The spin now runs in a **third of its old time — 0.3166667 s** — with a presentation-only `wind` cue at **0.06 s** and the damage `ring` cue at **0.16 s**, so the beats crowd the start of the turn. The arming-sword **LUNGING THRUST** travels **three times as far**: **0.24 s** at **405%** of the 5.5 m/s walk (about **22.3 m/s**, **5.34 m**), woken by a takeoff `dash` cue at **0.0** and followed by the thrust `arc` at **0.42 s**. The dash sweeps a **1.35 m / 170°** lane every tick and damages each body it passes through once for **68.4** (the arming sword's 1.8x), sharing that victim set with the final thrust so nothing is hit twice; a gold ground ribbon, a dust plume, skid smears, afterimage wisps and speed streaks trail the dash. Arena, delve and the open world validate the action on the host and replicate the active ability, cooldowns and animation through the existing actor snapshots; effect cues are clock-driven on every peer, and only the host applies damage and projectiles. The three shield skills present the disc ahead of the body: the disc's plane is pushed clear of the chest, head and legs and the left arm is solved onto it, so a clip that draws the hand back cannot pull the boss through the torso or the helmet.

**Bow skills turn the body onto the live crosshair** before the shot, and every arrow leaves along that line with the authored spread, so an off-axis target is solved by facing it rather than by floating the pose. The arming sword's **LUNGING THRUST**, the buckler **HEADBUTT** and the kite **SHIELD CHARGE** do the same before their committed step, so the dash lands where the player is pointing rather than where the body happened to be facing. The dagger's **BACKSTAB** needs a body under the crosshair within **8 m**: it preflights that target, teleports the ranger behind it at **0.20 s** inside a large black charcoal smoke cloud (roughly **4 m** wide and **3.6 m** tall, built from **130** soft billboards that last about **0.8 s**; the ranger is clear of it by about **0.7 s**), then plunges for double dagger damage (**28**) at **0.50 s** in a 0.9 s skill, bypassing a raised front guard. The blink lands behind the foe's back, so a front guard never covers the hit.

**1 (without Shift) always equips the selected bow; 2 always equips the selected sword; 3 equips the single dagger; 4 equips or stows the shield; 5 toggles dual wield; TAB toggles the bound quick-swap pair. No number key changes size.** The equipment paperdoll's main and off hands determine the starting kit for a session; these keys then change only the current match, while TAB reads and writes the persistent pair in every mode. **I** is the backpack and **P** is the equipment paperdoll in all three modes. The shield is legal with **any one-handed sword or the dagger**, including the shortsword; switching to a greatsword, staff, bow or dual wield stows it. Mail reduces incoming damage by 15%, plate by 30%; mixed sets add the pieces actually worn. The town's keepers and stash are the only places to buy or store gear; the arena portal and the delve hatch are the two other ways out of town.

## Running slide

In both Frontier and Arena, **hold Shift while moving, then press C** to slide. The character must already be sprinting on the ground: standing still, walking, exhaustion, rolling and attached cover cannot trigger a running slide.

The slide starts at **10.5 m/s**, slows to crouch speed over **0.75 seconds**, and finishes crouched. Releasing WASD or Shift preserves its momentum; WASD allows limited steering without reversing direction. It uses the normal collision capsule, lowers the camera, and shows a low, planted slide pose instead of cycling running steps. Sprint stamina consumption continues during the slide, and holding Shift cannot automatically repeat it.

Press **C** again to cancel and stand when headroom permits. **Space** jumps and **Shift + Space** rolls out of the slide, also requiring standing clearance. Blocked forward travel or leaving the ground ends the slide; death, respawn and returning to camp clear it. Grounded attacks still work, and sliding grants no invulnerability. Arena derives slide eligibility and movement on the host and replicates the pose to other players.

## Quick steps

**Q** and **E** perform a grounded side step left or right relative to the camera. The step covers about **2.95 m in 0.30 s**, spends **7 stamina**, and enters a **0.55-second cooldown**. It is not a roll and grants no invulnerability. A step cancels a held bow draw, a melee swing, a throw or a guard, exits sticky cover, and ends immediately if the feet leave the ground. The character keeps the facing it had before the step: the hips and shoulders rotate into the travel while the head stays on the target, the leading foot reaches out and lifts, and the trailing foot braces. Q and E no longer draw, attack or interact; **G** interacts with the campfire, waystones and the Sunken Delve hatch inside the Wayfarer Inn.

`playtest/sidestep_lab.tscn` opens an isolated plaza for tuning this move: a facing tree, a metre grid and a measured trace of the last step. Launch it with **`playtest/Sidestep Lab.cmd`** or run the scene directly. It uses the real `Archer` and `DodgeStep` code; only the camera and the test props are local to the lab.

## Cover movement and shoulder views

Both Frontier and Arena use the same geometry-driven cover movement. Stand within **1.35 m** of a tree trunk, wall, stone barrier or solid debris and press **F**. The character approaches with normal collision, faces away from the surface, and stays attached while you look around freely. **WASD** slides along the surface at **2.2 m/s**; hold **Shift** to slide at **4.2 m/s**, spending stamina with normal exhaustion rules. Both speeds work while crouched. Contiguous rounded, faceted and compound surfaces can be followed without treating collider-shape seams as cover edges. Genuine edges, hard corners and unsupported ground still stop movement. Decorative meshes without collision and the ground are not cover.

**X selects the left or right lookout**; the HUD shows **LEFT LOOKOUT**, **RIGHT LOOKOUT** or **TOP LOOKOUT** when exposed. Hold **RMB** to look out. Low cover uses a standing top peek; tall or rounded cover uses the selected side. The controller chooses the shortest supported, capsule-safe step with a clear firing corridor: **0.45 m**, extending to **0.55 m** or **0.65 m** only when the geometry requires it. A wide object may require sliding to its flank first. Trees, rotated props and convex rocks use the same clearance checks, not object-specific exceptions.

Lookouts keep one protected anchor and one selected destination through hold and return. Free look and button release do not silently switch the physical side; a new request or explicit X swap captures a new view frame. Ground-supported capsule sweeps follow slopes instead of treating floor contact as a wall, and a small floor-recovery displacement cannot leave the return latch stuck. Authored top/left/right poses follow actual exposure. The camera retains swept-volume collision during shoulder changes. Shoulder selection does not change weapon handedness.

**C** toggles manual crouch on the ground, in or out of cover; it never changes armor. Crouching lowers the camera, skeleton and collision capsule together. Starting a melee skill cancels the crouch first: the capsule stands when there is headroom, then the authored clip plays. Authored crouch idle and stepping animations support attached movement at both slide speeds, including curved surfaces. Side peeks preserve crouch; a top peek temporarily rises, then restores the tucked posture. Outside cover, crouched movement is **2.2 m/s** and Shift does not sprint. Leaving with **F** preserves manual crouch. Standing waits for clear headroom rather than expanding the capsule through a ceiling.

**LMB attacks directly out of cover; RMB is not required.** A bow draw automatically exposes over low cover or around the selected edge. Releasing early freezes charge while the character finishes exposing and raising the bow, then fires exactly once. The character retucks after follow-through. Blocked edges and insufficient headroom reject bow exposure rather than storing a shot that fires later.

**Melee breaks sticky cover immediately.** A valid sword click releases attachment and starts the normal swing without waiting for a peek, including at the solid middle of a tall wall. You can move away from the wall during the attack and remain detached afterward; press **F** to attach again. The exit does not teleport, force standing, or clear manual crouch. Cooldown, airborne and rolling restrictions still apply, and a rejected attack does not detach you. The blade still collides with world cover; attacking does not allow damage through walls.

A draw begun during a manual RMB peek leaves that peek under manual control: release RMB to retuck without canceling the held draw; releasing the bow afterward exposes again before firing. Holding RMB keeps the manual peek after a bow attack finishes; it cannot reattach a melee attacker. Cover releases check the visible arrow shaft from nock to tip, including an initially buried nock. A genuinely obstructed shaft cancels its pending shot instead of firing through the obstacle or storing a latent release. Clear shots follow the center crosshair ray: the physics arrow starts at a validated point on that ray, and the rendered shaft blends from the bow tip to the authoritative path over 0.12 s. If that camera-ray point would be buried in the cover the character is posted against, the shot keeps the rendered tip rather than firing through geometry. Actual projectile collisions still block obstacles.

**Space** and **Shift + Space** leave cover, clear manual crouch and attack/peek intent, then jump or roll; insufficient standing headroom blocks takeoff. Cover grants no invulnerability. Cancellation, equipment changes, death, respawn and returning to camp clear pending attacks. Arena remains host-authoritative: clients send validated movement, lookout context, crouch intent and the snapshot used to sample aim—not trusted collider sizes or cover positions. Remote releases wait for a fresh aim sample from the current exposed pose, without adding charge. Lost input cancels automatic/frozen cover intent, so it cannot fire later when input resumes.

## Bow charge, damage and re-nocking

Aiming behaves like a shooter: the camera turns with the mouse and the crosshair stays in the center. There is **no auto-fire, unit lock-on, target tracking, or automatic gravity compensation**. Hold left mouse to draw and aim; release to launch one arrow along the current crosshair aim. Holding at full draw never fires automatically. Arrows still fall under gravity after launch, and only actual collision applies damage.

Both shoulder views aim at the world point under the crosshair, independently of the character's previous facing. Aim queries start at the character's view-height plane and skip the shooter and only the cover body you are posted against. Raising or turning the bow cannot make the query skip a nearby target. Arrows launch along the exact center-crosshair ray instead of converging from the bow tip, and the visible shaft blends from the bow to that ray over 0.12 s, so shoulder swaps and bow poses cannot bend the trajectory. Arrows still fall under gravity and collide normally.

```text
arrow damage = bow base damage × clamp(draw amount, 0, 1)
```

Zero draw gives zero damage, half draw gives half damage, and full draw gives full damage. Armor applies its normal reduction afterward. Arrow flight and world obstruction use real swept physics collision. Full-draw arrows leave at **66 m/s**, **84 m/s** and **102 m/s** for the shortbow, recurve and longbow; partial draws scale speed from 45% to 100%.

Hits in the animated **head zone** deal **double damage**; body hits keep the base value. The zone follows the head joint through crouch, cover lean and rolls. It applies to arena players and bots plus the frontier wolf and cinder devil, and the multiplier is resolved before armor. A blade that sweeps through the head zone also doubles, even when the shape query reports the contact elsewhere; the zone is a damage volume on the normal body capsule, not a second collider.

The charge bar and bowstring animation fill together over the bow's full draw duration, including raising the bow. Release whenever you want: a large bow held for **1.5 seconds deals 50% damage**; holding it for 3 seconds gives full damage.

| Bow | Full draw duration | Full damage before armor |
| --- | --- | --- |
| Small | 1 second | 30 |
| Medium | 2 seconds | 38 |
| Large | 3 seconds | 50 |

There is **no separate bow attack cooldown**. Every release, even at zero or partial draw, plays a 0.28-second follow-through followed by 0.95 seconds to fetch and nock the next arrow. You can start drawing again as soon as that animation finishes. The HUD shows **NOCKING NEXT ARROW** during recovery. Changing weapons, bow size, movement or canceling cannot skip or restart re-nocking. Canceling an unreleased draw does not spend its arrow. Walking and running do not slow charging or re-nocking; you can move while aiming. New attacks cannot begin while airborne or rolling.

The draw hand uses a cheek-surface landmark on the imported head. Bow raising, shoulder retrieval and re-nocking follow reachable paths outside the torso; the bow is brought in front of the centreline while loading. Geometry regressions check the forearms against the actual skinned outfit, not just whether the bones remain connected.

## Thrown weapons

Hold **T** with a sword or dagger equipped to charge a throw, then release to hurl the weapon. Throwing reuses the bow's attack shape: the crosshair aim is the flight line, damage is multiplied by the actual charge, and a release spends a **0.28-second** follow-through plus **0.95 seconds** of recovery before another throw, swing or draw can start. Holding at full charge never throws automatically.

```text
thrown damage = weapon base damage × clamp(charge, 0, 1)
```

Charge time follows the equipped weapon's own attack duration: **1 / 2 / 3 seconds** for the shortsword, arming sword and greatsword, and **0.5 seconds** for the dagger. Full damage is the weapon's normal melee base damage (30 / 38 / 50 for swords, 14 for the dagger), halved at half charge and zero at zero charge. A thrown weapon falls under the same gravity as an arrow, uses swept physics collision, stops on the first world or body contact, and applies the normal **2x head-zone** multiplier before armor. It cannot be parried as melee; it uses the projectile damage path.

The hand weapon leaves the hand for the release frame and the **endless supply** restores the same equipped weapon as recovery begins. Throwing does not remove gear from the paperdoll or backpack. **T never replaces melee**; left mouse and the wheel still perform the normal sword or dagger attacks. Throws automatically expose from cover like a bow, and a wall between the hand and the aim line cancels the throw rather than passing the weapon through cover. In the arena the host owns the thrown projectile, its damage and its replication; clients only send the charge/release intent and aim.

## Swords and jump-rolls

Standard sword attacks are fast, descending **diagonal crowd-cleaves**: **0.60 / 0.78 / 1.02 seconds** for the shortsword, arming sword and greatsword. Larger weapons cut a wider arc with longer reach. Explicit overheads retain their **1 / 2 / 3-second** authored timing; precision stabs remain **0.5 seconds**, and throw charging is unchanged.

| Input | Swing | Path |
| --- | --- | --- |
| LMB | Diagonal cut from the camera shoulder | Cock the blade up and behind the striking shoulder, unwind the hips then the chest, and cut down across the front into a low opposite-side follow-through. Right shoulder starts right-to-left; left shoulder starts left-to-right. Subsequent cuts alternate; X resets the next side to the selected shoulder |
| Wheel up | Forward stab | The authored dagger thrust clip drives a **0.5-second** sword thrust down the crosshair line, with a short windup and fast recovery |
| Wheel down | Overhead chop | The original authored one-hand or greatsword overhead load and downstroke |

Melee has no held charge: each click starts one attack, never a held-button repeat. Every diagonal runs a **four-phase kinetic chain**: **0-30% wind-up** (both feet stay planted in the stance the attack started in — the swing pivots over them instead of stepping — weight settles onto the back foot, the pelvis coils about 27 degrees and the chest twists to roughly 50 degrees, and the weapon lifts out of the carry it is already in — out and up, never presented forward first — until the hands cock behind the striking shoulder while the free off hand reaches forward for balance), **30-45% release** (the hips snap first, the chest follows, the right shoulder drives past the left, the elbow leads and the wrist snaps through the apex), **45-65% follow-through** (the chest leans about 15 degrees forward into the strike over the planted feet — never back — the hilt crosses the body and the blade carries past the centre line to the low opposite hip while the head keeps the target in view), and **65-100% recovery** (the torso unwinds and the weapon returns to guard). The damage sector uses the same release curve as the visible arm, so contact timing and the blade agree. While moving, crouched or sliding, the pelvis stays owned by locomotion and the coil lives in Spine 01/02/03 and the right clavicle. Diagonals also sample the heavy overhead's authored leg drive, bend into the load and settle over the leading foot. Left/right cuts mirror the footwork. Wheel attacks retain their authored precision paths. A rejected local or host attack does not consume the next side; remote clients alternate dispatched attack intents without a new acknowledgement RPC.

The **dagger** (key **3**) uses the same alternating LMB diagonals, with a **0.42-second** cut, **14** base damage, **1.2 m** reach and a **150-degree** full frontal arc. Wheel up uses its **0.5-second** authored aim-directed stab; wheel down also uses that precision stab because the dagger has no authored overhead. The thrust follows the crosshair rather than auto-targeting: low aim angles toward a wolf, high aim stays high.

During the active diagonal stroke, damage sweeps a **frontal sector** in the cut's direction, rather than requiring a thin blade to touch every body. Shortsword / arming sword / greatsword reach is **1.8 / 2.1 / 2.5 m**, with full arcs of **160 / 170 / 180 degrees**. Staffs use the same damage and swing clock but a swing of their own rather than the two-handed sword's: the right hand sits just below the shaft centre and the left hand grips **0.32 m** above it, both hands drive forward as a piston, the shaft barrells through a wider arc than the hands travel, the leading end finishes ahead and low while the rear end counterweights up and behind, and the ember/bone shafts reach **1.6 / 1.5 m** (the catalog and HUD show the same values). This catches short enemies and crowds across the front while excluding targets behind or beyond reach. Every victim is checked separately against world cover, so a wall protects the target behind it without stopping the cut from hitting other visible targets. Each hand damages each victim **once per swing**, only during the active stroke, with normal **base body damage** (30 / 38 / 50 for swords, 14 for daggers)—never incidental cleave headshots. Precision stabs, authored overheads, arrows and thrown weapons retain actual-contact **2x headshots**. Guards, parries, clashes, cancellation and host-only damage remain in force. Switching weapons or rolling cancels further hits without erasing melee recovery; bow readiness stays independent.

## Dual wield

Press **5** with a one-handed sword selected and a **dagger or another one-handed sword in the paperdoll's off hand**. The off-hand piece determines the left weapon and its profile; the mode requires the small shortsword or medium arming sword in the right hand, so the greatsword leaves dual wield. A raised shield is stowed when dual begins, and the shield cannot be raised while dual wielding.

Left click performs **diagonal_left** with the left-hand weapon; right click performs **diagonal_right** with the right-hand sword. Both face the crosshair and use the equipped hand's diagonal timing, reach, arc and base cleave damage: an off-hand dagger uses **0.42 s / 14 damage / 1.2 m**, while an off-hand sword uses its corresponding sword profile. Scroll up stabs and scroll down performs the authored overhead with the right-hand sword; these remain precision attacks with headshots. **T** still throws the right-hand sword.

**Recovery is per hand.** You can start either hand while the other winds up, strikes or recovers; the freed hand can attack again when its own action completes. While the right sword is active it drives the body animation, with the left cut layered on the same skeleton. The HUD shows **LEFT** and **RIGHT** percentages (or **READY**). A standard block knocks aside only the contacting hand; a parry staggers and cancels both.

**Dual wield has no guard.** RMB never raises a block, and a shield cannot be raised. Instead, an attack inside its active strike window parries a front melee hit: no damage and the attacker is staggered for **0.8 s**. Windup, recovery, a hit from behind, or any non-dual attack does not parry. The attack parry does not stop the dual wielder's own swing, and there is no stamina cost.

## Guarding, parries and clashes

Equip a sword with **2** or the dagger with **3** and hold **RMB** while grounded and ready to guard. The character faces the camera, stops rotating with movement, and does not regenerate stamina while guarding. A hit from the front resolves from the guard timer and weapon, not exact blade geometry:

| Outcome | Trigger | Result |
| --- | --- | --- |
| Parry | Block began at most **0.25 s** before the hit | No damage. The attacker is staggered for **0.8 s**, leaving a guaranteed counter-hit. |
| Standard block | Guard held longer than **0.25 s** before the hit | No damage, **22 stamina** spent, and the defender is pushed slightly away. The contacting hand resets; a dual wielder's other hand keeps swinging. |
| Weak dagger block | Any hit into a raised dagger | **Half damage** still applies, **30 stamina** spent, no parry, and the attacker's swing continues. |
| Shield block | Any front hit into a raised shield | **No damage**, **18 stamina** spent, the defender is pushed back, and no parry is possible. |
| Attack parry | Dual wield and the strike is inside its contact window and facing the attacker | No damage and the attacker is staggered for **0.8 s**; the dual wielder's swing continues. No stamina cost. |
| Unblocked | Guard down, wrong facing, rolling, attacking outside a dual strike window, or no weapon | Normal damage applies. |

The **shield** (**4**) is a physical off-hand item carried on the left arm and legal with the dagger or any one-handed sword, including the shortsword. Holding RMB raises it in front of the chest and head, overriding the dagger's weak guard or the sword's parry timing with a **full front block**. The shield is a moving collision body in both modes: an arrow that hits it — raised or merely carried, whether it came from a player bow, a cinder devil's bow or a ranger clone — deals **zero damage** to the player and **sticks into the shield**. An arrow that reaches the body still deals damage and **sticks into the player** where it landed. Stowed shields are hidden and inert; switching to a bow, greatsword, staff or dual wield automatically stows the shield.

Releasing RMB drops the guard; pressing an attack while guarding also drops it. Dual wielders cannot guard at all: RMB attacks with the right-hand sword instead, and defense comes from the timed attack parry above. Guarding pauses stamina recovery, so repeated blocks cannot be turtled for free, and a guard with insufficient stamina still spends what remains. The held pose is a dedicated character-only animation: `Sword_Block_Loop_OneHand` for the dagger, short and arming swords, and the two-handed `Sword_Block_Loop` for the greatsword. Both are **120-sample / 1.983-second** breathing loops with planted feet; the greatsword's support hand stays on the actual hilt. These clips animate the Ranger rig only; the held weapon remains the normal socketed runtime model, and the lower-body crouch/slide layer does not overwrite the guard arms.

If two **sword** users are in their active downstroke at the same time and facing each other, their blades **clash** instead of trading damage: sparks and a loud clang, zero damage in both directions, a small bounce apart, and both swings reset so either fighter can immediately act again. A clash never uses an exact sword-to-sword contact test; simultaneous active hit-frames plus mutual facing are sufficient. A dagger never clashes; it can only weak-block and must rely on its speed and short recovery.

The character uses a 65-bone skinned humanoid and authored animation clips. The greatsword has a genuine two-handed overhead load, accelerating downward cut, whole-body weight transfer, closed hilt grip, follow-through and recovery. Short/medium swords use a separate authored one-handed overhead. Source motions are retargeted and grip/timing corrections baked in Blender. Overheads and stabs keep their authored elbows; diagonal cuts pose the striking and support arms at runtime over the authored body, cocking high and behind the shoulder, then finishing low across the front. The staff is socketed by its middle with both hands spaced around the shaft centre, so both ends sweep during standard cuts and the guard; the authored overhead and thrust slide to an end grip over their wind-up so the long shaft stays clear of the floor and head. The textured character and environment remain stylized, not photorealistic rendering.

**Shift + Space** starts a tucked forward tumble and directional burst immediately, either from the ground or during a jump. Space alone only jumps; double-tapping it never rolls. Knees and elbows fold, the chin tucks, the weapon stays clear of the torso, and landing compresses the legs before returning to the normal stance. Running or strafing direction takes priority over facing. Only one roll is allowed before landing; it does not grant invulnerability or ignore world collisions.

[In-engine authored sword, bow, movement and roll preview](media/motion-preview.mp4)

Authored walk, jog and sprint clips follow actual movement speed with a continuous gait phase. The sprint includes knee/heel recovery, flight, body lean and alternating arm drive. Bow aiming and terrain contact use skeletal corrections; the greatsword keeps a coupled two-hand carry. Collisions that stop movement also stop the running gait.

## Multiplayer feel

Remote fighters use **snapshot interpolation** rather than chasing the newest packet. Each replica buffers timestamped host snapshots and renders **0.12 s** behind them, blending position between the two samples that bracket the render time. The local client seat uses a shorter **0.05 s** delay. If packets are late, the last authoritative velocity carries the body for at most **0.15 s**, then it holds instead of inventing a long extrapolation. Teleports and respawns snap and clear the buffer.

Every hit spawns a **scrolling world-space damage number** that rises, drifts and fades; headshots are larger and gold, damage you take is red, and lethal blows are orange. Arena clients derive the number from the authoritative health delta in each snapshot, so all peers see it without a new network message.

Taking damage rolls an **attack interruption** against the share of max health the hit removed. A hit under **5%** never breaks a swing; a hit at **50%** or more always does; the chance ramps linearly between, so three small enemies can be traded through while a heavy hit lands with weight. A landed roll staggers for `0.08 s + 1.2 s × damage share of max health`, capped at **0.62 s**. The victim's movement input, guard, draw, throw and swing are interrupted, the torso and head recoil visibly, and the cap still leaves a counter window. A shrugged-off hit still rocks the pose and cancels a consumable but leaves the swing running. The recoil replicates through the animation phase as `STAGGER` without adding a snapshot field.

Fighters no longer hard-collide with each other. Their capsules have a **soft separation** that only pushes when centres are inside **0.46 m**, which lets two players close to stabbing distance without being shoved off their aim. World geometry, cover, blades and projectiles still collide normally.

The title menu and arena lobby remember the **last player name, host address, UDP port and join mode** in `user://net_cache.json`. Joining a game updates the cache after validation, and the next form opens with those values.

## Performance

A monster no longer pays for a physics step. The frontier's terrain is an analytic height field and its props are marked in a square-metre navigation grid, so a mob's next step is a few array reads instead of a **~90 µs** `move_and_slide` — the single largest cost a busy frontier frame used to carry. Mobs keep their collision shape on the hit layer, so blades, arrows and spells still find them.

Mobs also think on a **stride**: every second physics tick inside 22 m, every fourth out to 55 m, every twelfth beyond, with the decimated tick scaling `delta` so speeds, cooldowns and the sight memory stay in real time. A mob's rig is freed past **58 m** and rebuilt when its body comes back inside **45 m**; between those two the body keeps drawing and animating, and a visible rig samples at thirty hertz, so a body walking away never vanishes from the middle distance. The camera pass that hides offscreen rigs runs on the rendered frame — after the camera has moved — and tests a **2 m bounding sphere**, so turning onto a monster shows it on that frame instead of up to a quarter second later. Spacing reads a shared square-metre bucket grid instead of scanning every wilderness mob.

Press **F8** in any scene for the live frame diagnostic: fps and frame time, the worst frame and 1% low of the recent window, the engine's process and physics clocks, draw calls and primitives, scene and memory counts, the frontier's live/skipped/rigged/drawn mob split, and the profiler's heaviest scopes with their share of the frame.

Mob snapshots travel as **fifteen floats** (68 bytes) instead of a nine-key dictionary (244 bytes): 133 mobs in view ship in ~11 datagrams a send instead of 35, which is a third of the upload and the difference between a host on a home connection keeping up and dropping the snapshots that own the smoothness. The sun's shadow range is **60 m**, which still covers every weapon's useful range and the whole town square.

`tests/perf_suite.gd` measures all of it — the shipped frontier, thirty monsters spawned at once, a hundred fighting around an invulnerable ranger, and the host's replication path — and `docs/performance.md` records the numbers, the method and what is left. `tests/mob_cull_regression.gd` guards the camera cull on the real frontier: it turns the camera onto and away from live bodies and checks the frame the rig appears or hides on, that the 2 m sphere keeps a body just past the frustum edge in view, and that a host never culls by its own camera.

## Blood and wounds

This is an 18+ game: unmitigated damage now leaves persistent gore. **Every mob bleeds** — the Briar wolf, cinder devil packs, the five imported devils and the delve devils all take body stains, floor spatter and a death pool; the ranger does too. A real contact throws a spray of droplets from the wound, flings smaller drops onto the ground and walls around the victim, speckles the floor beneath it, soaks blood into the victim's clothes, and marks the attacker: a drawn blade takes a coating, a claw, paw or muzzle takes a soak on the limb that struck, and an arm's-length melee kill throws the victim's blood back over the killer's chest and face. Lethal blows add an arterial burst and a growing pool under the corpse that stays for as long as the body does. Blocked, parried and weak-blocked hits draw no impact spray; only weak blocks still leave the half damage's wound. A defeated body then **lies where it fell for five minutes** (`scripts/corpse_hold.gd`) holding its authored death pose, before a short dissolve frees it.

Blood is laid on the garment, not beside it. `scripts/blood_surface.gd` measures a rig once — every visible skinned-mesh vertex is binned into its dominant bone as a radial profile of the cloth around that bone — and keeps a thinned sample of the whole garment. A wound scatters several textured splashes across that measured strip, then uses the current pose to find the **outermost** layer under each splash and lifts it clear, so a belt, a sleeve cuff or a second armour layer cannot swallow the stain. The Sunken Delve's primitive depth roles are measured as their own triangles instead. Patch samples clamp to the measured strip, so a stain never rings the air past a cuff or the crown (the old extrapolation drew red "feathers" off hoods), and the cloth soak is a small ragged core with round satellite droplets rather than one large splat. An arrow carries only a short wet smear behind its head, never a blade-sized coating. Stains ride the nearest skeleton bone, so they travel with the limb.

Stains last **60 seconds**, then fade over the final three and are released — except for death pools. A lethal blow pools blood under the body, adds two lobes draining out past the corpse and keeps creeping outward for a few seconds; that pool holds for **five minutes**, the same clock as the corpse lying in it, and lives in its own **60-pool** budget so the sixty-second spatter recycling can never erase the pool a body is resting in. Surface spatter follows slopes and steps because each patch is conformed to the real collision surface, and weapon blood is parented to the drawn weapon so it moves through every swing. A scene owns at most **160 surface stains** and **10 wounds per fighter** (8 per weapon); the oldest stain is recycled first when a large fight exceeds that budget. Blood is presentation only — it never changes damage, hit detection or network authority, and a hit that applies no damage spawns none.

The project renders with the **GL Compatibility** backend, which has no decal support, so blood does not use `Decal` nodes: `scripts/blood_fx.gd` owns procedural splat, pool and soaked-cloth textures plus their materials, `scripts/blood_surface.gd` measures garments and builds conformed patches, and the per-scene `scripts/blood_field.gd` owns stain lifetime, weapon coatings and capped particle bursts. The first blood event on a rig costs a one-off ~30 ms measurement; later wounds are single-millisecond work. The host spawns blood where it applies damage; arena and delve clients derive wounds and the weapon-blood tally from the snapshot health delta and `weapon_blood` field, so all peers see the same result without a dedicated network message.

## Game modes

**Hearthstead / Open PvE:** the main world. New games start at the south gate; walk north into the square. The town has enterable houses, three keeper counters, the market stash chest, the arena portal, the campfire and the delve hatch. Beyond the safe ring lie forest, a ruined fortress, an upland shrine, trails and the bridge. Defeat wolves and cinder devil packs, clear defenders and restore three waystones. Gold from foes and waystones enters the same purse immediately, and defeated enemies drop physical gear that is picked up into the backpack. Death returns you to the town gate with restored health; restored waystones stay restored for the session.

**Arena:** a 64 × 64 metre woodland free-for-all with a wide spawn ring, flank trees and stone islands around the centre cover, four combatants, simple pursuit/attack bots, score tracking and three-second respawns. Bots use the same damage and attack paths as players. Step into the **Arena Portal** in town to host a local match on the first free UDP port from 7777; the main menu's **Join Game** connects to a host. `Arena.cmd` still opens the standalone lobby, whose **Return to Town** button loads Hearthstead.

**The Sunken Delve:** a host-authoritative, endless survival run beneath the town, reached by **falling through the hatch in the Wayfarer Inn**. The floor cell is physically open; jump in and the scene hands off as you drop. The party falls onto the landing of the **sanctuary**: a 15 m stone chamber with a central dais, pillars, barricades and four dark archways, and no gates. Walk to the **altar** and press **G**; a five-pointed **pentagram** ignites on the dais, and a 3.2 s ritual of light columns, embers and point-orbs plays. Then **10 enemies — a three-imp and two-devil ladder plus the five starting-court devils** — spawn from random points all over the room across 30 seconds, scheduled from the lightest body to the heaviest, so the room opens on imps and closes on the heavyweights; the spawn times are still weighted toward the back end of the window. Every wave, cycle one included, fields one of each **starting-court devil** from the frontier — the hellish goat man, succubus, devil spawn, hell beast and gargoyle — scattered through the schedule in their authored rigs and claw cadence, at a court scale (`0.45 ×` frontier health, `0.65 ×` damage) so the first wave stays a first wave; health, damage and speed still grow with depth. Every wave after the first adds five more bodies — **10, 15, 20, 25, 30, 35 ...** — and the **crimson clones** enlist from the **third wave** on — one on wave three, one more each wave up to four — always closing the schedule. Clear them and the cache appears after a short delay, a **rope drops from the ceiling**, and a **floor plate opens**; glowing, shimmering **beacons** label the altar, the rope (`ROPE OUT`) and the hatch (`DESCEND`) so every choice is obvious. Open the cache for gold (`40 + 30 × depth`) plus a 10% chance of one deterministic piece from a depth-scaled loot tier, climb the rope to return to town, or drop through the floor into the **Ossuary Pit**: a claustrophobic, organic charnel with a lower ceiling, rib-arc walls, stacked-skull niches, bone totems, gore pools and bone-dust floor. It starts the moment every delver lands — the summoning continues for **15 enemies — a six-imp and four-devil ladder plus the same five court devils**. Clear it and the rope and hatch return. Dropping again returns to a **new instance** of the sanctuary (odd depths) and then the ossuary (even depths), each cycle with a fresh room palette, more enemies and heavier devils. Health, damage and chase speed scale with depth. There is no fixed wave count and no resume checkpoint — the loop is the run. `Host Tailscale.cmd` starts the town in delve-host mode, so the same hatch opens a hosted party on UDP 7777; friends choose **Join Game → Delve party**.

**Cinder devil packs:** ember-skinned horned devils, **2.11 m to the crown**, with claws and ember eyes. **Five packs (20 devils)** hunt the frontier: a mixed five-devil pack in the glade north-west of the camp beyond the safe ring, a three-devil pack in the western woods, and four-devil packs in the northern woods, the southern meadow and the ridge approach. Each pack mixes roles: **claw**, **dagger**, **short sword** and **bow**. They do not charge in a straight line: they orbit at different radii and directions, leap, slide, and make quick half-distance side steps (**1.48 m in 0.22 s**) to reach a flank. Melee devils dive in with a telegraphed strike; bow devils kite at range and release real arrows, aiming with a small ballistic lead. Up to **three** pack members commit to an attack at once, and attacks come faster than the first pass. All devils have **24 health** and award **6 gold**; claw hits deal **8** (**10** on a landing pounce), daggers **6**, short swords **11**, and bow arrows **7**. The head zone rides the authored skull, and headshots still double damage.

**Mob aggression and sight:** every wilderness mob — wolves, sentinels, cinder devil packs, the five devils and the three Unholy Forest mobs — decides whether it is in a fight with its eyes. `scripts/mob_senses.gd` owns the one rule set. Aggression begins only when a ranger stands inside a **140° forward cone** within the profile's sight range (23 m for the legacy wolf and sentinel, 30 m for the cinder devil, 18–32 m per devil/forest profile) with an unobstructed chest-or-head line of sight, so terrain, props and tree trunks hide a ranger and a mob's back is blind. That blind side is what makes sneaking work: walk up behind an unaware mob and the dagger's backstab lands at double damage.

Losing sight never calls the fight off. A mob keeps hunting the last place it saw (or was struck by) its quarry for **15 s** and only then walks home, so stepping behind a tree or a rock no longer resets aggro. Any landed blow names its attacker through `note_attacker` — arrows, thrown weapons, spells, blades and the backstab all report it — and a mob turns on that archer even when the shot came from behind cover; the same cry reaches every mob within **12 m**, so shooting one beast of a pack brings the rest. The town's 19 m safe ring overrides all of it: nothing inside is hunted, however it was provoked.

## World art

The frontier and arena are dressed by a small, data-driven world-art kit rather than per-scene primitives:

- **Textured sky.** A photoreal 4096 × 2048 equirectangular panorama (`assets/world/textures/sky_frontier.png`) supplies the sky background: a Rayleigh-like blue gradient, a real-sized sun disc and aureole at the key light's exact direction, a perspective cumulus deck with self-shadowing, thin cirrus and aerial haze. Fog, ambient light, filmic grade and saturation are tuned to it.
- **Textured terrain.** The continuous heightfield keeps its authored routes and clearings, but now renders through a world-space splat shader: grass, trail dirt and rock/scree textures blended by vertex dirt weights and slope, with low-frequency macro variation. Grass clumps, wildflowers and ferns are chunked alpha-cut cards that sway in the wind and fade out at their visibility range.
- **Textured trees.** A species library builds deterministic mesh variants: oaken trunks with real branches and leaf-card crowns, layered briar pines, slim silver birches, amber rowans and bare snags. Bark and leaf textures are separate authored PNGs with normal maps and per-instance tint, so one mesh family yields many colours and silhouettes. Sizes, species weights and shape parameters live in code, not in the mesh files.
- **Textured props.** Boulders, pebbles, village timber, plaster, roof shingles, bridge timbers and stonework share triplanar materials. The pond uses a ripple normal map and a cheap sky-tinted fresnel shader.

Everything is batched into per-chunk `MultiMesh` instances with explicit AABBs and visibility ranges. Grass and leaf cards use alpha scissor (no sorting), cast no grass shadows, and vary tint per instance; there is no per-frame scenery script. Measured on the development machine at 1280 × 800 with the GL Compatibility renderer (uncapped, GTX 1080), the frontier holds about 155 FPS at the village and 270 FPS in dense forest, drawing roughly 720k and 704k visible primitives. The previous flat-colour primitives drew about 1M primitives at roughly 196 / 376 FPS; the extra draw calls come from shadowed alpha foliage. The arena is far lighter at about 280 draw calls and 46k primitives.

### Editing the world look

`scripts/world/` contains the re-usable kit:

| File | Responsibility |
| --- | --- |
| `world_style.gd` | Data for the frontier and arena: sky/grade, ground textures and tints, tree species, grass/cover densities, prop tints. Add a species here or append one at runtime. |
| `tree_kit.gd` | Seeded trunk/branch/foliage mesh generation for the four tree forms. |
| `texture_library.gd` | Cached texture loading and shared materials/shaders. |
| `scatter.gd` | Chunked MultiMesh batching with instance colours and visibility ranges. |
| `grass_field.gd` | Grass, flower and fern placement with slope/reserved-area rejection. |
| `environment_kit.gd` | Panorama sky, fog, ambient, tonemap and sun/shadow setup. |
| `shaders/` | Foliage, grass, terrain, arena-ground and water shaders. |

To add a tree species, append a dictionary to `WorldStyle.default_trees()` (or to a scene's cloned style) with `id`, `form` (`broadleaf`, `conifer`, `birch`, `snag`), bark and leaf texture ids, height range, trunk/crown ratios, tint pools, wind and variant count. `TreeKit` and `WorldScatter` do the rest. The frontier scatters species by the weights in that list.

All world textures are original procedural work generated by `tools/world_textures.py` (Python + numpy + Pillow, deterministic). Regenerate and reimport after changing the generator:

```powershell
python tools/world_textures.py
& $Godot --headless --editor --path . --import
```

The manifest is `assets/world/world_textures.json`; provenance and the CC0 dedication are in `assets/world/LICENSE.txt`. World textures import lossless with mipmaps (they are alpha-scissored cards and tiled ground/bark surfaces, so mipmaps are required and block compression is intentionally disabled).

## Devil court

Five imported devil-themed mobs inhabit the frontier outside Hearthstead: the **Hellish goat man** (jet-black armorless goat demon with empty skull sockets and black horns/hooves), **Succubus** (half-open-wing, black-horned raider), **Devil spawn** (low skittering nest-hunter), **Hell beast** (heavy quadruped brute) and **Gargoyle** (carved stone brute with ember-slit sockets, a fanged muzzle, crown horns, half-raised bat wings and a spiked spine). Their placements are authored in `RangeWorld.devil_spawns`, deliberately separate from the legacy 36-entry `enemy_spawns` contract. Five of the sixteen spawns form a starting court inside the town’s safe ring — one of each species, about 10 m ahead of the south-gate spawn — so all five can be inspected immediately without aggro.

**Crimson ranger clones:** four patrols hold the outer frontier trails, and from **cycle two** three to four join every delve wave. Each clone wears the player Ranger rig **heavily tinted crimson-black** with its own random paperdoll — a rolled main hand (any bow, sword, dagger or staff), an optional shield or focus, and a mixed armor set per slot — so no two read alike. They fight like the arena bots rather than the mobs: **bow beyond nine metres, blade inside it**, strafing and keeping range, leading their arrows, switching targets, and reacting to an incoming swing with a raised guard or a quick side step. Their armor reduces damage like a player's, they can be parried, and they drop the main-hand weapon they rolled when they fall.

They are built from the same licensed CC0 Quaternius sources as the ranger — the male/female bases, ranger outfits, long hair and 65-bone animation library — with original devil anatomy and paint on top. No generated image, photogrammetry scan or restricted file is used. Each mob is one imported GLB with:

- a real skinned Quaternius body (the goat deliberately uses no ranger outfit) or the original Briar wolf for the beast, plus authored goat skull, horns, clean membrane wings, tails, claws, fangs, hoof boots, fur and stone spikes;
- source PBR skin, leather, hair and eye maps (2048/1024 px) tinted while retaining pores, grain and iris detail, plus authored bone, horn, membrane, stone and fur maps;
- six baked 60 Hz clips: idle, walk, run, attack, hit and death, using the ranger/wolf authored locomotion and time-warped attacks;
- extra `head`/`jaw`, wing and tail bones where the silhouette needs them.

The result is the ranger's authored PBR quality on a demon silhouette rather than a procedural blob.

`scripts/devil_mob_visual.gd` is presentation only: it samples the clips, scales cadence from actual post-collision movement, and maps the physics attack clock onto the authored impact frame. `scripts/devil_mob.gd` owns the shared state machine, per-mob profiles, collision, damage, parries/staggers, gold, blood and the five-minute corpse hold. The existing frontier loot rotation and HUD feedback are unchanged.

The full authoring workflow, budgets and gates are documented in [docs/devil-mobs.md](docs/devil-mobs.md). Rebuild all five assets with:

```powershell
python tools/build_devils.py all
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/devil_mobs_regression.gd
```

Tinted source maps, authored PBR maps, preview renders and capture sheets are written to the ignored `.runtime/devil-source/<mob>/` workspace; source archives stay in `.runtime/character-source/`. Keep each shipped GLB, its adjacent JSON and its `.glb.import` together; import settings embed the textures and sample animation at 60 Hz.

### The Cinder devil (original route)

The **Cinder devil** is the sixth devil and takes the **original route** — no
download. The CC0 Quaternius archives that the five mobs above rebuild from are not
present in a clean checkout, so `tools/prepare_cinder_devil.py` authors it from
nothing. That script imports `tools/prepare_forest_mobs.py` and rebinds its
`styles`/`surfaces`/`SEED`/`FPS` globals to `tools/cinder_devil_styles.py` and
`tools/cinder_devil_surface.py`, so rig building, skinning, the per-material
atlas bake, clip baking, export and captures are literally the Unholy Forest
code path rather than a fork.

It ships as `assets/characters/devils/ironwood_cinder_devil.glb` plus its
adjacent JSON: **43,366 triangles, 38 bones, eight `Cinder_*` materials, 26
embedded images, 2.242 m to the horn tips** (the crown is 2.11 m), soles at
y 0.007 and no root drift. Seven baked 60 Hz clips — `Cinder_Idle` (2.200 loop),
`Cinder_Walk` (0.900 loop), `Cinder_Run` (0.617 loop), `Cinder_Attack` (0.800,
impact 0.380), `Cinder_Shoot` (0.550, release 0.300), `Cinder_Hit` (0.367) and
`Cinder_Death` (0.900) — on a stationary root. `scripts/cinder_devil_visual.gd`
is its presentation-only sampler; the frontier pack AI stays in `enemy.gd`
kind 2. The **Sunken Delve's** four primitive depth roles (imp, devil,
bonefiend, brute) keep `scripts/devil_visual.gd` and `delve_regression.gd`
asserts they stay primitive.

```powershell
python tools/build_cinder_devil.py
& $Godot --headless --path . --script res://tests/devil_regression.gd
```

Ignored intermediates land in `.runtime/cinder-source/cinder_devil/`; keep the
shipped GLB, its JSON and its `.glb.import` together.

## Unholy Forest

Three mobs own the woodland outside Hearthstead: the **Hollow warden** (hooded
grave-cloth atop a hole in the world, two ember eyes and a branching antler rack
growing out of its crown), the **Ossuary stalker** (a hooded human in a fitted
sackcloth tunic and torn skirt — carved bone mask with empty black sockets,
antlers lashed to a brow band) and the
**Gallowsroot** (a big man in a long tattered coat with bark plates strapped over
it, a carved wooden mask with an ember slit, branches lashed to a brow band, bark
mitts and boots). Their placements live in
`RangeWorld.forest_spawns`, a third table beside the legacy 36 `enemy_spawns` and
the 16 `devil_spawns`. Three of the nineteen spawns sit inside the town's safe
ring about 14 m ahead of the south gate, so all three are inspectable at once and
stay idle until the ranger leaves the ring.

They are **original procedural work**, not source-based: `tools/prepare_forest_mobs.py`
authors every mesh, rig and clip in Blender, and `tools/forest_surface.py`
rasterises seven analytic PBR surfaces (bark, cloth, bone, antler, moss, void and
the emissive ember) into per-material UV atlases, so fissures, weave and bone
grain are continuous across seams and carry texel-scale detail. No third-party
model, texture or motion is used and nothing has to be downloaded to rebuild them.

Each mob ships one imported GLB with a real skinned mesh (30k / 49k / 47k
triangles), six baked 60 Hz clips (idle, walk, run, attack, hit, death) with a
stationary root and planted-foot locomotion solved with two-bone leg IK, and its
own measured JSON. `scripts/forest_mob_visual.gd` is presentation only and maps
the physics attack clock onto the authored impact frame; `scripts/forest_mob.gd`
reuses the devil state machine through its virtual profile/group/visual hooks, so
there is one AI, not two.

The same set supplies the **Makeshift** starter gear: the salvage armour the
ranger begins in — bone over cured hide, matching the stalker's kit, with a bone
antler helm, a hide vest under bone rib bars, hide bracers with bone knuckle
spikes, hide leggings with bone knee cops and hide boots with bone toe caps —
and the salvage blades the smith sells beside the forged kit (a knapped flint
cleaver and a ground-rib shiv). Makeshift is set index 4 in
`scripts/armor_data.gd`; five sets need three bits per slot, so
`ArmorData.PIECE_MASK` and `ArmorData.SHIELD_BIT` are one shared contract across
the HUD, the arena, the delve and host-authoritative snapshots.

The workflow, budgets and gates are documented in
[docs/forest-mobs.md](docs/forest-mobs.md). Rebuild with:

```powershell
python tools/build_forest.py all
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/forest_mobs_regression.gd
```

Captures and baked atlases land in the ignored `.runtime/forest-source/<mob>/`
workspace. Keep each shipped GLB, its adjacent JSON and its `.glb.import`
together; the import settings embed the textures and sample animation at 60 Hz.

## Update

**Close every running game instance, including the host, before updating.** Godot keeps loaded scripts in memory; pulling changes does not update an already-running match. Current windows show **0.4.0** in the HUD, and `Play.cmd` opens the main menu.

```powershell
git pull --ff-only
.\Setup.cmd
.\Play.cmd
```

## Development and tests

`assets/characters/ironwood_ranger.glb` contains the skinned character and authored clips, including the one- and two-handed held guard loops; its adjacent JSON records source timing, guard targets/support clearance and weapon/palm transforms. `scripts/archer.gd` samples these animations on the physics clock, applies bow/terrain corrections, and emits blade sweeps from the same pose used to render the sword. `assets/characters/ironwood_wolf.glb` is the original textured Briar wolf: a continuous skinned quadruped with a 37-bone rig, deterministic grey coat and in-place idle, trot, bite and death clips. `scripts/wolf_visual.gd` samples them and maps the 1.5 s bite to gameplay's 0.65 s impact and 0.85 s recovery; `enemy.gd` keeps AI, collision, damage and the corpse lifetime authoritative. `scripts/cinder_devil_visual.gd` samples the imported Cinder devil GLB's seven clips; `_step_devil` in `enemy.gd` owns the orbiting pack AI, dives, the three-attacker cap and shared `DodgeStep` side steps, and the Sunken Delve's primitive depth roles keep `scripts/devil_visual.gd`. `tests/devil_regression.gd` covers that split. `combat.gd` handles authoritative swept contact, independent sword recovery and bow readiness. `dodge_roll.gd` owns explicit Shift + Space roll state. `main.gd` controls the frontier; `arena.gd` and `arena_actor.gd` implement authoritative ENet multiplayer and replicas. World and weapon geometry remain runtime-generated.

`cover_movement.gd` owns acquisition, supported capsule sweeps, contiguous-surface sliding, bounded firing-corridor search and latched lookout/retuck state. The single authoritative cover snapshot contains physical stance and world-space `lean`; animation snapshots do not duplicate it. `archer.gd` layers the authored pose before foot/weapon corrections. `Combat` checks the actual shaft before a cover release; melee still clears cover before its first swing pose. Arena aim samples carry the observed own-actor snapshot tick, and remote release waits for the current exposure epoch before applying the unchanged shaft collision check. Regressions exercise left/right tree shots, convex and compound cover, slopes/recovery, side swaps/free look, blocked shafts, malformed/stale aim stamps, cancellation, melee exits and observer replication.

Standard melee uses a dedicated **world-only occlusion ray**; camera projectile-lane checks include fighters and never share that query. This prevents normal crosshair aiming from turning a victim into its own melee blocker. `swing_reach_regression.gd` covers that aim-to-attack transition, mirrored frontal crowds, point-blank and short targets, weapon/staff reach, a 40-enemy cleave, thin walls, guards, cancellation and one hit per victim. Rendered checks exercise actual frontier clicks, while `network_input_regression.gd` verifies the remote greatsword's single authoritative base-damage hit.

`paperdoll_regression.gd` drives the equipment system: the ten slots and every-weapon starter kit, item taxonomy and legal-slot rules, right-click routing, the two-handed main/off override and its backpack/floor overflow, the off-hand override that returns a two-handed main to the backpack, dual-wield routing, ring slots, drops and floor pickups, a full backpack rejecting loot, version-4 save round-trip with floor items and version-1/2/3 migration, the TAB quick-swap pair and its BIND SWAP path, a cinder devil's held-shortsword ground drop, rig loadouts for bow, staff, focus, shield, dual and empty hands with middle-grip staff reach matching the catalog, and the in-world paperdoll's ten slots, panel containment, live-rig equipping and right-click unequip. Script-mode tests start from the authored defaults instead of a player's real save.

Repo-local skills provide step-by-step instructions for coding and asset-authoring agents:

- [Ironwood Archer](.omp/skills/ironwood-archer/SKILL.md): gameplay, controls, shared animation/combat, multiplayer, verification and safe restarts.
- [Ironwood Assets](.omp/skills/ironwood-assets/SKILL.md): sourcing/licensing, new models, UVs, PBR textures, Blender export, Godot import and material isolation.
- [Ironwood Creatures](.omp/skills/ironwood-creatures/SKILL.md): character anatomy, skeletons, skinning, authored animation, the wolf-overhaul workflow, and independent size/coat variants.

OMP discovers these at session startup. Invoke `/skill:ironwood-assets` and `/skill:ironwood-creatures` for a character task, or ask an agent to read those files explicitly. The default grey wolf overhaul is implemented (`assets/characters/ironwood_wolf.glb`, `scripts/wolf_visual.gd`, `tools/prepare_wolf.py`); small/medium/big and black/grey/white variants remain a separate requested expansion.

Run the behavior regressions after setup:

```powershell
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/rig_regression.gd
& $Godot --headless --path . --script res://tests/draw_combat_regression.gd
& $Godot --headless --path . --script res://tests/projectile_regression.gd
& $Godot --headless --path . --script res://tests/gameplay_regression.gd
& $Godot --headless --path . --script res://tests/melee_roll_regression.gd
& $Godot --headless --path . --script res://tests/action_pose_regression.gd
& $Godot --headless --path . --script res://tests/arm_clearance_regression.gd
& $Godot --headless --path . --script res://tests/weapon_input_regression.gd
& $Godot --headless --path . --script res://tests/network_input_regression.gd
& $Godot --headless --path . --script res://tests/cover_movement_regression.gd
& $Godot --headless --path . --script res://tests/wolf_regression.gd
& $Godot --headless --path . --script res://tests/devil_regression.gd
& $Godot --headless --path . --script res://tests/devil_mobs_regression.gd
& $Godot --headless --path . --script res://tests/swing_reach_regression.gd
& $Godot --headless --path . --script res://tests/running_slide_regression.gd
& $Godot --headless --path . --script res://tests/block_clash_regression.gd
& $Godot --headless --path . --script res://tests/hitbox_regression.gd
& $Godot --headless --path . --script res://tests/title_menu_regression.gd
& $Godot --headless --path . --script res://tests/town_services_regression.gd
& $Godot --headless --path . --script res://tests/paperdoll_regression.gd
& $Godot --headless --path . --script res://tests/world_ui_regression.gd
& $Godot --headless --path . --script res://tests/throw_regression.gd
& $Godot --headless --path . --script res://tests/world_art_regression.gd
& $Godot --headless --path . --script res://tests/delve_regression.gd
& $Godot --headless --path . --script res://tests/delve_entry_regression.gd
& $Godot --headless --path . --script res://tests/delve_network_regression.gd
& $Godot --headless --path . --script res://tests/world_network_regression.gd
& $Godot --headless --path . --script res://tests/net_prediction_regression.gd
& $Godot --headless --path . --script res://tests/open_world_combat_regression.gd
& $Godot --headless --path . --script res://tests/open_world_delve_regression.gd
& $Godot --headless --path . --script res://tests/ranger_clone_regression.gd
& $Godot --headless --path . --script res://tests/consumable_regression.gd
& $Godot --headless --path . --script res://tests/blood_regression.gd
& $Godot --headless --path . --script res://tests/corpse_regression.gd
& $Godot --headless --path . --script res://tests/ability_regression.gd
& $Godot --headless --path . --script res://tests/weapon_abilities_regression.gd
& $Godot --headless --path . --script res://tests/backstab_regression.gd
& $Godot --headless --path . --script res://tests/trinkets_regression.gd
```

`python tools/run_tests.py` runs the full suite in parallel with isolated `APPDATA` per test, unique fixed UDP ports and a fixed simulated clock for the two long deterministic tests; it retries a timing failure once.

`blood_regression.gd` checks the 60-second stain lifetime and fade, surface/body/weapon coverage, projectile and melee hooks, the per-rig and per-scene budgets, and the bleed path for the cinder devil, the five imported devils and the claw-armed attackers. `corpse_regression.gd` checks that a wolf, a cinder devil, an imported devil and a delve devil all outlive the old four-second free, stop blocking collision while still catching the world, and dissolve through the shared five-minute hold. It also checks the death physics: a rigged wolf, imported devil and delve species build a Godot physical-bone ragdoll under `scripts/corpse_physics.gd`, get an attack-style force from `scripts/impact_rules.gd`, fall onto the floor without folding their torso into a pile or spinning the head, settle and bake their limp pose, while a procedural delve devil killed in the air still obeys gravity through the dead CharacterBody root. `ability_regression.gd` checks the item-granted definitions, the shortbow Barrage grant, both hand slots, trivial stamina spend, cooldown swap reset, cue timing, the 1000-stamina pool, rejection cases, the packed ability index across animation/snapshot replication, the snapshot budget, the Shift + 1 / Shift + 2 frontier bindings, both HUD slots, the backstab sound and the hosted arena cue landing real damage. `weapon_abilities_regression.gd` covers all twelve catalog weapon/shield skills, their effect data and icons/sounds, the `move` feet rule (a held walk continues through a move-enabled melee skill and stops dead for a bow cast, on both a host arena fighter and the frontier ranger), the long lunge's 5.34 m lane that cuts a near and a far body once each without the closing thrust landing again, the 0.3166667 s spin and its crowded 0.06/0.16 cues, radial/arc/block/blast damage, the fireball and bone-spear projectiles, Barrage and piercing end-to-end damage, the off-axis bow that turns the body onto the live crosshair, the backstab blink behind the aimed body with its 28 damage, the spin dust ring and the MTU budget. `backstab_regression.gd` checks the crosshair target preflight, the behind-the-back landing spot, the blink and the guard-bypassing strike on a frozen arena rig. `ability_regression.gd` checks the item-granted definitions, the shortbow Barrage grant, both hand slots, trivial stamina spend, cooldown swap reset, cue timing, the 1000-stamina pool, rejection cases, the packed ability index across animation/snapshot replication, the snapshot budget, the Shift + 1 / Shift + 2 frontier bindings, both HUD slots, the backstab sound and the hosted arena cue landing real damage. `weapon_abilities_regression.gd` covers all twelve catalog weapon/shield skills, their effect data and icons/sounds, the `move` feet rule (a held walk continues through a move-enabled melee skill and stops dead for a bow cast, on both a host arena fighter and the frontier ranger), the long lunge's 5.34 m lane that cuts a near and a far body once each without the closing thrust landing again, the 0.3166667 s spin and its crowded 0.06/0.16 cues, radial/arc/block/blast damage, the fireball and bone-spear projectiles, Barrage and piercing end-to-end damage, the off-axis bow that turns the body onto the live crosshair, the backstab blink behind the aimed body with its 28 damage, the spin dust ring and the MTU budget. `backstab_regression.gd` checks the crosshair target preflight, the behind-the-back landing spot, the blink and the guard-bypassing strike on a frozen arena rig.

`delve_regression.gd` checks the endless loop: the fall-in start, the sanctuary altar phase, the pentagram ritual, the cycle-one **10-enemy** wave (three imps, two devils, all five court devils and no clones) from random spawn points, its lightest-to-heaviest schedule, the delve's bandage/potion keys and heal, the wave ramp to the cycle-two twenty with the first crimson clone joining last (imported rig, court-scaled health, complete head and strike anchors), the clear delay, cache spawn, rope and floor-hole beacons, chest rewards, the Ossuary Pit's 15 enemies, depth-three sanctuary recycling with a new palette, and the rope return to town. `ranger_clone_regression.gd` covers the frontier's four clones: red-black tint, random main hands and armor, the arena-bot range discipline, the guard reaction, a real bow release, the one-time reward and corpse, and both snapshot shapes. `delve_entry_regression.gd` drives the town gate, the physical inn hatch fall, the arena portal host, and the rope return to `main.tscn`. `delve_network_regression.gd` runs two real ENet processes: a client joins the altar, both see the ritual, room, wave and cache, the client builds the species and clone replicas, and both observe the descent into the ossuary. `world_network_regression.gd` runs two real ENet processes for the open world: the host opens the town/frontier, the client joins seat one, both mobs and rangers replicate, the client's weapon/jump/melee intents drive its host-authoritative ranger, damage and health reach both peers, the host's mob arrow and loot drop appear on the client, every client mob is a host-driven replica, and the seat is freed when the client leaves. `open_world_delve_regression.gd` runs two real ENet processes through the hatch hand-off: the host lifts a rider who drops into the hatch alone back onto the inn floor, then the host's fall keeps the same ENet peer and port, the connected client follows into the delve without reconnecting, both delvers are seated, and the client keeps its role and name.

`world_ui_regression.gd` drives the in-world **I/P kit** in the real delve and arena scenes. It checks that **I** opens the backpack and frees the cursor, that **P** opens the paperdoll, that an equip updates `PlayerState` and the live rig (`Archer.apply_loadout`), that `Escape` closes the kit and recaptures the mouse, and that arena drops fall back to the persistent ground list. `town_services_regression.gd` walks the PvE town: the three keeper counters, the stash chest, the arena portal, the open hatch cell, the town-gate spawn, I/P panel switching, vendor buying, stash transfers and unarmed world drops. `title_menu_regression.gd` covers Start New Game, Load Saved Game, the disabled-load state and the cached Join form.

### Rebuilding character assets

The bundled Ranger model and motions are **CC0**: Ranger/base characters and locomotion by [Quaternius](https://quaternius.com/), with the two-handed heavy attack by [Gres](https://opengameart.org/content/humanoid-soulslike-animations). The Briar wolf is original procedural work authored by `tools/prepare_wolf.py`; it is not derived from those sources. Exact source files, extraction ranges, wolf measurements and modifications are recorded in [the asset provenance](assets/characters/LICENSE.txt). No paid pack or game account is needed.

To re-author the assets, install Blender 5.1+, download and unpack the listed free sources into `.runtime/character-source`, then run:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python tools/prepare_character.py -- .runtime/character-source assets/characters/ironwood_ranger.glb
& $Godot --headless --editor --path . --import
```

Keep the GLB, adjacent JSON/provenance, and `.glb.import` settings together. Import settings preserve authored clip names, use 60 Hz animation sampling, and keep textures embedded rather than duplicating extracted PNGs. The preparation workflow preserves the authored striking arm and body motion, corrects support-hand proportions and clothing clearance, and smooths the one-handed cut's timing. `tools/character_clearance.py` validates interpolated support-arm motion against the deformed outfit before export is accepted.

`tools/prepare_consumables.py` imports the shipped GLB and merges the authored **3.0-second `Bandage_Wrap`** and **0.5-second `Potion_Drink`** clips into the original document, leaving every existing node, skin, mesh and animation untouched.

The same rebuild imports `Crouch_Idle_Loop` and `Crouch_Fwd_Loop` from the existing Quaternius source and authors `Cover_Lean_Top`, `Cover_Lean_Left` and `Cover_Lean_Right` in Blender, plus the **0.5-second** `Dagger_Stab` thrust and the two held guard loops. The three 0.24-second lean clips share an idle reference, with planted feet and unchanged local arm poses for weapon layering. JSON records their asset-space directions, the stab's contact window and the crouch clip's measured stride estimate; runtime cadence follows actual movement rather than requested speed.

Optional Godot MCP tooling is pinned under `tools/`; run `npm ci --ignore-scripts` there if needed. Local MCP configuration, engine binaries, imports, caches and logs are excluded from Git. They are not required from the original development machine.

Godot is downloaded separately under its [MIT license](https://godotengine.org/license/). [Official engine release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Archery stance reference: [World Archery recurve technique](https://extranet.worldarchery.sport/documents/index.php/Media/Information_Sheets/003_Guide_to_Recurve_Technique.pdf).
