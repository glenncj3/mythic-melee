# MythicMash Content Guide

How to add new cards and locations to MythicMash. This guide covers every ability type, every location effect, balance guidelines, and the exact steps to ship new content.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Adding a New Card](#adding-a-new-card)
3. [Card Ability Reference](#card-ability-reference)
   - [OnReveal Abilities](#onreveal-abilities)
   - [Ongoing Abilities](#ongoing-abilities)
   - [EndOfTurn Abilities](#endofturn-abilities)
   - [OnDestroy Abilities](#ondestroy-abilities)
   - [Compound Abilities](#compound-abilities)
4. [Adding a New Location](#adding-a-new-location)
5. [Location Effect Reference](#location-effect-reference)
   - [OnPlay Effects](#onplay-effects)
   - [StartOfTurn Effects](#startofturn-effects)
   - [EndOfTurn Location Effects](#endofturn-location-effects)
   - [Restriction Effects](#restriction-effects)
   - [Special Effects](#special-effects)
   - [Compound Location Effects](#compound-location-effects)
6. [Balance Guidelines](#balance-guidelines)
7. [Factions](#factions)
8. [Validation and Testing](#validation-and-testing)
9. [Updating the Starter Deck](#updating-the-starter-deck)
10. [Adding New Ability Types (Advanced)](#adding-new-ability-types-advanced)

---

## Architecture Overview

All game content is **data-driven**. You add cards and locations by writing entries in Lua tables — you do **not** need to touch game engine code unless you are adding an entirely new effect type.

### Key Files

| File | Purpose |
|---|---|
| `src/ReplicatedStorage/Modules/CardDatabase.lua` | All card definitions (stats, abilities, faction, art) |
| `src/ReplicatedStorage/Modules/LocationDatabase.lua` | All location definitions (point value, effects) |
| `src/ReplicatedStorage/Modules/AbilityRegistry.lua` | Maps card ability keyword strings to resolver functions |
| `src/ReplicatedStorage/Modules/LocationEffectRegistry.lua` | Maps location effect keyword strings to resolver functions |
| `src/ReplicatedStorage/Modules/LocationRestrictions.lua` | Handles `Restrict:` placement rules |
| `src/ReplicatedStorage/Modules/GameConfig.lua` | Game constants and the starter deck list |
| `src/ReplicatedStorage/Modules/GameStateUtils.lua` | Shared helpers for querying/modifying game state |

### How It Works

Abilities and effects are **keyword strings** in a colon-delimited format:

```
TriggerType:EffectName:Param1:Param2:...
```

When the game engine reaches the right phase (card placed, turn starts, card destroyed, etc.), it parses the keyword string and dispatches to the matching resolver function. You never call resolvers directly — just write the correct string in the database.

---

## Adding a New Card

Open `CardDatabase.lua` and add a new entry to the table. Every card needs a unique `UPPER_SNAKE_CASE` key.

### Card Template

```lua
MY_NEW_CARD = {
    name = "My New Card",           -- Display name (any string)
    cost = 3,                       -- Energy cost (1-6)
    power = 4,                      -- Base power (0+)
    ability = nil,                  -- Ability string or nil for vanilla
    abilityText = nil,              -- Human-readable text or nil
    rarity = "Common",              -- "Common", "Uncommon", "Rare", "Legendary"
    faction = "Iron",               -- "Arcane", "Iron", "Wild", "Shadow"
    artColor = Color3.fromRGB(R, G, B), -- Card art color
},
```

### Required Fields

All 8 fields are **required** for every card. The validator will flag any missing fields.

| Field | Type | Notes |
|---|---|---|
| `name` | string | The display name shown to players |
| `cost` | number | Energy cost to play (1-6 typically) |
| `power` | number | Base power value. Can be 0 (e.g. Sprout grows via EndOfTurn) |
| `ability` | string or nil | The keyword ability string. `nil` for vanilla cards |
| `abilityText` | string or nil | Human-readable ability text. Must exist if `ability` exists. `nil` for vanilla |
| `rarity` | string | One of: `"Common"`, `"Uncommon"`, `"Rare"`, `"Legendary"` |
| `faction` | string | One of: `"Arcane"`, `"Iron"`, `"Wild"`, `"Shadow"` |
| `artColor` | Color3 | RGB color used to render the card art background |

### Vanilla Card Example

```lua
STEEL_KNIGHT = {
    name = "Steel Knight",
    cost = 3,
    power = 5,
    ability = nil,
    abilityText = nil,
    rarity = "Common",
    faction = "Iron",
    artColor = Color3.fromRGB(170, 170, 180),
},
```

### Card With a Single Ability

```lua
FIRE_MAGE = {
    name = "Fire Mage",
    cost = 4,
    power = 3,
    ability = "OnReveal:RemovePower:All_Enemy_Here:2",
    abilityText = "On Reveal: -2 Power to all enemy cards at this location.",
    rarity = "Rare",
    faction = "Shadow",
    artColor = Color3.fromRGB(255, 80, 30),
},
```

### Card With a Compound Ability

Separate multiple abilities with `|` (pipe):

```lua
NATURE_SPIRIT = {
    name = "Nature Spirit",
    cost = 5,
    power = 4,
    ability = "EndOfTurn:AddPower:Self:2|Ongoing:AddPower:Adjacent:1",
    abilityText = "End of Turn: +2 Power to self. Ongoing: +1 Power to adjacent cards.",
    rarity = "Legendary",
    faction = "Wild",
    artColor = Color3.fromRGB(100, 200, 60),
},
```

---

## Card Ability Reference

Every ability string follows this format:

```
Trigger:Effect:Param1:Param2:...
```

There are four trigger types. Each fires at a different point in the turn:

| Trigger | When It Fires |
|---|---|
| `OnReveal` | Once, when the card is first played and placed on the board |
| `Ongoing` | Recalculated from scratch every turn after OnReveal resolution |
| `EndOfTurn` | After Ongoing recalculation, before scoring |
| `OnDestroy` | When the card is removed from the board (by DestroyBelow, overwrite, or location effects) |

### Turn Flow Order

```
1. Grant energy
2. Draw cards
3. Apply StartOfTurn location effects
4. Planning phase (players choose cards)
5. Validate and place cards (triggers OnPlay location effects)
6. Resolve OnReveal abilities
7. Recalculate Ongoing abilities
8. Resolve EndOfTurn abilities (cards + locations)
9. Score locations
10. Check win condition
```

---

### OnReveal Abilities

Fire once when the card is played. Suppressed by locations with `SuppressOnReveal`.

#### `OnReveal:DrawCard:N`

Draw N cards from your deck.

```lua
ability = "OnReveal:DrawCard:1"    -- Draw 1 card
ability = "OnReveal:DrawCard:2"    -- Draw 2 cards
```

**Existing cards:** Scout (1), High Priestess (2)

---

#### `OnReveal:AddPower:Target:Amount`

Add power to cards. Multiple target types available:

| Target | Effect |
|---|---|
| `Self` | +N to this card |
| `Location` | +N to all OTHER friendly cards at this location |
| `Column` | +N to all friendly cards in the same column (excluding self) |
| `Faction_X` | +N to all cards of faction X at this location (excluding self) |
| `PerFaction_X` | +N to self for each OTHER card of faction X you control (all locations) |

```lua
ability = "OnReveal:AddPower:Self:2"                -- +2 to self
ability = "OnReveal:AddPower:Location:1"            -- +1 to all other friendlies here
ability = "OnReveal:AddPower:Column:1"              -- +1 to same-column friendlies
ability = "OnReveal:AddPower:Faction_Iron:1"        -- +1 to all Iron cards here
ability = "OnReveal:AddPower:PerFaction_Arcane:1"   -- +1 per Arcane card you control
```

**Existing cards:** Healer (Location:1), Mystic (Column:1), Banner Knight (Faction_Iron:1), Rift Scholar (PerFaction_Arcane:1)

---

#### `OnReveal:RemovePower:Target:Amount`

Remove power from cards. The amount is applied as a negative modifier.

| Target | Effect |
|---|---|
| `Random_Enemy_Here` | -N to one random enemy at this location |
| `Random_Friendly_Here` | -N to one random friendly at this location (excluding self) |
| `All_Enemy_Here` | -N to ALL enemy cards at this location |

```lua
ability = "OnReveal:RemovePower:Random_Enemy_Here:2"     -- -2 to random enemy here
ability = "OnReveal:RemovePower:All_Enemy_Here:1"        -- -1 to all enemies here
ability = "OnReveal:RemovePower:Random_Friendly_Here:1"  -- -1 to random friendly here
```

**Notes:** Enemy-targeted debuffs are blocked by the `isImmune` flag (set by `Ongoing:Immune` or `Ongoing:NoPowerReduction`).

**Existing cards:** Frost Sprite (Random_Enemy:2), Saboteur (All_Enemy:1), Storm Mage (All_Enemy:2), Ember (Random_Friendly:1)

---

#### `OnReveal:ConditionalPower:Condition:Amount`

Conditionally buff this card.

| Condition | Triggers when... |
|---|---|
| `Opponent_Played_Here` | Your opponent played a card at the same location this turn |
| `Empty_Slots_Here` | +N per empty friendly slot at this location |

```lua
ability = "OnReveal:ConditionalPower:Opponent_Played_Here:3"  -- +3 if opponent played here
ability = "OnReveal:ConditionalPower:Empty_Slots_Here:1"      -- +1 per empty slot
```

**Existing cards:** Lookout (Opponent_Played_Here:3), Berserker (Empty_Slots_Here:1)

---

#### `OnReveal:MoveThis:OtherLocation`

Move this card to a random empty slot at the other location.

```lua
ability = "OnReveal:MoveThis:OtherLocation"
```

**Existing cards:** Wind Dancer

---

#### `OnReveal:SetPower:Source`

Set this card's power to match a target.

| Source | Effect |
|---|---|
| `Highest_Enemy_Here` | Copy the highest enemy card's power at this location |

```lua
ability = "OnReveal:SetPower:Highest_Enemy_Here"
```

**Existing cards:** Trickster

---

#### `OnReveal:DestroyBelow:PowerThreshold:Scope`

Destroy all cards at or below a power threshold.

| Scope | What gets destroyed |
|---|---|
| `Here_Both` | All cards (both sides) at this location |
| `Here_Friendly` | Only your cards at this location |
| `Here_Enemy` | Only enemy cards at this location |

```lua
ability = "OnReveal:DestroyBelow:2:Here_Both"    -- Destroy all cards with <=2 power (both sides)
ability = "OnReveal:DestroyBelow:3:Here_Enemy"   -- Destroy enemy cards with <=3 power
```

**Notes:** Destroyed cards trigger their `OnDestroy` abilities. The source card is never destroyed by its own DestroyBelow.

**Existing cards:** Void Walker (2:Here_Both), Shadow Lord (3:Here_Enemy)

---

#### `OnReveal:SummonCopy:Adjacent:Power`

Summon a token copy of this card in a random empty adjacent slot.

```lua
ability = "OnReveal:SummonCopy:Adjacent:1"   -- Summon a 1-power copy next to this card
```

**Existing cards:** Echo, Bloom Fairy

---

#### `OnReveal:Bounce:Target`

Return a card to its owner's hand, freeing the board slot.

| Target | Effect |
|---|---|
| `Random_Enemy_Here` | Bounce a random enemy card at this location |
| `Weakest_Friendly_Here` | Bounce your weakest card here (replay for OnReveal value) |

```lua
ability = "OnReveal:Bounce:Random_Enemy_Here"
ability = "OnReveal:Bounce:Weakest_Friendly_Here"
```

**Notes:** Fails if the target owner's hand is full (6 cards).

**Existing cards:** Spell Weaver (Weakest_Friendly_Here)

---

#### `OnReveal:AddPowerAll:Amount`

+N to ALL your other cards across ALL locations.

```lua
ability = "OnReveal:AddPowerAll:1"   -- +1 to every card you control (except self)
```

**Existing cards:** Grand Archivist

---

#### `OnReveal:FillLocation:TokenPower`

Fill all empty friendly slots at this location with token cards of the given power.

```lua
ability = "OnReveal:FillLocation:1"   -- Fill empty slots with 1-power tokens
```

**Existing cards:** World Tree

---

#### `OnReveal:SwapPower:Target`

Swap this card's current power with a target card's power.

| Target | Effect |
|---|---|
| `Random_Enemy_Here` | Swap with a random enemy at this location |

```lua
ability = "OnReveal:SwapPower:Random_Enemy_Here"
```

**Notes:** Replaces all existing modifiers on both cards to achieve the swap.

**Existing cards:** Soul Thief

---

### Ongoing Abilities

Recalculated from scratch every turn. All `_ONGOING` modifiers are cleared first, then reapplied. This means Ongoing effects always reflect the current board state.

#### `Ongoing:AddPower:Target:Amount`

Continuously buff cards.

| Target | Effect |
|---|---|
| `Adjacent` | +N to adjacent cards (left/right neighbors) |
| `Location` | +N to all other friendly cards at this location |
| `Row` | +N to all other friendly cards in the same row |
| `AllLocations` | +N to all other friendly cards at both locations |
| `Self:PerOngoing` | +1 per other Ongoing card you control (special case) |
| `Faction_X` | +N to all your faction X cards at all locations (excluding self) |

```lua
ability = "Ongoing:AddPower:Adjacent:1"           -- +1 to neighbors
ability = "Ongoing:AddPower:Location:1"           -- +1 to all other friendlies here
ability = "Ongoing:AddPower:Row:2"                -- +2 to row mates
ability = "Ongoing:AddPower:AllLocations:1"       -- +1 globally
ability = "Ongoing:AddPower:Self:PerOngoing"      -- +1 per other Ongoing card
ability = "Ongoing:AddPower:Faction_Arcane:1"     -- +1 to all your Arcane cards
```

**Existing cards:** Seedling (Adjacent:1), Commander (Location:1), Shield Wall (Row:2), Overlord (AllLocations:1), Sage (Self:PerOngoing), Fortress (Adjacent:2), Arcane Sovereign (Faction_Arcane:1)

---

#### `Ongoing:DoublePower:Location`

Double your total power at this location (applied after all other modifiers during scoring).

```lua
ability = "Ongoing:DoublePower:Location"
```

**Existing cards:** Warlord

---

#### `Ongoing:Immune`

This card's power cannot be reduced by enemy abilities.

```lua
ability = "Ongoing:Immune"
```

**Existing cards:** Colossus

---

#### `Ongoing:NoPowerReduction:Location`

ALL friendly cards at this location (including this card) are immune to enemy power reduction.

```lua
ability = "Ongoing:NoPowerReduction:Location"
```

**Existing cards:** Shield Bearer

---

### EndOfTurn Abilities

Fire every turn after Ongoing recalculation. Modifiers from EndOfTurn effects **accumulate** across turns (they are not cleared like Ongoing modifiers).

#### `EndOfTurn:AddPower:Target:Amount`

| Target | Effect |
|---|---|
| `Self` | +N to this card each turn |
| `AllFriendlyHere` | +N to all friendly cards at this location (including self) each turn |

```lua
ability = "EndOfTurn:AddPower:Self:1"              -- +1 to self each turn (grows over time)
ability = "EndOfTurn:AddPower:Self:2"              -- +2 to self each turn
ability = "EndOfTurn:AddPower:AllFriendlyHere:1"   -- +1 to all friendlies here
```

**Existing cards:** Sprout (Self:1), Siege Engine (Self:1), Grove Tender (AllFriendlyHere:1), Ancient Oak (Self:2)

---

#### `EndOfTurn:DamageAll:Amount`

-N to all enemy cards at this location each turn.

```lua
ability = "EndOfTurn:DamageAll:1"   -- -1 to all enemies here each turn
```

**Notes:** Respects the `isImmune` flag (blocked by Immune/NoPowerReduction).

**Existing cards:** Plague Rat

---

#### `EndOfTurn:SummonToken:Power`

Summon a token in a random empty friendly slot at this location each turn.

```lua
ability = "EndOfTurn:SummonToken:1"   -- Summon a 1-power token each turn
```

**Existing cards:** Vine Mother

---

### OnDestroy Abilities

Fire when the card is destroyed (by DestroyBelow, overwrite, or location effects like Death Hollow). The card is still on the board when OnDestroy fires, then removed after.

#### `OnDestroy:DrawCard:N`

Draw N cards when this card is destroyed.

```lua
ability = "OnDestroy:DrawCard:1"
```

---

#### `OnDestroy:AddPower:AllFriendlyHere:Amount`

+N to all other friendly cards at this location when destroyed.

```lua
ability = "OnDestroy:AddPower:AllFriendlyHere:3"   -- +3 to all other friendlies here
```

**Existing cards:** Thornguard

---

#### `OnDestroy:SummonToken:Power`

Summon a token at this location when destroyed (prefers the same slot).

```lua
ability = "OnDestroy:SummonToken:5"   -- Leave a 5-power token behind
```

**Existing cards:** Doom Herald

---

#### `OnDestroy:Bounce:Self`

Return this card to your hand instead of being destroyed. The card is removed from the board but goes to hand, not the void. Fails if hand is full (6 cards).

```lua
ability = "OnDestroy:Bounce:Self"
```

**Existing cards:** Phantom

---

### Compound Abilities

A single card can have **multiple abilities** separated by `|`. Each sub-ability is resolved independently by its trigger.

```lua
-- OnReveal + Ongoing
ability = "OnReveal:DrawCard:1|Ongoing:AddPower:Self:PerOngoing"

-- Two OnReveals
ability = "OnReveal:RemovePower:Random_Enemy_Here:3|OnReveal:AddPower:Self:2"

-- EndOfTurn + Ongoing
ability = "EndOfTurn:AddPower:Self:2|Ongoing:AddPower:Adjacent:1"

-- OnReveal + OnDestroy
ability = "OnReveal:RemovePower:Random_Enemy_Here:3|OnDestroy:SummonToken:5"

-- OnReveal + EndOfTurn
ability = "OnReveal:FillLocation:1|EndOfTurn:AddPower:AllFriendlyHere:2"
```

**Rules:**
- Any combination of triggers is valid
- Multiple abilities of the same trigger type are valid (e.g. two OnReveals)
- Compound cards should have a bigger power penalty (see [Balance Guidelines](#balance-guidelines))
- The `abilityText` should describe all sub-abilities in one string

---

## Adding a New Location

Open `LocationDatabase.lua` and add a new entry.

### Location Template

```lua
MY_LOCATION = {
    name = "My Location",
    pointValue = 3,          -- Points awarded to the winner each turn (2-4)
    effect = nil,            -- Effect string or nil for vanilla
    effectText = nil,        -- Human-readable text or nil
},
```

### Required Fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | Display name |
| `pointValue` | number | Points to the player who wins this location each turn (typically 2-4) |
| `effect` | string or nil | The keyword effect string. `nil` for no effect |
| `effectText` | string or nil | Human-readable text. Must exist if `effect` exists |

### Vanilla Location Example

```lua
ANCIENT_ARENA = {
    name = "Ancient Arena",
    pointValue = 3,
    effect = nil,
    effectText = nil,
},
```

### Location With Effect Example

```lua
WAR_CAMP = {
    name = "War Camp",
    pointValue = 3,
    effect = "OnPlay:AddPower:Self:1",
    effectText = "Cards played here get +1 Power.",
},
```

---

## Location Effect Reference

Location effects use the same `Trigger:Effect:Params` format as card abilities, but with location-specific triggers.

### OnPlay Effects

Fire when a player places a card at this location.

#### `OnPlay:AddPower:Self:N`

Modify the placed card's power.

```lua
effect = "OnPlay:AddPower:Self:1"     -- +1 to each card played here
effect = "OnPlay:AddPower:Self:-2"    -- -2 to each card played here
```

**Existing locations:** War Camp (+1), Frozen Lake (-1), Enchanted Spring (+2), Cursed Bog (-2)

#### `OnPlay:AddPower:Self:PerTurn`

+1 per current turn number to the placed card. Cards played later in the game get a bigger bonus.

```lua
effect = "OnPlay:AddPower:Self:PerTurn"
```

**Existing locations:** Mirror Lake

#### `OnPlay:DrawCard:N`

Draw N cards when you play a card here.

```lua
effect = "OnPlay:DrawCard:1"   -- Draw 1 when you play here
effect = "OnPlay:DrawCard:2"   -- Draw 2 when you play here
```

**Existing locations:** Mana Well (1), Scholar's Tower (2)

#### `OnPlay:SummonToken:Opponent:Power`

When you play a card here, your **opponent** gets a token in a random empty slot at this location.

```lua
effect = "OnPlay:SummonToken:Opponent:1"   -- Opponent gets a 1-power token
```

**Existing locations:** Haunted Ruins

---

### StartOfTurn Effects

Fire at the beginning of each turn (after turn 1), before the planning phase.

#### `StartOfTurn:AddPower:AllHere:N`

+N to all cards at this location (both players' cards).

```lua
effect = "StartOfTurn:AddPower:AllHere:1"   -- +1 to all cards here each turn
effect = "StartOfTurn:AddPower:AllHere:2"   -- +2 to all cards here each turn
```

**Existing locations:** Verdant Grove (+1), Healing Shrine (+1), Growing Meadow (+2)

#### `StartOfTurn:DrawCard:BothPlayers:N`

Both players draw N extra cards at the start of each turn.

```lua
effect = "StartOfTurn:DrawCard:BothPlayers:1"   -- Both draw 1 extra
```

**Existing locations:** Library

---

### EndOfTurn Location Effects

Fire after card EndOfTurn abilities, before scoring.

#### `EndOfTurn:DestroyWeakest:Here`

Destroy the single weakest card at this location (either side). Ties go to whichever is found first. Triggers OnDestroy abilities.

```lua
effect = "EndOfTurn:DestroyWeakest:Here"
```

**Existing locations:** Death Hollow

#### `EndOfTurn:DamageAll:Here:N`

-N to all cards at this location (both sides) each turn.

```lua
effect = "EndOfTurn:DamageAll:Here:1"   -- -1 to all cards here
```

**Existing locations:** Volcanic Rift

---

### Restriction Effects

Prevent certain cards from being played at this location. Checked during validation before placement.

#### `Restrict:MinCost:N`

Only cards costing N or more can be played here.

```lua
effect = "Restrict:MinCost:3"   -- Only 3+ cost cards
effect = "Restrict:MinCost:5"   -- Only 5+ cost cards
```

**Existing locations:** Sky Temple (3), Titan's Gate (5)

#### `Restrict:MaxCost:N`

Only cards costing N or less can be played here.

```lua
effect = "Restrict:MaxCost:3"   -- Only 1-3 cost cards
```

**Existing locations:** Proving Grounds (3)

#### `Restrict:FrontRowOnly`

Each player can only use the front row (row 1) here.

```lua
effect = "Restrict:FrontRowOnly"
```

**Existing locations:** Dueling Grounds

#### `Restrict:NoOngoing`

Cards with any Ongoing ability (including compound abilities containing Ongoing) cannot be played here.

```lua
effect = "Restrict:NoOngoing"
```

**Existing locations:** Silence Chamber

#### `Restrict:NoAbility`

Only vanilla cards (cards with `ability = nil`) can be played here.

```lua
effect = "Restrict:NoAbility"
```

**Existing locations:** Sacred Grove

---

### Special Effects

#### `SuppressOnReveal`

A standalone keyword (not `Trigger:Effect` format). Prevents all OnReveal abilities from triggering at this location.

```lua
effect = "SuppressOnReveal"
```

**Existing locations:** Shadow Nexus, Wasteland

---

### Compound Location Effects

Locations can have multiple effects separated by `|`, just like cards:

```lua
effect = "OnPlay:AddPower:Self:-1|StartOfTurn:AddPower:AllHere:1"
```

This means cards played here get -1 power on play, but all cards here gain +1 each turn.

**Existing locations:** Blood Pit

**Rules:**
- Each sub-effect fires at its own trigger time
- Restriction sub-effects are always checked during placement validation
- You can combine any trigger types

---

## Balance Guidelines

### Power Curve

The baseline for a **vanilla** card (no ability) is:

```
power = cost * 2 - 1
```

| Cost | Vanilla Power | Examples |
|---|---|---|
| 1 | 1 | (Spark is 2 — slightly above curve) |
| 2 | 3 | Iron Guard (3) |
| 3 | 5 | Stone Golem (5) |
| 4 | 7 | War Beast (7) |
| 5 | 9 | Dragon (9) |
| 6 | 11 | Titan (12 — above curve as top-end reward) |

### Ability Tax

Cards with abilities should have **lower power** than the vanilla baseline. The stronger the ability, the bigger the tax:

| Ability Strength | Power Penalty | Example |
|---|---|---|
| Weak (draw 1, small buff) | -1 to -2 | Scout: cost 1, power 1 (baseline 1, -0) |
| Medium (conditional buff, debuff) | -2 to -3 | Healer: cost 3, power 2 (baseline 5, -3) |
| Strong (mass debuff, destroy) | -3 to -5 | Storm Mage: cost 5, power 5 (baseline 9, -4) |
| Game-changing (double power, global) | -5+ | Warlord: cost 5, power 1 (baseline 9, -8) |
| Compound (two abilities) | Extra -1 to -2 | Ancient Oak: cost 5, power 4 (baseline 9, -5) |

### Location Point Values

| Type | Typical Points | Rationale |
|---|---|---|
| Strong positive effect | 2 | Low stakes balance the benefit |
| No effect (vanilla) | 3-4 | Pure contest of power |
| Negative/mixed effect | 3-4 | High reward for dealing with the downside |
| Strong restriction | 3-4 | Fewer cards can be played, so higher stakes |

---

## Factions

Every card must belong to one of four factions:

| Faction | Theme | Play Pattern | Color Identity |
|---|---|---|---|
| **Arcane** | Magic, spells, knowledge | Card draw, OnReveal combos, faction synergy | Purple/Blue |
| **Iron** | Warriors, defense, strength | High-power vanilla, Ongoing buffs, raw stats | Red/Gray |
| **Wild** | Nature, growth, life | EndOfTurn growth, token generation, OnDestroy value | Green |
| **Shadow** | Trickery, disruption, death | Enemy debuffs, destruction, power manipulation | Dark Purple/Black |

### Faction-Synergy Abilities

These abilities reference factions by name using `Faction_X` or `PerFaction_X` in the target parameter. Replace `X` with the faction name exactly (case-sensitive):

```lua
-- Buff all Iron cards at this location
ability = "OnReveal:AddPower:Faction_Iron:1"

-- +1 per Arcane card you control
ability = "OnReveal:AddPower:PerFaction_Arcane:1"

-- Ongoing: +1 to all your Wild cards everywhere
ability = "Ongoing:AddPower:Faction_Wild:1"
```

Valid faction names: `Arcane`, `Iron`, `Wild`, `Shadow`

---

## Validation and Testing

### Running Validation

After adding content, run the built-in validators to catch errors:

```lua
-- In Roblox Studio console or a test script:
local CardDatabase = require(game.ReplicatedStorage.Modules.CardDatabase)
local LocationDatabase = require(game.ReplicatedStorage.Modules.LocationDatabase)

CardDatabase.validate()      -- Checks all cards
LocationDatabase.validate()  -- Checks all locations
```

The validators check:
- All required fields exist
- Ability strings parse correctly (colon-delimited format)
- Every ability has a matching resolver in AbilityRegistry
- Every card with an ability also has abilityText
- Point values are valid for locations

### Debug Helpers

```lua
CardDatabase.printAll()          -- Print all cards sorted by cost
CardDatabase.printByCost(3)      -- Print only 3-cost cards
LocationDatabase.printAll()      -- Print all locations

local AbilityRegistry = require(game.ReplicatedStorage.Modules.AbilityRegistry)
AbilityRegistry.printAllAbilities()  -- Print all parsed ability strings
AbilityRegistry.testParse()          -- Test parsing of sample strings
```

### Integration Testing

Run a bot-vs-bot match to test the full game loop with all content:

```lua
local MatchManager = require(game.ServerScriptService.MatchManager)
MatchManager.runTestMatch()  -- Runs a complete bot-vs-bot game
```

Run this **multiple times** (3-5) since locations are randomly selected each game. Watch the output for `WARNING` messages about missing resolvers.

---

## Updating the Starter Deck

The starter deck is defined in `GameConfig.lua` under `STARTER_DECK`. It must:

- Contain exactly **20 card IDs** (matching `DECK_SIZE`)
- Use IDs that exist in `CardDatabase`
- Have no duplicates (each card appears once)

```lua
STARTER_DECK = {
    "SPARK", "SCOUT", "SPROUT", "PHANTOM",
    "IRON_GUARD", "LOOKOUT", "BLOOM_FAIRY", "DARK_WHISPERER",
    "STONE_GOLEM", "HEALER", "SABOTEUR", "RIFT_SCHOLAR",
    "WAR_BEAST", "COMMANDER", "THORNGUARD", "SHIELD_WALL",
    "DRAGON", "SIEGE_ENGINE",
    "TITAN", "GRAND_ARCHIVIST",
},
```

### Deck Design Guidelines

- **Mana curve:** 4x 1-cost, 4x 2-cost, 4x 3-cost, 4x 4-cost, 2x 5-cost, 2x 6-cost
- **Faction balance:** Include cards from all four factions
- **Trigger variety:** Include at least one of each trigger type (OnReveal, Ongoing, EndOfTurn, OnDestroy, vanilla)
- **Complexity:** Avoid complex compound-ability cards in the starter — save those for collection/deckbuilding

---

## Adding New Ability Types (Advanced)

If none of the existing effects cover your design, you can add a new resolver.

### Adding a New OnReveal Effect

1. Open `AbilityRegistry.lua`
2. Find the `local onRevealResolvers = {}` section
3. Add a new resolver:

```lua
-- OnReveal:MyNewEffect:Param1:Param2
onRevealResolvers["MyNewEffect"] = function(gameState, sourceCard, playerID, locIdx, col, row, params)
    local param1 = params[1]
    local param2 = tonumber(params[2]) or 0

    -- Your logic here. Use GSU helpers:
    -- GSU.getCard(gameState, playerID, locIdx, col, row)
    -- GSU.setCard(gameState, playerID, locIdx, col, row, cardState)
    -- GSU.addModifier(card, sourceName, amount, isEnemySourced)
    -- GSU.getFriendlyCardsAt(gameState, playerID, locIdx, excludeCol, excludeRow)
    -- GSU.getEnemyCardsAt(gameState, playerID, locIdx)
    -- GSU.getEmptySlots(gameState, playerID, locIdx)
    -- GSU.pickRandom(list)
    -- GSU.drawCards(gameState, playerID, count)
    -- GSU.destroyCard(gameState, playerID, locIdx, col, row)
    -- GSU.getOpponent(gameState, playerID)
    -- GSU.getCurrentPower(cardState)
    -- GSU.countFactionCards(gameState, playerID, faction, excludeCol, excludeRow, excludeLocIdx)
    -- GSU.getFactionCardsAt(gameState, playerID, locIdx, faction, excludeCol, excludeRow)

    print(string.format("  [Ability] %s: did my new thing", sourceCard.cardID))
end
```

4. Now use it in CardDatabase: `ability = "OnReveal:MyNewEffect:foo:3"`

The same pattern applies for new Ongoing, EndOfTurn, and OnDestroy effects — just add to the corresponding resolver table (`ongoingResolvers`, `endOfTurnResolvers`, `onDestroyResolvers`).

### Adding a New Location Effect

1. Open `LocationEffectRegistry.lua`
2. Add to `onPlayResolvers`, `startOfTurnResolvers`, or `endOfTurnResolvers`
3. Location resolver signature differs from card resolvers:

```lua
-- OnPlay resolvers receive:
function(location, cardState, playerID, gameState, params)

-- StartOfTurn and EndOfTurn resolvers receive:
function(location, locIdx, gameState, params)
```

### Adding a New Restriction Type

1. Open `LocationRestrictions.lua`
2. Add to the `restrictionCheckers` table:

```lua
restrictionCheckers["MyRestriction"] = function(_location, cardDef, row, params)
    local threshold = tonumber(params[1]) or 0
    if cardDef and someCondition then
        return false, (cardDef.name or "Card") .. " blocked (reason)"
    end
    return true
end
```

3. Use it in LocationDatabase: `effect = "Restrict:MyRestriction:param1"`

### Resolver Function Parameters

**Card ability resolvers** all receive:

| Parameter | Type | Description |
|---|---|---|
| `gameState` | table | The full mutable game state |
| `sourceCard` | table | The card state object triggering the ability |
| `playerID` | string | The player who owns this card |
| `locIdx` | number | Which location (1 or 2) |
| `col` | number | Column position (1-3) |
| `row` | number | Row position (always 1 in current grid) |
| `params` | table | Array of string parameters from the ability string |

---

## Quick Reference Card

### Card Ability Cheat Sheet

```
-- DRAW
OnReveal:DrawCard:N
OnDestroy:DrawCard:N

-- BUFF SELF
OnReveal:AddPower:Self:N
EndOfTurn:AddPower:Self:N
OnReveal:ConditionalPower:Condition:N
OnReveal:SetPower:Highest_Enemy_Here

-- BUFF FRIENDLIES
OnReveal:AddPower:Location:N
OnReveal:AddPower:Column:N
OnReveal:AddPowerAll:N
EndOfTurn:AddPower:AllFriendlyHere:N
OnDestroy:AddPower:AllFriendlyHere:N
Ongoing:AddPower:Adjacent:N
Ongoing:AddPower:Location:N
Ongoing:AddPower:Row:N
Ongoing:AddPower:AllLocations:N
Ongoing:AddPower:Faction_X:N

-- DEBUFF ENEMIES
OnReveal:RemovePower:Random_Enemy_Here:N
OnReveal:RemovePower:All_Enemy_Here:N
EndOfTurn:DamageAll:N

-- DESTRUCTION
OnReveal:DestroyBelow:Threshold:Scope

-- TOKENS
OnReveal:SummonCopy:Adjacent:Power
OnReveal:FillLocation:TokenPower
EndOfTurn:SummonToken:Power
OnDestroy:SummonToken:Power

-- MOVEMENT
OnReveal:MoveThis:OtherLocation
OnReveal:Bounce:Target
OnDestroy:Bounce:Self

-- POWER TRICKS
OnReveal:SwapPower:Random_Enemy_Here
Ongoing:DoublePower:Location

-- DEFENSE
Ongoing:Immune
Ongoing:NoPowerReduction:Location

-- FACTION SYNERGY
OnReveal:AddPower:Faction_X:N
OnReveal:AddPower:PerFaction_X:N
Ongoing:AddPower:Faction_X:N

-- SPECIAL
OnReveal:RemovePower:Random_Friendly_Here:N
Ongoing:AddPower:Self:PerOngoing
```

### Location Effect Cheat Sheet

```
-- ON PLAY
OnPlay:AddPower:Self:N
OnPlay:AddPower:Self:PerTurn
OnPlay:DrawCard:N
OnPlay:SummonToken:Opponent:Power

-- START OF TURN
StartOfTurn:AddPower:AllHere:N
StartOfTurn:DrawCard:BothPlayers:N

-- END OF TURN
EndOfTurn:DestroyWeakest:Here
EndOfTurn:DamageAll:Here:N

-- RESTRICTIONS
Restrict:MinCost:N
Restrict:MaxCost:N
Restrict:FrontRowOnly
Restrict:NoOngoing
Restrict:NoAbility

-- SPECIAL
SuppressOnReveal
```
