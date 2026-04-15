# Roblox CCG: Implementation Spec v4
## Snap-Inspired Positional Card Game

---

## How to Use This Document

This is both a game design spec and a build guide. It is written to be read by both you (a human with no Roblox experience) and Claude Code (an AI coding agent that will write the actual Lua scripts). The document is structured so that you can hand it directly to Claude Code as a prompt and it will have enough detail to build each phase.

**Your workflow will be:**
1. Read this document to understand what you're building.
2. Set up Roblox Studio (instructions below).
3. Prompt Claude Code to read this spec and build Phase 1.
4. Take Claude Code's output and put it into Roblox Studio.
5. Test, fix issues, move to the next phase.

---

## Before You Start: Setup

### Install Roblox Studio

1. Go to https://create.roblox.com and create a Roblox account (or log in if you have one).
2. Download and install **Roblox Studio**. It's free. It runs on Windows and Mac.
3. Open Studio. You'll see a templates page. Choose **Baseplate** — this gives you an empty world with a flat ground. This is your starting project.
4. Save the project: File → Save to Roblox As → give it a name like "Card Game Prototype." This saves it to Roblox's cloud. You can also File → Save to File to keep a local copy.

### Learn to Navigate Studio (5 minutes)

Roblox Studio looks overwhelming at first. You only need to care about a few panels:

- **Explorer** (usually right side): This is the file tree. It shows every object in your game, organized into folders called "services." Think of it like a project directory. You'll spend most of your time here.
- **Properties** (usually below Explorer): When you click any object in the Explorer, its settings appear here. You'll rarely edit these directly — Claude Code will handle it through scripts.
- **Output** (usually at the bottom): This is the console log. When something goes wrong, error messages appear here in red. This is your primary debugging tool.
- **Viewport** (the big center area): This is the 3D world view. You can fly around using WASD + right-click drag. For this project, the 3D world is secondary — most gameplay happens in UI overlays.

If any of these panels are missing, go to View menu at the top and enable them.

### Install Rojo (Recommended)

**What Rojo does:** Claude Code writes Lua scripts as files on your computer. Rojo watches those files and automatically syncs them into Roblox Studio. Without Rojo, you'd have to manually create script objects in Studio and paste code into each one — which is slow and error-prone.

**How to install:**
1. Install Rojo via: `cargo install rojo` (requires Rust) or download the latest release from https://github.com/rojo-rbx/rojo/releases
2. Install the Rojo plugin in Roblox Studio: open Studio → Plugins tab → Manage Plugins → search "Rojo" → Install.
3. Claude Code will generate a `default.project.json` file that maps your file tree to the Studio Explorer hierarchy.
4. In your project folder, run `rojo serve` from the terminal. In Studio, click the Rojo plugin button → Connect. The two are now synced — saving a .lua file on disk instantly updates the corresponding script in Studio.

**If you skip Rojo:** Claude Code will still produce .lua files. You'll need to manually create the corresponding script objects in Studio (right-click a service → Insert Object → ModuleScript/Script/LocalScript) and paste the code from each file. The spec tells you exactly where each script goes.

---

## Roblox Concepts You Need to Know

Roblox uses its own architecture and terminology. Here's what matters for this project, explained from scratch.

### The Client-Server Model

Every Roblox game has **one server** and **multiple clients** (one per player). The server is the authority — it runs the game rules, stores the true game state, and tells clients what's happening. Each client is one player's screen — it renders graphics, takes input, and sends actions to the server.

**Why this matters for a card game:** The server runs the match logic (shuffling, turn resolution, scoring). The client runs the UI (showing cards, handling tap input, playing animations). They talk to each other through messages called RemoteEvents. When a player taps "Confirm," the client sends a message to the server. When the server resolves a turn, it sends messages to both clients with the results.

**Critical rule:** Never trust the client. A player could theoretically hack their client to send false messages ("I played a card I don't have" or "I have 99 energy"). The server must validate every message and reject anything illegal.

### Services (Where Scripts Live)

In the Explorer panel, you'll see a tree of "services" — these are the top-level folders of a Roblox project. The ones you care about:

- **ServerScriptService**: Scripts here run ONLY on the server. Players can't see or modify them. Put all game logic here: the match engine, validation, scoring. Scripts here are `Script` objects (not LocalScript, not ModuleScript used alone).
- **ReplicatedStorage**: Files here are visible to BOTH the server and all clients. Put shared data and utilities here: card definitions, location definitions, game config, ability registry. Files here are typically `ModuleScript` objects — reusable code that other scripts can import.
- **StarterPlayerScripts**: Scripts here are copied to each player's client when they join. Put client-side code here: the match UI, input handling, animations. Scripts here are `LocalScript` objects.
- **StarterGui**: GUI objects (ScreenGui) placed here are automatically copied to each player's screen when they join. Your match interface will be a ScreenGui here.
- **ReplicatedStorage** (also used for RemoteEvents): You'll create RemoteEvent objects here. These are the "communication channels" between client and server. When the client fires a RemoteEvent, the server can listen for it, and vice versa.
- **Workspace**: The 3D world. The baseplate floor is here. Eventually the hub world goes here. For the prototype, you don't need much in Workspace.

### Script Types

- **Script**: Runs on the server. Has full authority. Use for game logic.
- **LocalScript**: Runs on a client (one player's machine). Use for UI and input.
- **ModuleScript**: Doesn't run on its own. It's a library that other scripts import via `require()`. Can be used by both Scripts and LocalScripts (if placed in ReplicatedStorage). Use for shared code: card data, config, utility functions.

### The Luau Language

Roblox uses **Luau**, a variant of Lua. If you've never seen Lua:
- Variables: `local x = 5`
- Tables (like dictionaries/objects): `local card = { name = "Spark", cost = 1, power = 2 }`
- Functions: `local function add(a, b) return a + b end`
- No classes — use tables and metatables (Claude Code knows how to do this)
- Arrays are 1-indexed (the first element is `[1]`, not `[0]`)
- Comments: `-- this is a comment`

You don't need to be fluent in Luau. Claude Code writes the code. You need to be able to read error messages in the Output panel and understand roughly what the code is doing when debugging.

### How RemoteEvents Work

This is the most important Roblox-specific concept for this game.

A RemoteEvent is a named message channel sitting in ReplicatedStorage. Here's the pattern:

**Client → Server (player submits their turn):**
```lua
-- In LocalScript (client side):
local submitEvent = game.ReplicatedStorage:WaitForChild("SubmitTurn")
submitEvent:FireServer(myPlays)  -- sends data to server

-- In Script (server side):
local submitEvent = game.ReplicatedStorage:WaitForChild("SubmitTurn")
submitEvent.OnServerEvent:Connect(function(player, plays)
    -- 'player' is automatically provided — you always know WHO sent it
    -- 'plays' is the data the client sent
    -- Validate and process...
end)
```

**Server → Client (server sends turn results):**
```lua
-- In Script (server side):
local revealEvent = game.ReplicatedStorage:WaitForChild("RevealResult")
revealEvent:FireClient(player1, resultData)  -- sends to one specific player
revealEvent:FireAllClients(resultData)        -- sends to ALL players

-- In LocalScript (client side):
local revealEvent = game.ReplicatedStorage:WaitForChild("RevealResult")
revealEvent.OnClientEvent:Connect(function(resultData)
    -- Animate the results...
end)
```

That's the entire communication model. Every interaction between client and server in this game goes through RemoteEvents.

---

## Project Structure

This is the exact file layout for the prototype. If using Rojo, this maps to your filesystem. If working manually in Studio, create these objects in the Explorer panel.

```
game
├── ReplicatedStorage
│   ├── Modules
│   │   ├── GameConfig          (ModuleScript) — all tunable parameters
│   │   ├── CardDatabase        (ModuleScript) — card definitions
│   │   ├── LocationDatabase    (ModuleScript) — location definitions
│   │   ├── AbilityRegistry     (ModuleScript) — ability keyword → function mapping
│   │   ├── SlotGrid            (ModuleScript) — adjacency and grid utilities
│   │   └── CardFrame           (ModuleScript) — shared card rendering component
│   └── Events
│       ├── TurnStart           (RemoteEvent)  — server tells clients a new turn began
│       ├── SubmitTurn          (RemoteEvent)  — client sends plays to server
│       ├── RevealResult        (RemoteEvent)  — server sends resolution results
│       ├── ScoreUpdate         (RemoteEvent)  — server sends updated scores
│       ├── GameOver            (RemoteEvent)  — server announces winner
│       ├── InvalidPlay         (RemoteEvent)  — server rejects a play with reason
│       ├── RequestBotMatch     (RemoteEvent)  — client requests a bot match
│       └── RequestMatch        (RemoteEvent)  — client requests PvP matchmaking
├── ServerScriptService
│   ├── MatchManager            (ModuleScript) — the game engine (turn loop, validation, resolution)
│   ├── BotPlayer               (ModuleScript) — AI opponent logic
│   └── GameServer              (Script)       — the entry point that listens for match requests
│                                                 and creates MatchManager instances
├── StarterPlayerScripts
│   └── MatchClient             (LocalScript)  — handles UI interaction, sends input, receives results
├── StarterGui
│   └── MatchGui                (ScreenGui)    — the UI container (frames, labels, buttons)
│                                                 MatchClient populates this at runtime
└── Workspace
    └── HubWorld                (Folder)       — 3D environment (Phase 4, not needed for prototype)
```

**What Claude Code produces:** Lua files for every ModuleScript, Script, and LocalScript listed above. Claude Code should also produce a Rojo project config (`default.project.json`) if you're using Rojo.

**What you create manually in Studio (if not using Rojo):**
- The RemoteEvent objects in ReplicatedStorage/Events (right-click → Insert Object → RemoteEvent, rename to match)
- The ScreenGui in StarterGui (right-click → Insert Object → ScreenGui, rename to "MatchGui")
- The folder structure in ReplicatedStorage (right-click → Insert Object → Folder, rename to "Modules" and "Events")

Claude Code's scripts will reference these by name using `WaitForChild()`, so the names must match exactly.

---

## How to Test Your Game

### Method 1: Studio Local Server (Two-Player Testing)

1. In Studio, go to the **Test** tab at the top.
2. Find the "Players" dropdown — set it to **2**.
3. Click **Start**. Studio opens three windows: one Server window and two Client windows (one for each simulated player).
4. Each Client window shows what that player sees. You play both sides by switching between them.
5. The **Output** panel in the Server window shows server-side prints and errors. Each Client window has its own Output for client-side messages.
6. Click **Stop** (red square) to end the test.

**Use this for:** Verifying the state machine works, checking that RemoteEvents fire correctly, seeing both players' views side by side.

### Method 2: Play Against Bot (Solo Design Testing)

Once the bot is implemented in Phase 2:
1. In Studio, set Players to **1** and click Start.
2. The single client interacts with a "Play vs Bot" button in the hub (or a test trigger).
3. The server creates a match with you as Player 1 and the bot as Player 2.
4. You play normally. The bot makes its moves automatically.

**Use this for:** Evaluating pacing, card balance, energy curve, and fun factor.

### Method 3: Published Private Game (Real Multiplayer Testing)

1. In Studio: File → Publish to Roblox. This uploads your game.
2. Go to the Game Settings (Home tab → Game Settings). Under Permissions, set it to **Private**.
3. Under Permissions → Collaborators, add the Roblox usernames of your playtesters.
4. Share the game link. Only people you've added can join.
5. You and a friend join from the Roblox app (not Studio) and play a real match.

**Use this for:** Actual multiplayer experience testing, latency feel, mobile device testing (have a friend play on their phone).

### Reading the Output Panel

The Output panel is your lifeline. When something breaks:
- **Red text** = error. Read the message and the script name/line number. Copy the error and ask Claude Code to fix it.
- **Orange text** = warning. Usually non-critical but worth checking.
- **White text** = print statements. Claude Code should add strategic `print()` calls in the MatchManager so you can trace turn flow: "Turn 3 started," "Player1 submitted 2 plays," "Resolving OnReveal for HEALER at location 1," "Scores: P1=8, P2=6."

**Tip for Claude Code prompts:** When something breaks, copy the exact error message from Output and paste it into Claude Code. Include which phase you're on and what you were doing when it broke. Claude Code can usually diagnose and fix Roblox errors from the error message alone.

---

## Prompting Claude Code: Phase-by-Phase Guide

### Before Any Phase

Give Claude Code this entire spec file as context. Say something like:

> "Read this game design spec. We're building a Roblox card game. I'm a novice to Roblox Studio and Luau. I'm using [Rojo / manual script creation]. Build Phase 1 — all the ModuleScripts in ReplicatedStorage. Generate complete, working Luau code for each module. Include print statements for debugging. [If using Rojo: Also generate the default.project.json Rojo config for the full project structure.]"

### Phase 1 Prompt

> "Build Phase 1: Create the GameConfig, CardDatabase, LocationDatabase, AbilityRegistry, and SlotGrid ModuleScripts. Include all 30 cards from the starter card pool and all 10 locations. The AbilityRegistry should have working resolver functions for every ability keyword used by the starter cards. Include unit-test-style print functions I can call to verify the data is correct (e.g., print all cards at cost 3, print adjacency map for slot (2,1), resolve a test ability)."

**What you'll get:** Five .lua files. Put them in ReplicatedStorage/Modules.

**How to verify:** In Studio, create a temporary Script in ServerScriptService that does:
```lua
local CardDB = require(game.ReplicatedStorage.Modules.CardDatabase)
print(CardDB["SPARK"].name, CardDB["SPARK"].power) -- should print "Spark 2"
```
Run the game. Check Output. If it prints correctly, Phase 1 is working.

### Phase 2 Prompt

> "Build Phase 2: Create the MatchManager ModuleScript, the BotPlayer ModuleScript, and the GameServer Script. The MatchManager should implement the complete turn loop from the spec — simultaneous submission, validation with overwrite support, card placement, On Reveal resolution in the correct order, Ongoing recalculation, per-turn scoring, and win detection. The BotPlayer should make heuristic plays as described in the spec. The GameServer should listen for RequestBotMatch and create a match with one real player and one bot. Include detailed print statements tracing every step of every turn. I need to be able to read the Output panel and follow the entire game flow."

**What you'll get:** Three .lua files. Put them in ServerScriptService.

**How to verify:** At this point, you can't play yet (no UI). But you can test the engine by having GameServer auto-start a bot-vs-bot match and watching the Output trace a complete game: turns advancing, cards being played, abilities resolving, scores changing, and a winner declared.

### Phase 3 Prompt

> "Build Phase 3: Create the MatchClient LocalScript and the MatchGui ScreenGui. The MatchClient should handle the full match UI as described in the spec — two locations with 3x2 grids, the hand display, energy counter, score display, tap-to-select card placement with overwrite support, pending card visuals, confirm button, reveal animations, and the end-of-game screen. Use the CardFrame ModuleScript for rendering cards. For the prototype, card art should be colored rectangles with the card name as text. Connect to all RemoteEvents. Include a 'Play vs Bot' button on screen to start a bot match (fires RequestBotMatch). The UI must work on both desktop (mouse clicks) and mobile (touch taps)."

**What you'll get:** A LocalScript and possibly a ScreenGui setup script. The ScreenGui may need to be created manually or via script.

**How to verify:** Set Players to 1, click Start, click "Play vs Bot." You should see the board, your hand, and be able to play a full game against the bot. This is the moment the prototype is alive.

### Debugging Tips

- **"Infinite yield possible on..."** means a script is waiting for an object that doesn't exist. Check that all RemoteEvents are created and names match exactly (case-sensitive).
- **"attempt to index nil with '...'"** means a variable is nil when the script tried to use it. Usually a missing `require()` path or a misspelled key in a table.
- **Nothing happens when you click a button** means the LocalScript isn't connected to the GUI element, or the GUI element's name doesn't match what the script expects. Check names in Explorer.
- **Cards don't appear** means the CardFrame renderer is returning an invisible frame, or the GUI hierarchy is wrong. Add print statements to the CardFrame module.
- **The game freezes or the timer never runs** means the server's turn loop is stuck waiting for a submission that never arrives. Check that SubmitTurn is being fired by the client and received by the server.

---

## Core Rules Summary

This section is the single source of truth for game rules. Every system described in later phases implements these rules.

### The Board

Two locations are revealed at the start of the game and persist for the entire game. Each location has a **point value** (2–5) and an optional **effect** that modifies play at that location.

Each player has a **3-column × 2-row grid** of card slots at each location (6 slots per location, 12 total per player across both locations). Players choose exactly which slot to place each card in. Once placed, cards remain on the board unless overwritten or destroyed.

### Overwriting

A player may play a card into a slot that already contains one of their own cards. The existing card is **destroyed** (removed from the game permanently) and replaced by the new card. The new card's On Reveal ability triggers normally. The overwritten card's Ongoing effects (if any) cease immediately, and all Ongoing effects are recalculated after resolution.

Overwriting is a deliberate strategic cost — you lose the overwritten card's Power contribution and spend energy to replace it. This prevents board stalemates when all slots are full, and creates interesting decisions: is it worth overwriting your 2-Power vanilla to play a 9-Power Dragon in that slot?

Players cannot overwrite opponent cards. Only your own occupied slots are valid overwrite targets.

### Turns

The game is a continuous sequence of turns with no resets, no rounds, no phases. Everything escalates until someone wins.

**Turn structure:**

1. **Start of turn:** Each player gains +1 Max Energy (turn 1 = 1 energy, turn 2 = 2 energy, turn 10 = 10 energy — no cap, no reset). Each player draws 1 card from their deck, unless their hand is at max size (7), in which case the draw is skipped (card is NOT drawn and discarded — it stays on top of the deck). On turn 1, this is the first draw; players started the game with 3 cards in hand before any turns began.
2. **Planning phase:** Both players simultaneously choose which cards to play and where. A player may play any number of cards as long as their total cost does not exceed their current energy. A player may also choose to play nothing (pass). A countdown timer runs (default: 30 seconds).
3. **Submission:** Each player confirms their plays (or the timer expires, locking in whatever is placed — if nothing is placed, that's a pass). The client sends the server a list of plays: each play is a (cardID, locationIndex, column, row) tuple, **ordered by the sequence the player placed them**. This ordering matters for resolution.
4. **Reveal phase:** All cards from both players are placed on the board and revealed simultaneously. On Reveal abilities then resolve in a specific order (see Resolution Order below).
5. **Scoring phase:** After all abilities resolve, each location is evaluated. The player with more total Power at a location earns that location's point value, added to their running score. If Power is tied at a location, each player earns 1 point regardless of the location's point value. If a player has cards at a location and the opponent has none, the player with cards wins that location (earning its full point value).
6. **Win check:** If either player's score has reached or exceeded the point threshold, the game ends immediately. That player wins. If both players cross the threshold on the same turn, the player with the higher score wins. If scores are exactly tied, play one additional turn as a tiebreaker.

### Resolution Order

When multiple On Reveal abilities trigger on the same turn, they resolve in this order:

1. **Location priority:** The location with the higher point value resolves all its cards first. If both locations have equal point value, choose randomly at game start and keep that order for the entire game.
2. **Player priority:** Within a location, the player with the higher current score resolves their cards first. If scores are tied, choose randomly at game start and keep that order for the entire game. (This means the leading player commits first, giving a slight structural advantage to the trailing player — an intentional catch-up mechanic.)
3. **Play order:** Within a single player's plays at a single location, cards resolve in the order the player placed them during the planning phase (first placed = first resolved).

After all On Reveal effects resolve, all Ongoing effects across the entire board are recalculated from scratch.

### Key Rule: Play Order Determines Buff Timing

If a player places Card A (which has "On Reveal: +2 Power to adjacent cards") and then places Card B in an adjacent slot during the same turn, Card A resolves first. At the time Card A's ability fires, Card B is already on the board (all cards are placed before any abilities resolve). Therefore Card B DOES receive the +2 buff. However, if the player placed Card B first and Card A second, Card B's resolution (if it has an ability) happens before Card A's — so Card A's adjacency buff hasn't fired yet during Card B's resolution, but Card B would still receive it when Card A resolves afterward. In short: all cards are on the board during resolution, but abilities fire in play order and can only affect cards that are already present.

### Decks

20 cards per deck. Only one copy of any card allowed. The deck is shuffled at game start and never reshuffled. Cards played to the board remain there unless overwritten or destroyed by an ability. Overwritten and destroyed cards are removed from the game permanently.

### Starting State

- Each player's score: 0
- Each player's hand: 3 cards drawn from shuffled deck
- Max Energy: 0 (will become 1 at start of turn 1)
- Board: empty (no cards at any location)
- Both locations: revealed with point values and effects visible

### Game Length

Games are not fixed-length. They continue until the point threshold is reached. With locations worth 2–5 points scored every turn, and a threshold around 20 (configurable), games will typically last 8–15 turns. Players will see 11–18 of their 20 cards (3 starting + 1 per turn drawn). Since players can overwrite their own cards, the board never truly locks — there is always a legal play available as long as the player has cards and energy. This eliminates stalemates and ensures every turn involves a meaningful decision.

### Adjacency

Adjacency is defined only among a player's own cards at a single location. Slot positions are labeled (column, row): (1,1), (2,1), (3,1) for row 1 and (1,2), (2,2), (3,2) for row 2. Two slots are adjacent if they share an edge — not diagonals:

```
(1,1) ↔ (2,1) ↔ (3,1)
  ↕          ↕          ↕
(1,2) ↔ (2,2) ↔ (3,2)
```

So (1,1) is adjacent to (2,1) and (1,2). Center slot (2,1) is adjacent to (1,1), (3,1), and (2,2). Corner slots have 2 neighbors, edge slots have 3, and there is no slot with 4. An opponent's cards are never considered adjacent to yours. Cards at different locations are never adjacent.

---

## Starter Card Pool (30 Cards)

All cards below are placeholders with fantasy-themed names. Art assets will use solid-color rectangles with the card name for prototyping.

### 1-Cost Cards

| ID | Name | Cost | Power | Ability |
|----|------|------|-------|---------|
| SPARK | Spark | 1 | 2 | — |
| SCOUT | Scout | 1 | 1 | On Reveal: Draw a card. |
| SEEDLING | Seedling | 1 | 1 | Ongoing: +1 Power to adjacent cards. |
| EMBER | Ember | 1 | 3 | On Reveal: -1 Power to a random friendly card at this location. |
| SAGE | Sage | 1 | 1 | Ongoing: +1 Power for each other Ongoing card you control (at any location). |

### 2-Cost Cards

| ID | Name | Cost | Power | Ability |
|----|------|------|-------|---------|
| IRON_GUARD | Iron Guard | 2 | 3 | — |
| FROST_SPRITE | Frost Sprite | 2 | 1 | On Reveal: -2 Power to a random enemy card at this location. |
| LOOKOUT | Lookout | 2 | 2 | On Reveal: If your opponent played a card at this location this turn, +3 Power to this card. |
| FLAME_IMP | Flame Imp | 2 | 2 | Ongoing: +1 Power to adjacent cards. |
| MYSTIC | Mystic | 2 | 2 | On Reveal: +1 Power to all friendly cards in the same column at this location. |

### 3-Cost Cards

| ID | Name | Cost | Power | Ability |
|----|------|------|-------|---------|
| STONE_GOLEM | Stone Golem | 3 | 5 | — |
| HEALER | Healer | 3 | 2 | On Reveal: +1 Power to all other friendly cards at this location. |
| WIND_DANCER | Wind Dancer | 3 | 4 | On Reveal: Move this card to a random empty slot at the other location. |
| SABOTEUR | Saboteur | 3 | 3 | On Reveal: -1 Power to all enemy cards at this location. |
| ECHO | Echo | 3 | 1 | On Reveal: Summon a 1-Power copy of this card in a random empty adjacent slot. |

### 4-Cost Cards

| ID | Name | Cost | Power | Ability |
|----|------|------|-------|---------|
| WAR_BEAST | War Beast | 4 | 7 | — |
| COMMANDER | Commander | 4 | 4 | Ongoing: +1 Power to all other friendly cards at this location. |
| TRICKSTER | Trickster | 4 | 0 | On Reveal: Set this card's Power equal to the highest-Power enemy card at this location. |
| SHIELD_WALL | Shield Wall | 4 | 3 | Ongoing: +2 Power to all other friendly cards in the same row as this card. |
| BERSERKER | Berserker | 4 | 4 | On Reveal: +1 Power for each empty slot on your side of this location. |

### 5-Cost Cards

| ID | Name | Cost | Power | Ability |
|----|------|------|-------|---------|
| DRAGON | Dragon | 5 | 9 | — |
| STORM_MAGE | Storm Mage | 5 | 5 | On Reveal: -2 Power to all enemy cards at this location. |
| WARLORD | Warlord | 5 | 1 | Ongoing: Double your total Power at this location (applied after all other modifiers). |
| HIGH_PRIESTESS | High Priestess | 5 | 6 | On Reveal: Draw 2 cards. |

### 6-Cost Cards

| ID | Name | Cost | Power | Ability |
|----|------|------|-------|---------|
| TITAN | Titan | 6 | 12 | — |
| OVERLORD | Overlord | 6 | 8 | Ongoing: +1 Power to all your other cards at both locations. |
| VOID_WALKER | Void Walker | 6 | 10 | On Reveal: Destroy all cards with 2 or less Power at this location (both sides). |
| COLOSSUS | Colossus | 6 | 8 | Ongoing: This card's Power cannot be reduced by enemy abilities. |

### Design Notes on the Card Pool

**Vanilla cards** exist at every cost to establish a baseline Power curve: 1/2, 2/3, 3/5, 4/7, 5/9, 6/12. Any card with an ability should have less base Power than the vanilla at the same cost — the ability is what makes up the difference. This is the fundamental costing principle.

**Ability distribution:** 10 vanilla cards, 14 On Reveal cards, 6 Ongoing cards. On Reveal is the primary mechanic — it's simpler to understand ("this happens once when you play it") and creates dramatic reveal moments. Ongoing cards are fewer and create persistent board texture.

**Positional cards:** Seedling, Flame Imp, Shield Wall, Mystic, and Echo all reward specific slot placement. These are the cards that make the 3×2 grid matter and distinguish this game from Snap.

**Starter deck:** New players receive all 30 cards and a premade 20-card starter deck. Suggested starter deck (skewing toward simpler cards): Spark, Scout, Ember, Iron Guard, Frost Sprite, Lookout, Stone Golem, Healer, Saboteur, War Beast, Commander, Berserker, Dragon, Storm Mage, High Priestess, Titan, Overlord, Seedling, Flame Imp, Shield Wall.

---

## Starter Location Pool (10 Locations)

| ID | Name | Points | Effect |
|----|------|--------|--------|
| CRYSTAL_CAVERN | Crystal Cavern | 2 | No effect. |
| DRAGONS_PEAK | Dragon's Peak | 3 | No effect. |
| SUNKEN_RUINS | Sunken Ruins | 4 | No effect. |
| FROZEN_LAKE | Frozen Lake | 2 | Cards played here get -1 Power. |
| WAR_CAMP | War Camp | 3 | Cards played here get +1 Power. |
| SHADOW_NEXUS | Shadow Nexus | 3 | On Reveal abilities do not trigger here. |
| VERDANT_GROVE | Verdant Grove | 2 | At the start of each turn, +1 Power to all cards here (both players). |
| SKY_TEMPLE | Sky Temple | 4 | Only cards costing 3 or more can be played here. |
| DUELING_GROUNDS | Dueling Grounds | 3 | Each player can only use the front row (3 slots) here. |
| MANA_WELL | Mana Well | 2 | Whenever you play a card here, draw a card. |

### Location Design Notes

**Point value distribution:** Four locations worth 2, four worth 3, two worth 4. No 5-point locations in the starter pool — those are reserved for later content drops where they create high-stakes drama.

**Effect-free locations** (Crystal Cavern, Dragon's Peak, Sunken Ruins) are essential for learning. New players' first games should ideally feature at least one no-effect location. Matchmaking can bias toward simpler locations for low-rank players.

**Location pairing matters:** The two locations in a game are drawn randomly from the pool without replacement. Some pairings are more interesting than others — Sky Temple (only 3+ cost) paired with Mana Well (draw on play) creates a tension between going wide cheaply at one location vs. going tall expensively at the other. The system should eventually support curated pairing rules, but random is fine for the prototype.

---

## Sample Turn Walkthrough

This walkthrough demonstrates one complete turn of gameplay to serve as a reference implementation and test case.

**Game state entering Turn 3:**
- Location 1: War Camp (3 points, +1 Power to cards played here)
- Location 2: Crystal Cavern (2 points, no effect)
- Player A score: 5 (won War Camp on turns 1 and 2 = 3+3, lost Crystal Cavern turn 1 = 0, nobody at Crystal Cavern turn 2 = 0... wait, let's be more precise)

Let's trace from the start:

**Game Start:**
- Location 1: War Camp (3 points), Location 2: Crystal Cavern (2 points)
- War Camp resolves first (higher point value). Random tiebreaker not needed since point values differ.
- Both players draw 3 cards from shuffled decks. Board is empty. Scores: A=0, B=0.

**Turn 1:**
- Start of turn: Max Energy → 1. Each player draws 1 card (now 4 in hand).
- Planning: Player A plays Spark (1/2) to War Camp slot (1,1). Player B plays Iron Guard... wait, Iron Guard costs 2 and they have 1 energy. Player B plays Spark (1/2) to Crystal Cavern slot (2,1).
- Both confirm.
- Reveal: Both cards appear. Player A's Spark at War Camp gets +1 Power from War Camp's effect → now 3 Power. No On Reveal abilities on either card.
- Ongoing recalculation: No Ongoing cards. Skip.
- Scoring: War Camp — Player A has 3 Power, Player B has 0. Player A wins War Camp: +3 points. Crystal Cavern — Player B has 2 Power, Player A has 0. Player B wins Crystal Cavern: +2 points.
- Scores: A=3, B=2.

**Turn 2:**
- Start of turn: Max Energy → 2. Each draws 1 card (5 in hand, minus 1 played = 4 in hand).
- Planning: Player A plays Iron Guard (2/3) to Crystal Cavern slot (2,1). Player B plays Lookout (2/2) to War Camp slot (1,1).
- Reveal: Both cards placed. War Camp resolves first (higher point value). Player B's Lookout is at War Camp. Did Player A play a card at War Camp this turn? No. So Lookout's condition ("if your opponent played a card at this location this turn") is not met. Lookout stays at 2 Power. War Camp gives +1 → Lookout is 3 Power. Player A's Iron Guard at Crystal Cavern: no ability, no location effect. 3 Power.
- Scoring: War Camp — Player A has Spark (3 Power), Player B has Lookout (3 Power). Tied → 1 point each. Crystal Cavern — Player A has Iron Guard (3 Power), Player B has Spark (2 Power). Player A wins: +2 points.
- Scores: A = 3+1+2 = 6, B = 2+1 = 3.

**Turn 3:**
- Start of turn: Max Energy → 3. Each draws 1 card.
- Planning: Player A plays Healer (3/2) to War Camp slot (2,1) (adjacent to their existing Spark at (1,1)). Player B plays Saboteur (3/3) to War Camp slot (2,1).
- Reveal: Both cards placed. War Camp resolves first.
  - Player priority: Player A has 6 points (higher score), resolves first.
  - Player A's Healer: On Reveal: +1 Power to all other friendly cards at this location. Spark (the only other friendly card at War Camp) gets +1 → Spark now has 4 Power. Healer itself: base 2 + War Camp bonus 1 = 3 Power.
  - Player B's Saboteur: On Reveal: -1 Power to all enemy cards at this location. Player A's Spark goes from 4 → 3, Player A's Healer goes from 3 → 2.
  - No On Reveals at Crystal Cavern.
- Ongoing recalculation: No Ongoing cards. Skip.
- Scoring: War Camp — Player A: Spark (3) + Healer (2) = 5 Power. Player B: Lookout (3) + Saboteur (3+1 War Camp = 4) = 7 Power. Player B wins: +3 points. Crystal Cavern — Player A: Iron Guard (3). Player B: Spark (2). Player A wins: +2 points.
- Scores: A = 6+2 = 8, B = 3+3 = 6.

This walkthrough demonstrates: location effects applying on play, On Reveal resolution order (leading player first), ability interactions, and per-turn scoring. The game would continue from here until one player reaches the threshold (e.g., 20).

---

## Phase 1: Card Data Architecture

**What you're building:** The data modules that define all cards, locations, and the ability resolution system.

**Modules to create:**

### GameConfig (ModuleScript, ReplicatedStorage)

A single table of every tunable parameter. All other modules read from this — nothing is hardcoded elsewhere.

```
DECK_SIZE = 20
MAX_COPIES_PER_CARD = 1
LOCATIONS_PER_GAME = 2
SLOTS_PER_LOCATION = 6
GRID_COLUMNS = 3
GRID_ROWS = 2
STARTING_HAND_SIZE = 3
STARTING_MAX_ENERGY = 0
ENERGY_PER_TURN = 1
CARDS_DRAWN_PER_TURN = 1
MAX_HAND_SIZE = 7
TURN_TIMER_SECONDS = 30
POINTS_TO_WIN = 20
```

### CardDatabase (ModuleScript, ReplicatedStorage)

Contains the full card pool as defined in the Starter Card Pool section above. Each entry is a table keyed by card ID with fields: name, cost, power, ability (keyword string or nil), abilityText (display string or nil), rarity, faction, artAsset.

For the prototype, artAsset can be nil — the CardRenderer will generate colored rectangles with the card name as placeholder art.

### LocationDatabase (ModuleScript, ReplicatedStorage)

Contains the location pool as defined in the Starter Location Pool section above. Each entry: name, pointValue, effect (keyword string or nil), effectText (display string or nil).

### AbilityRegistry (ModuleScript, ReplicatedStorage)

Maps ability keyword strings to resolver functions. Each resolver takes (gameState, sourceCard, sourceLocation, sourceSlot) and returns the modified gameState.

**Keyword encoding format:** `"TriggerType:EffectName:Param1:Param2:..."`

Triggers for the prototype:
- `OnReveal` — fires once when the card is revealed during the reveal phase.
- `Ongoing` — recalculated after every state change. Not stored as a keyword that "fires" — instead, Ongoing cards are flagged and their effects are applied during recalculation sweeps.

Effects for the prototype:
- `AddPower:Target:Amount` — Target can be: `Self`, `Adjacent`, `Row`, `Column`, `Location` (all friendly at this location), `AllLocations` (all friendly everywhere), `Random_Enemy_Here` (random enemy at this location).
- `RemovePower:Target:Amount` — same target options but subtracts Power.
- `DrawCard:Amount` — draw N cards from deck.
- `MoveThis:OtherLocation` — move this card to a random empty slot at the other location.
- `DestroyBelow:PowerThreshold:Scope` — destroy all cards at or below a Power value. Scope: `Here_Both` (this location, both players), `Here_Friendly`, `Here_Enemy`.
- `SummonCopy:Target:Power` — create a token copy in a random empty adjacent slot with the given Power.
- `ConditionalPower:Condition:Amount` — add Power to self only if Condition is met. Conditions: `Opponent_Played_Here` (opponent played at least one card at this location this turn), `Alone_In_Row` (no other friendly cards in this row).
- `SetPower:Source` — set this card's Power to a value derived from Source. Sources: `Highest_Enemy_Here`.
- `Immune` — this card's Power cannot be reduced by opponent abilities (used for Colossus's Ongoing).

**Encoding examples:**
- Healer's ability: `"OnReveal:AddPower:Location:1"` with abilityText `"On Reveal: +1 Power to all other friendly cards at this location."`
- Frost Sprite: `"OnReveal:RemovePower:Random_Enemy_Here:2"`
- Lookout: `"OnReveal:ConditionalPower:Opponent_Played_Here:3"`
- Wind Dancer: `"OnReveal:MoveThis:OtherLocation"`
- Void Walker: `"OnReveal:DestroyBelow:2:Here_Both"`
- Trickster: `"OnReveal:SetPower:Highest_Enemy_Here"`
- Echo: `"OnReveal:SummonCopy:Adjacent:1"`
- Colossus: `"Ongoing:Immune"`

### SlotGrid (ModuleScript, ReplicatedStorage)

Utility module for grid queries:
- `getAdjacent(col, row)` → returns list of (col, row) pairs sharing an edge.
- `getRow(row)` → returns all (col, row) pairs in that row.
- `getColumn(col)` → returns all (col, row) pairs in that column.
- `isValidSlot(col, row)` → checks bounds within GRID_COLUMNS × GRID_ROWS.
- `getAllSlots()` → returns all slot positions.

**Deliverable:** Four ModuleScripts (GameConfig, CardDatabase, LocationDatabase, AbilityRegistry) plus the SlotGrid utility, all in ReplicatedStorage and importable by both server and client code.

---

## Phase 2: Match State Machine

**What you're building:** The server-side engine that runs a complete game from start to win.

### Game State Object

The MatchManager maintains a single authoritative state object structured as follows:

```
{
  players = {
    [playerID] = {
      score = 0,
      deck = { "CARD_ID", "CARD_ID", ... },    -- ordered, draw from front
      hand = { "CARD_ID", "CARD_ID", ... },     -- unordered
      energy = 0,                                -- current max energy
      boards = {
        [1] = {                                  -- location index
          { nil, nil, nil },                     -- row 1 (cols 1-3)
          { nil, nil, nil },                     -- row 2 (cols 1-3)
        },
        [2] = { ... }                            -- same structure for location 2
      }
    }
  },
  locations = {
    [1] = { id = "WAR_CAMP", pointValue = 3, effect = "..." },
    [2] = { id = "CRYSTAL_CAVERN", pointValue = 2, effect = nil },
  },
  locationPriority = { 1, 2 },    -- resolved at game start: higher point value first, random tiebreak
  playerPriority = { playerA, playerB },  -- resolved at game start for ties, updated each turn based on score
  turn = 0,
  phase = "WAITING_FOR_START",  -- or PLANNING, RESOLVING, SCORING, GAME_OVER
  turnSubmissions = {},           -- holds submitted plays until both players confirm
  cardStates = {},                -- tracks per-card modifiers (power adjustments from abilities)
}
```

### Board Card State

Each non-nil slot on the board doesn't just hold a card ID — it holds a card state:

```
{
  cardID = "SPARK",
  basePower = 2,           -- from CardDatabase
  powerModifiers = {       -- list of named modifiers for debugging
    { source = "WAR_CAMP_EFFECT", amount = 1 },
    { source = "HEALER_ONREVEAL", amount = 1 },
    { source = "SABOTEUR_ONREVEAL", amount = -1 },
  },
  currentPower = 3,        -- basePower + sum of modifiers (recalculated, never stale)
  isToken = false,         -- true for summoned copies (Echo)
  isImmune = false,        -- true for Colossus-style cards (cannot have Power reduced by enemies)
  turnPlayed = 3,          -- which turn this card was placed
  playOrder = 1,           -- order within the player's submission this turn (for resolution)
}
```

`currentPower` is always recalculated, never set directly. A `recalculatePower(cardState)` function sums basePower + all modifiers. If `isImmune` is true, enemy-sourced negative modifiers are excluded from the sum.

### Server-Side Flow (per turn)

The MatchManager runs this sequence every turn. This is pseudocode for the exact implementation:

```
function runTurn(gameState):
    -- 1. ADVANCE TURN
    gameState.turn += 1
    
    -- 2. GRANT ENERGY
    for each player:
        player.energy += ENERGY_PER_TURN
    
    -- 3. DRAW CARDS
    for each player:
        if #player.hand < MAX_HAND_SIZE and #player.deck > 0:
            card = table.remove(player.deck, 1)
            table.insert(player.hand, card)
    
    -- 4. APPLY START-OF-TURN LOCATION EFFECTS
    -- (e.g., Verdant Grove: +1 Power to all cards here)
    for each location in locationPriority order:
        applyStartOfTurnEffect(gameState, location)
    
    -- 5. SEND STATE TO CLIENTS
    for each player:
        fireClient("TurnStart", player, getVisibleState(gameState, player))
    -- Visible state includes: own hand, own boards, opponent's boards (card IDs and power),
    -- opponent's hand SIZE (not contents), both scores, energy, turn number
    
    -- 6. WAIT FOR SUBMISSIONS
    gameState.phase = "PLANNING"
    startTimer(TURN_TIMER_SECONDS)
    wait until both players submit OR timer expires
    -- Timer expiry with no submission = empty submission (pass)
    
    -- 7. VALIDATE SUBMISSIONS
    for each player:
        validPlays = {}
        energyRemaining = player.energy
        for each play in submission (in order):
            card = CardDatabase[play.cardID]
            if card.cost > energyRemaining: reject play, continue
            if play.cardID not in player.hand: reject play, continue
            if boardSlot is occupied by OPPONENT: reject play, continue
            -- (occupied by own card is allowed — this is an overwrite)
            if location restricts this card (e.g., Sky Temple and cost < 3): reject play, continue
            if location restricts this slot (e.g., Dueling Grounds back row): reject play, continue
            energyRemaining -= card.cost
            table.insert(validPlays, play)
            remove play.cardID from hand (tentatively)
        player.validPlays = validPlays
    
    -- 8. PLACE ALL CARDS ON BOARD (before any abilities resolve)
    for each player:
        for each play in player.validPlays (in order):
            -- If the target slot already has a friendly card, destroy it (overwrite)
            if slot is occupied by own card:
                remove existing card from board
                remove all modifiers sourced from the destroyed card
                -- (destroyed card is gone permanently — not returned to hand or deck)
            place new card on board at specified slot
            apply location effects that trigger on placement (e.g., War Camp +1 Power)
            assign playOrder index (1, 2, 3... in submission order)
            deduct energy cost from player.energy
    
    -- 9. RESOLVE ON REVEAL ABILITIES
    for each locationIndex in locationPriority order:
        -- Determine player resolution order for this turn
        if playerA.score > playerB.score:
            resolveOrder = { playerA, playerB }
        elif playerB.score > playerA.score:
            resolveOrder = { playerB, playerA }
        else:
            resolveOrder = gameState.playerPriority  -- predetermined random tiebreak
        
        for each player in resolveOrder:
            -- Get cards this player placed at this location THIS turn, in play order
            newCards = getCardsPlacedThisTurn(player, locationIndex)
            sort newCards by playOrder ascending
            for each card in newCards:
                if card has OnReveal ability:
                    resolveAbility(gameState, card, locationIndex)
    
    -- 10. RECALCULATE ALL ONGOING EFFECTS
    clearAllOngoingModifiers(gameState)
    for each card on the entire board:
        if card has Ongoing ability:
            applyOngoing(gameState, card)
    recalculateAllPower(gameState)
    
    -- 11. BROADCAST REVEAL RESULTS
    for each player:
        fireClient("RevealResult", player, getFullBoardState(gameState))
    -- Client animates: card flips, ability effects, power changes
    
    -- 12. SCORE LOCATIONS
    for each locationIndex in { 1, 2 }:
        playerAPower = sumPower(gameState, playerA, locationIndex)
        playerBPower = sumPower(gameState, playerB, locationIndex)
        locationPoints = gameState.locations[locationIndex].pointValue
        if playerAPower > playerBPower:
            playerA.score += locationPoints
        elif playerBPower > playerAPower:
            playerB.score += locationPoints
        else:  -- tie
            playerA.score += 1
            playerB.score += 1
    
    -- 13. BROADCAST SCORES
    fireClient("ScoreUpdate", allPlayers, { scores, breakdown per location })
    
    -- 14. CHECK WIN CONDITION
    if playerA.score >= POINTS_TO_WIN or playerB.score >= POINTS_TO_WIN:
        if playerA.score > playerB.score:
            winner = playerA
        elif playerB.score > playerA.score:
            winner = playerB
        else:
            -- Exact tie at or above threshold: play one tiebreaker turn
            -- (set a flag, run one more turn, then highest score wins; if still tied, draw)
            gameState.tiebreaker = true
            return  -- will run one more turn
        
        gameState.phase = "GAME_OVER"
        fireClient("GameOver", allPlayers, { winner, finalScores })
        return
    
    -- 15. CONTINUE
    -- Since players can always overwrite their own cards, there is no stalemate condition.
    -- The game always continues to the next turn as long as the threshold hasn't been reached.
    -- A player with cards in hand can always play (even if all slots are full, they can overwrite).
    -- A player with an empty hand and no deck simply passes each turn — but the opponent can
    -- still play, and scoring continues, so the game will end shortly.
```

### Bot Opponent (for Playtesting)

The prototype must include a bot opponent so the game can be tested solo. The bot replaces one of the two players and runs server-side — it receives the same game state a real client would, makes decisions, and submits plays through the same MatchManager interface.

**Bot decision logic (simple heuristic, not AI):**

```
function botDecidePlays(gameState, botPlayer):
    plays = {}
    energyRemaining = botPlayer.energy
    hand = copy(botPlayer.hand)
    
    -- Sort hand by cost descending (play biggest affordable cards first)
    sort hand by CardDatabase[cardID].cost descending
    
    for each cardID in hand:
        card = CardDatabase[cardID]
        if card.cost > energyRemaining: continue
        
        -- Pick a location: prefer the higher-value location if we're losing there,
        -- otherwise spread cards between locations
        location = pickLocation(gameState, botPlayer)
        
        -- Pick a slot: prefer empty slots; if all full, overwrite the lowest-Power friendly card
        slot = pickSlot(gameState, botPlayer, location)
        
        if slot:
            table.insert(plays, { cardID, location, slot.col, slot.row })
            energyRemaining -= card.cost
    
    return plays

function pickLocation(gameState, botPlayer):
    -- Calculate current Power at each location for both players
    -- If losing at the higher-value location, play there
    -- If winning at both, play at whichever has more empty slots
    -- If tied, pick randomly
    -- (This is intentionally simple — a smarter bot comes later)

function pickSlot(gameState, botPlayer, locationIndex):
    -- Get all slots at this location for the bot
    -- If any are empty, pick a random empty one
    -- If all are full, pick the friendly card with the lowest current Power and overwrite it
    -- (Only overwrite if the new card has higher base Power than the card being replaced)
```

**Integration:** When a player starts a match against the bot (via a separate "Play vs Bot" ProximityPrompt in the hub), the MatchManager creates the match with one real player and one bot. The bot's submissions are generated instantly (no timer needed), but the server adds a brief delay (1–2 seconds) before submitting to make reveals feel natural. The bot uses the same starter deck as the player (or a predefined bot deck).

**The bot does NOT need to be good.** It needs to make legal plays and provide an unpredictable opponent for testing pacing, scoring math, and UI flow. Improvement comes later.

### Communication (RemoteEvents)

Create these RemoteEvents in ReplicatedStorage:
- `TurnStart` (server → client): sends visible game state, energy, hand, turn number.
- `SubmitTurn` (client → server): sends ordered list of plays.
- `RevealResult` (server → client): sends full board state after resolution.
- `ScoreUpdate` (server → client): sends updated scores and per-location breakdown.
- `GameOver` (server → client): sends winner and final state.
- `InvalidPlay` (server → client): notifies if any plays were rejected during validation, with reason.

### Matchmaking (Basic)

For the prototype, implement a simple queue. When a player interacts with the arena entrance, add them to a server-side queue table. When two players are in the queue, create a new MatchManager instance for them, remove both from the queue, and start the game. No rank-based filtering for the prototype — just first-come-first-served.

**Deliverable:** A MatchManager ModuleScript in ServerScriptService that runs a complete game: turn loop, simultaneous submission, validation, placement (with overwriting), On Reveal resolution, Ongoing recalculation, per-turn scoring, and win detection. A bot opponent that makes heuristic-based plays for solo playtesting. Plus RemoteEvents for client-server communication and a basic matchmaking queue (human vs. human and human vs. bot).

---

## Phase 3: Board and Hand UI

**What you're building:** The full-screen match interface — two locations with 3×2 grids, the player's hand, energy/score display, and all turn interaction.

### Screen Layout (Landscape, ScreenGui)

The entire match UI is a ScreenGui that covers the full screen, hiding the 3D hub world during gameplay.

```
┌──────────────────────────────────────────────────────────┐
│  [Opponent Score: 6]    [Turn 4]    [Your Score: 8]      │
│                                                          │
│  ┌─ Location 1: War Camp (3 pts) ─┐  ┌─ Location 2 ──┐ │
│  │  Opponent's 3×2 grid            │  │  Opp's grid    │ │
│  │  [card] [card] [    ]           │  │  [    ] [    ] │ │
│  │  [    ] [card] [    ]           │  │  [card] [    ] │ │
│  │ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │  │ ─ ─ ─ ─ ─ ─  │ │
│  │  Your 3×2 grid                  │  │  Your grid     │ │
│  │  [card] [slot] [slot]           │  │  [slot] [slot] │ │
│  │  [card] [slot] [slot]           │  │  [slot] [slot] │ │
│  │  Power: You 8 / Opp 5          │  │  You 3 / Opp 2 │ │
│  └─────────────────────────────────┘  └────────────────┘ │
│                                                          │
│  Energy: ●●●  (3 available)                  [Confirm]     │
│                                                          │
│  Hand: [card] [card] [card] [card]           [Timer: 22] │
└──────────────────────────────────────────────────────────┘
```

Key layout decisions:
- Locations sit side-by-side, each divided horizontally: opponent's grid on top, yours on bottom, mirrored so both players see their own cards closer to their hand.
- Each slot is a clearly bordered rectangle. Empty slots have a subtle dotted border. Occupied slots show the card (art, name, Power number).
- Power totals per location are shown below each location panel. This is the most important number — make it large and bold.
- The hand runs along the bottom. Cards are wider here than on the board to allow readability.
- Score is prominently displayed at the top. Use large text and update with animation.
- The Confirm button is large and easy to tap on mobile. It's grayed out if no cards have been placed (tapping it in that state confirms a deliberate pass).

### Card Rendering (CardFrame Module)

A reusable `CardFrame` ModuleScript that takes a card ID and a display size ("hand", "board", "detail") and returns a Frame GUI element:

- **Board size:** Small rectangle. Shows: card art (colored rectangle for prototype), Power number (large, bottom-right), cost (small, top-left). Name and ability text are NOT shown at board size — too small to read.
- **Hand size:** Wider rectangle. Shows: card art, name, cost, Power, and one line of ability text (truncated if needed).
- **Detail size:** Full card view shown as an overlay when a player taps/clicks any card (on the board or in hand). Shows all information including full ability text. A player can tap any card — their own or their opponent's — to see its detail view.

Rarity is indicated by border color: white (common), green (uncommon), blue (rare), gold (legendary). For the prototype, all cards can be common — rarity only matters for the collection system in Phase 5.

### Interaction During Planning Phase

1. Player taps a card in their hand → the card highlights (rises slightly or gets a glow border), and all valid slots on both locations highlight with a pulsing border. Valid slots include empty slots AND slots occupied by the player's own cards (overwrite targets). Own-occupied slots should highlight with a distinct color (e.g., orange instead of green) to signal that placing here will destroy the existing card.
2. Player taps a highlighted slot → the card is placed there with a "pending" visual (semi-transparent, pulsing). If the slot had an existing friendly card, show that card dimmed/crossed-out beneath the pending card to indicate it will be overwritten. Energy display updates to show the tentative spend. The card is removed from the hand display.
3. Player can tap a pending card on the board → it returns to hand, energy is refunded, the slot reverts (if it was an overwrite, the original card reappears).
4. Player can place multiple cards in one turn if they have the energy.
5. Player taps Confirm → all pending placements are sent to the server as a SubmitTurn event, ordered by placement sequence.
6. If the timer expires → whatever is currently placed is submitted. If nothing is placed, it's a pass.

During the waiting period (opponent hasn't confirmed), show a subtle "Waiting for opponent..." indicator. The Confirm button changes to "Waiting..." and becomes non-interactive.

### Reveal Phase Animation

When the server sends RevealResult:
1. All pending cards on the player's side become solid (no longer semi-transparent). If any card was an overwrite, the old card briefly shatters or fades out before the new card solidifies.
2. Opponent's new cards appear face-down in their slots, then flip to face-up with a brief animation (0.2s per card, staggered slightly). Overwrites on the opponent's side show the same shatter effect on the replaced card.
3. On Reveal ability effects play: the source card briefly glows, then affected cards show floating "+1" or "-2" text that fades upward (green for buffs, red for debuffs). Power numbers on affected cards animate to their new values.
4. Location Power totals update with a counting animation.
5. After abilities resolve, scores update: points earned this turn fly from each location to the score display at the top. A brief "+3" or "+2" appears next to the score.

### Detail Overlay

Tapping any card (own or opponent's) during any phase shows a centered detail overlay: the full card at large size with all text readable. A dimmed backdrop covers the rest of the screen. Tapping outside the overlay closes it. During the planning phase, the detail overlay for a hand card includes a "Select" button that starts the placement flow.

### End-of-Game Screen

When GameOver fires, show a full-screen overlay: "Victory!" or "Defeat!", the final score, and a "Return to Hub" button. Keep it simple for the prototype — no rank changes, no rewards. Just the result and a way back.

### Mobile Optimization Notes

- All touch targets: minimum 44×44 points.
- With 2 locations × 6 slots × 2 players = 24 slots on screen, test carefully on small phones. If cramped, the fallback is a tab system: show one location at a time with a toggle between them. Both locations' scores remain visible even when toggled.
- Hand cards should be scrollable horizontally if more than 4 are present, since max hand size is 7.
- The timer should be visually prominent — a countdown number or shrinking bar. At 5 seconds remaining, flash it red and play a warning sound.

**Deliverable:** A complete ScreenGui match interface with two-location board, 3×2 grids, tap-to-place interaction, pending card management, reveal animations, per-turn score updates, card detail overlays, and a Confirm/Pass button. Functional on both desktop and mobile.

---

## Phases 4–10: Summary

Phases 4 through 10 remain structurally the same as in the previous version of this document. The key changes from the new rules apply only to Phases 1–3 (the prototype). For reference, the later phases are:

- **Phase 4 — Hub World and Deck Builder:** 3D hub with arena, shop, deck builder, and trading post. Deck builder enforces 20-card / 1-copy rules with mana curve display.
- **Phase 5 — Collection, Packs, Persistence:** DataStore-backed player data, starter collection of all 30 cards, pack system with pity timers, Robux integration via Developer Products.
- **Phase 6 — Trading System:** Server-validated atomic card swaps, double confirmation for rare cards, deck-lock protection, transaction logging.
- **Phase 7 — Ability and Location Expansion:** Positional abilities (row, column, cross-location), 20+ new keyword effects, location effects leveraging the grid, deterministic resolution pipeline.
- **Phase 8 — Ranked Play, Seasons, Quests:** Tier-based ladder, seasonal resets and rewards, daily/weekly quests, free and premium reward tracks.
- **Phase 9 — Polish, Animations, Audio:** Card flip animations, ability VFX, sound design (12 core sounds), card visual template, consistent CardFrame rendering across all screens.
- **Phase 10 — Monetization and Live Service:** Pack sales, seasonal passes, cosmetics, 6–8 week content cadence, balance monitoring, community building.

These phases should be revisited and detailed further when the prototype is complete and the core loop has been playtested. Playtesting will likely surface changes to card balance, location effects, and pacing that affect later system design.

---

## Configurable Parameters Reference

All values are defined in the `GameConfig` ModuleScript. No other module hardcodes these.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `DECK_SIZE` | 20 | |
| `MAX_COPIES_PER_CARD` | 1 | |
| `LOCATIONS_PER_GAME` | 2 | |
| `SLOTS_PER_LOCATION` | 6 | 3×2 grid per player |
| `GRID_COLUMNS` | 3 | |
| `GRID_ROWS` | 2 | |
| `STARTING_HAND_SIZE` | 3 | Drawn before turn 1 |
| `STARTING_MAX_ENERGY` | 0 | Becomes 1 at start of turn 1 |
| `ENERGY_PER_TURN` | 1 | No cap |
| `CARDS_DRAWN_PER_TURN` | 1 | Blocked if hand is at max |
| `MAX_HAND_SIZE` | 7 | Draw is skipped, card stays in deck |
| `TURN_TIMER_SECONDS` | 30 | |
| `POINTS_TO_WIN` | 20 | Subject to playtesting |

---

## Prototype Phase Summary

| Phase | Focus | Estimated Effort |
|-------|-------|-----------------|
| 1 | Card/Location Data, AbilityRegistry, SlotGrid | 1–2 weeks |
| 2 | MatchManager (full game loop, validation, resolution, scoring) + Bot Opponent | 4–5 weeks |
| 3 | Board UI (layout, interaction, reveal animation, scoring display) | 3–4 weeks |

**Total to playable prototype: ~8–11 weeks.**

After the prototype is functional, playtest with these questions in mind:
- Does the point threshold feel right? (Games too short or too long?)
- Is the 3×2 grid readable on mobile?
- Do positional abilities (adjacency, row, column) feel meaningful or fiddly?
- Is the energy curve correct? (Do late turns have too much energy with nothing to spend it on?)
- How often are players overwriting their own cards? Does it feel like a meaningful choice or a forced move?
- Is the bot opponent sufficient for evaluating pacing and balance, or do you need smarter heuristics?

---

## Glossary

Every Roblox-specific and game-specific term used in this document, defined in plain language.

**Baseplate** — The default Roblox Studio template: an empty world with a flat gray floor. Your starting point.

**Client** — One player's instance of the game running on their device. Each player has their own client. The client handles what the player sees and touches, but does not run game logic.

**DataStore** — Roblox's built-in cloud database for saving player data (collections, decks, scores) between sessions. Used in Phase 5 onwards — not needed for the prototype.

**Decal** — A 2D image applied to a 3D surface. Used for card art when rendering cards as 3D objects. In the prototype (where cards are ScreenGui elements), you'll use ImageLabels instead.

**Developer Product** — A purchasable item in a Roblox game that can be bought multiple times (like a pack of cards). Purchased with Robux. Defined in the Roblox dashboard, processed in code via MarketplaceService.

**Explorer** — The panel in Roblox Studio that shows the tree of all objects in your game. Think of it as a file browser for your project.

**FireClient / FireServer** — Methods on RemoteEvent. FireServer sends a message from client to server. FireClient sends from server to a specific client. FireAllClients sends to every connected client.

**Frame** — A rectangular UI element in a ScreenGui. Cards, slots, buttons, and panels are all Frames with nested child elements.

**Game Pass** — A purchasable item that can only be bought once per player (like a season pass). Different from Developer Products, which are repeatable.

**ImageLabel** — A UI element that displays an image. Used for card art, icons, backgrounds.

**LocalScript** — A script that runs on the client (one player's machine). Use for UI, input, and animations. Cannot access server-side services. Place in StarterPlayerScripts.

**Luau** — Roblox's programming language. A modified version of Lua with type annotations and performance improvements. All scripts in Roblox are written in Luau.

**ModuleScript** — A reusable code library. Doesn't run on its own — other scripts import it with `require()`. Can be shared between server and client if placed in ReplicatedStorage.

**On Reveal** — A card ability trigger. Fires once when the card is played and revealed during the reveal phase.

**Ongoing** — A card ability type. Active continuously while the card is on the board. Recalculated after every state change.

**Output** — The console panel in Roblox Studio. Shows print messages, warnings (orange), and errors (red). Your primary debugging tool.

**Overwrite** — Playing a card into a slot already occupied by one of your own cards. The existing card is destroyed and replaced.

**Power** — A card's numeric strength at its location. A location's total Power per player determines who wins that location each turn.

**ProximityPrompt** — A Roblox interaction trigger. When a player walks near an object with a ProximityPrompt, a prompt appears ("Press E to..."). Used in the hub world for accessing the shop, arena, etc.

**RemoteEvent** — A named message channel in ReplicatedStorage that allows communication between client and server scripts. The fundamental networking mechanism.

**ReplicatedStorage** — A service visible to both server and clients. Shared data (card definitions, config) and RemoteEvents live here.

**Robux** — Roblox's premium currency. Players buy Robux with real money. Developers earn Robux through in-game sales and can convert to real currency via DevEx.

**Rojo** — A third-party tool that syncs files on your filesystem to Roblox Studio. Lets Claude Code write files that automatically appear in Studio. Not required but strongly recommended.

**ScreenGui** — A UI container that displays 2D elements overlaid on the player's screen. Your entire match interface is a ScreenGui.

**Script** — A script that runs on the server. Has full authority over game state. Place in ServerScriptService.

**Server** — The single authoritative instance of the game. Runs game logic, validates player actions, and sends results to clients. There is one server per game session.

**ServerScriptService** — A service for server-only scripts. Clients cannot see or access anything here. All game logic (MatchManager, BotPlayer, GameServer) lives here.

**StarterGui** — A service where you place ScreenGui objects. Each player automatically gets a copy of everything in StarterGui when they join.

**StarterPlayerScripts** — A service where you place LocalScripts. Each player automatically gets a copy when they join.

**SurfaceGui** — A UI container attached to the face of a 3D Part. Can display text, images, and buttons on 3D objects. Used when rendering cards as physical objects in the 3D world (not used in the prototype — we use ScreenGui instead for better mobile performance).

**TextLabel** — A UI element that displays text. Used for card names, Power numbers, score displays.

**WaitForChild()** — A Luau method that pauses a script until a named child object exists. Use this when referencing objects that might not be loaded yet (e.g., RemoteEvents). Example: `game.ReplicatedStorage:WaitForChild("Events"):WaitForChild("SubmitTurn")`

**Workspace** — The service that contains the 3D world. The baseplate, hub world, and any physical objects live here.
