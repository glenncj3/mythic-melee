# Mythic Mash UI Improvement Plan

Complete UI overhaul plan. The new layout draws inspiration from Marvel Snap's board design: a physical "table surface" feel, location info centered as the divider between player sides, bold energy indicators, and vibrant colors with glowing edges. Adapted for Mythic Mash's 2-location, 1x3 grid format.

**Grid change:** All grids move from 2 rows x 3 columns to **1 row x 3 columns** per side. This is required to maintain card-shaped (3:4 portrait) slots at playable sizes across mobile, tablet, and desktop. `GameConfig.GRID_ROWS` changes from 2 to 1, `SLOTS_PER_LOCATION` from 6 to 3.

Each phase is shippable independently and ordered by player impact.

**Files touched across all phases:**
- `MatchClient.client.lua` — layout, colors, animation, interaction
- `CardFrame.lua` — card rendering, rarity visuals
- `GameConfig.lua` — grid dimensions

---

## Phase 1: Layout Restructure & Board Feel

**Goal:** Rebuild the board layout around 1x3 grids, centered location info, and a table-surface aesthetic.

### 1A. Grid Dimension Change
- `GameConfig.GRID_ROWS`: 2 -> 1
- `GameConfig.SLOTS_PER_LOCATION`: 6 -> 3
- Update `createSlotGrid` loop to iterate 1 row only
- Update `SlotGrid.lua` adjacency logic (no vertical neighbors with 1 row)
- Verify `MatchManager`, `GameServer`, `BotPlayer`, and `AbilityRegistry` all respect the new row count (they read from `GameConfig` so should just work, but test)

### 1B. Location Panel — Centered Info Divider
Restructure each location panel's vertical layout. The location name and effect text move to the **center** of the panel, acting as a divider between opponent and player rows:

```
+---------------------------------------+
|  Opponent row (1x3 card slots)        |   ~35% of panel
|---------------------------------------|
|     [pts badge]  Location Name        |   ~18% of panel (centered info band)
|     Effect description text           |
|---------------------------------------|
|  Player row (1x3 card slots)          |   ~35% of panel
+---------------------------------------+
|  You: 12  |  Opp: 8                   |   ~12% (power totals footer)
+---------------------------------------+
```

- Remove the old "OPPONENT" / "YOUR SIDE" 9px labels — the spatial position (top = them, bottom = you) is self-evident with the divider in place
- Location name: 17px GothamBold, centered, white
- Effect text: 12px GothamMedium, centered, gold/amber tint
- Point value: rendered as a circular badge (gold background, white text, 16px) to the left of the location name

### 1C. Board Surface Feel
- Add a subtle outer border to the entire board area — a rounded Frame with a soft glowing UIStroke (color: muted blue or purple, thickness: 2px, transparency: 0.3)
- Each location panel gets a UIGradient — slightly lighter in the center (where the location info sits), darker at top and bottom edges. This creates a subtle "raised surface" feel
- Add a thin inner bevel: a 1px lighter-colored UIStroke on location panels (gives the panel a slight 3D edge)
- Board background behind the panels: keep very dark but add a faint radial gradient (dark center to slightly lighter edges) to simulate a tabletop surface

### 1D. Card Slot Sizing
With 1 row x 3 columns per grid, slots become much larger. Target sizes per device:

| Device | Grid area | Slot size (3:4) | Status |
|--------|-----------|-----------------|--------|
| Mobile (812x375) | 346 x 98px | 74 x 98px | Good — meets 44px touch target |
| Tablet (1024x768) | 436 x 200px | 135 x 180px | Generous |
| Desktop (1920x1080) | 841 x 280px | 189 x 252px | Large |

- Cards fill their slots with 4px inner padding (card frame = slot size - 8px)
- Remove `CardFrame.SIZE_PRESETS.board` fixed pixel size — board cards now inherit slot dimensions
- Keep `hand` and `detail` presets as fixed pixel sizes

### 1E. Hand Area Redesign
- Increase hand card size from 90x120 to **110x147** (maintains 3:4 ratio, more prominent)
- Hand tray: instead of a flat embedded ScrollingFrame, give it a slight "shelf" look — darker background with a top-edge highlight (1px lighter line), as if cards sit on a raised surface
- Selected card lifts above the hand tray (tweened, see Phase 3)
- Cards that can't be afforded: reduce opacity AND apply a desaturating tint (darken the card frame background)

### 1F. Energy Indicator Overhaul
Replace the text label `"Energy: 3 / 5"` with a visual indicator:
- A circular frame (44x44px) in the bottom-left of the control row
- Filled portion represented by colored segments or a simple number on a glowing circle
- Background ring: dark gray. Fill color: bright blue `(80, 150, 255)`
- Large centered number showing available energy (24px GothamBold)
- Small "/ max" text below the circle (11px, gray)
- When energy is spent on pending plays, the number updates and the spent portion of the ring dims

### 1G. Score Bar Rework
- Turn counter centered and prominent: `"TURN 3"` at 22px GothamBold
- Player score (right of center): just the number in green, 20px, with a small sword/shield icon or colored pip before it
- Opponent score (left of center): just the number in red, 20px, matching pip
- Win threshold shown as a subtle progress element: a thin horizontal bar under the score bar, with green fill from the right (player progress toward 20) and red fill from the left (opponent progress toward 20)
- Remove the separate `"/ 20"` text label — the progress bar replaces it

---

## Phase 2: Color Palette & Contrast

**Goal:** Shift from muddy near-blacks to a rich, readable dark theme with vibrant accents.

### 2A. Updated Color Table

| Token | Current | New | Rationale |
|-------|---------|-----|-----------|
| `bg` | (18,18,24) | (10,10,18) | Deepest layer, true dark |
| `boardSurface` | N/A | (20,22,32) | New: board area background behind panels |
| `panel` | (28,30,40) | (32,36,52) | Panels clearly lifted above board |
| `panelBorder` | (55,60,80) | (70,80,110) | More visible panel edges |
| `panelGlow` | N/A | (60,80,160) | New: subtle outer glow on panel border |
| `centerBand` | N/A | (25,28,42) | New: location info divider strip |
| `oppRow` | (40,25,25) | (50,25,30) | Opponent row — warmer red tint, more visible |
| `myRow` | (25,35,40) | (25,35,55) | Player row — cooler blue tint, more visible |
| `slotEmpty` | (35,38,50) | (42,46,62) | Empty slots clearly defined |
| `slotEmptyOpp` | (50,30,30) | (58,32,36) | Opponent slots visible |
| `scoreBarBg` | (15,15,20) | (14,14,22) | Score bar darker than board |
| `bottomBg` | (22,22,30) | (18,20,30) | Hand tray — slight step above bg |
| `confirm` | (45,160,75) | (40,170,80) | Slightly more saturated green |
| `energyColor` | (80,150,255) | (70,140,255) | Bright blue energy, slightly purer |
| `slotHighlight` | (50,180,80) | (50,200,90) | Brighter valid-slot green |

### 2B. Accent Glow System
- Location panels: add a faint glowing UIStroke (2px, `panelGlow` color, transparency ~0.5) — gives a subtle neon edge
- Selected hand card: glow border (green, 3px, slight transparency)
- Winning location: panel glow shifts to green
- Losing location: panel glow shifts to red
- These glows are the primary way the board communicates state at a distance

### 2C. Grid Row Differentiation
- Opponent row background: visible warm red tint `(50,25,30)` — clearly "their territory"
- Player row background: visible cool blue tint `(25,35,55)` — clearly "your territory"
- The centered location info band provides a natural visual break between the two
- No need for text labels — color coding + position is enough

---

## Phase 3: Interaction Feedback & Animation

**Goal:** Every player action gets a visible, satisfying response.

### 3A. Card Selection
- On tap: tween card scale from 1.0 to 1.08 and Y position up by 10px over 0.15s (Quad, Out)
- Add a green glowing UIStroke (3px) that tweens in from 0 to full opacity over 0.1s
- On deselect: reverse both tweens
- Valid slots light up simultaneously (see 3C)

### 3B. Card Placement
- Pending card tweens into the slot from its hand position over 0.2s (Quad, Out)
- Slot border flashes bright green for 0.15s then settles to a steady green glow
- Pending cards display with a gentle pulsing transparency (loop tween 0.3 <-> 0.45 over 1.5s)
- Card disappears from hand with a quick scale-to-zero tween (0.1s)

### 3C. Slot Highlighting
- When a card is selected, valid empty slots get a pulsing green border (tween stroke opacity 0.3 <-> 0.8, loop, 1s period)
- Occupied slots that allow overwrite get a pulsing orange border
- Invalid slots stay neutral — no change
- When card is deselected/placed, all slot highlights tween back to neutral

### 3D. Invalid Play Feedback
- Red toast notification: a TextLabel that slides down from the top of the board, holds 1.5s, slides back up
- Styled: red background `(180,40,40)` with rounded corners, white text, 14px GothamBold
- Messages: "Not enough energy", "Restricted by [Location Name]", "Invalid placement"
- The offending card or slot also flashes its border red (tween to red and back over 0.3s)
- Wire into: `onHandCardClicked` (can't afford), `onSlotClicked` (location restriction), `InvalidPlayEvent`

### 3E. Timer Urgency Escalation
- 30-10s: timer displays normally, white text, 20px
- 10-5s: slow pulse on timer text (scale 20px <-> 22px, 1s loop). Timer text turns amber
- 5-3s: faster pulse (0.5s loop). Timer text turns red. A subtle red vignette begins fading in at screen edges (a frame with UIGradient, red at edges, transparent center)
- 3-0s: vignette intensifies. Timer pulses rapidly. Bottom panel border flashes red

### 3F. Score Update Animation
- Floating "+N" or "-N" label spawns next to the score, tweens upward 30px and fades out over 0.8s
- Score number itself does a brief scale pulse (1.0 -> 1.15 -> 1.0, 0.3s, Back ease)
- Green for player gains, red for opponent gains

### 3G. Game Over Reveal
Staggered entrance sequence:
1. **0.0s** — Dim overlay fades in (BackgroundTransparency 1.0 -> 0.25 over 0.4s)
2. **0.3s** — Result text scales from 0.5 to 1.0 with bounce (0.4s, Back ease). "VICTORY!" in gold, "DEFEAT" in red, "DRAW" in white
3. **0.7s** — Final score + location breakdown fades in (0.3s)
4. **1.0s** — Buttons slide up from below and fade in (0.3s)

### 3H. Confirm Button Polish
- MouseEnter: tween background to `confirmHover`, scale to 1.02 (0.1s)
- MouseLeave: tween back to `confirm`, scale to 1.0 (0.1s)
- MouseButton1Down: scale to 0.96 (0.05s)
- MouseButton1Up: scale back to 1.02 then 1.0 (0.1s)
- "Waiting..." state: pulsing text opacity (0.5 <-> 1.0, 1.5s loop)

---

## Phase 4: Card Visual Improvements

**Goal:** Cards feel like collectible game pieces with clear at-a-glance identification.

### 4A. Art Area Enhancement
- Replace flat color fill with a UIGradient: artColor at top-left, 25% darker variant at bottom-right (gives dimensionality)
- Add a 1px inner UIStroke on the art frame, 15% lighter than artColor (subtle inner bevel)
- Board-size cards: remove the name TextLabel from the art area (unreadable at small sizes). Let art color + cost/power badges identify the card. Players tap for detail view.

### 4B. Rarity Border Progression
Each rarity tier should be visually distinct at a glance:

| Rarity | Stroke | Thickness | Extra |
|--------|--------|-----------|-------|
| Common | White (200,200,200) | 2px | None |
| Uncommon | Green (80,200,80) | 2px | Faint green outer glow (second UIStroke, 4px, 0.7 transparency) |
| Rare | Blue (60,120,255) | 3px | Blue outer glow (second UIStroke, 5px, 0.6 transparency) |
| Legendary | Gold (255,200,40) | 3px | Gold outer glow + animated shimmer (UIGradient rotation tween, 3s loop) |

### 4C. Ability Type Indicator
Small colored pip in the top-right corner of the card frame:
- **On Reveal**: orange pip (255,160,40)
- **Ongoing**: teal pip (40,200,180)
- **Vanilla** (no ability): no pip
- Pip size: 10px on board cards, 14px on hand cards, 18px on detail cards
- Pip has a 1px dark outline so it reads against any art color
- Lets players scan the board and instantly identify which cards have active effects

### 4D. Cost & Power Badge Improvements
- Size badges as a percentage of card width (26%) rather than font-size math — consistent proportions across all display sizes
- Add a 1px dark UIStroke outline on each badge so they pop against light art colors
- Cost badge: blue circle, top-left, white number
- Power badge: gold/amber circle, bottom-right, white number
- Power change animation: when `updatePower` is called, flash the badge (scale 1.0 -> 1.3 -> 1.0 over 0.3s, Quad ease). Green text if above base, red if below

### 4E. Hand Card Sizing
- Increase hand preset from (90,120) to (110,147) — 3:4 ratio, more readable
- Detail preset stays at (240,340) — already generous

---

## Phase 5: Information Architecture

**Goal:** The board state tells the player everything they need without mental math.

### 5A. Location Win/Loss Indicator
In `updatePowerTotals`, after comparing myPower vs oppPower:
- **Winning**: tween the location panel's UIStroke color to green `(50,200,90)`, thickness to 2px
- **Losing**: tween to red `(200,50,50)`
- **Tied**: tween back to neutral `panelGlow`
- Add a small text badge below the power totals: "WINNING" (green), "LOSING" (red), "TIED" (gray), 10px GothamBold

### 5B. Location Point Value Badge
- Render point value as a circular badge (gold background, white number) to the left of the location name in the center info band
- Size: 22x22px, 14px text
- This is the most strategically important number — it determines how many points winning this location awards

### 5C. Energy Cost Preview
When a card is selected from hand, update the energy indicator to show the projected spend:
- Circle shows current available energy
- A secondary arc or number shows "after placement" value in a dimmer shade
- Example: if energy is 5/5 and a 3-cost card is selected, show "5" with a small "(-3)" beneath in orange
- Updates in real-time as the player selects different cards

### 5D. Score Progress Bar
- Thin horizontal bar (4px tall) directly below the score bar
- Green fill from right side = player score / 20
- Red fill from left side = opponent score / 20
- When fills meet or cross, the game is approaching its end — creates visual tension
- A small white tick mark at the center (the "20" win line) anchors the scale

### 5E. Opponent Card Inspection
- Wire up `onOppSlotClicked` to open the detail overlay for the tapped opponent card
- Identical to the player card detail overlay but with a red-tinted border to indicate "opponent's card"
- Allows strategic assessment of opponent board state

---

## Phase 6: Lobby & Game Over Polish

**Goal:** Strong first and last impressions.

### 6A. Lobby Screen
- **Background**: dark with a subtle animated element — 3-4 card frames from the starter deck arranged in a spread behind the title, slowly rotating or drifting
- **Entrance animation**: title scales up from 0.8 to 1.0 + fades in (0.4s), subtitle fades in (0.3s, delayed 0.3s), button slides up + fades in (0.3s, delayed 0.6s)
- **"Searching..." state**: replace button text with a pulsing animation (dots cycling: "." -> ".." -> "..." every 0.4s). Add a subtle spinning ring indicator below the button
- **Play vs Bot button**: give it a soft green glow (UIStroke, 2px, slight transparency) to draw the eye

### 6B. Game Over Screen
- Add **"Play Again"** button next to "Return to Lobby" (fires `RequestBotMatchEvent` directly, skips lobby)
- Show per-location breakdown below the final score:
  ```
  Crystal Cavern (2 pts): You 12 | Opp 8 — WON
  Dragon's Peak (3 pts):  You 5  | Opp 9 — LOST
  ```
- Each line color-coded: green for won locations, red for lost, white for tied
- Apply the staggered entrance animation from Phase 3G

### 6C. Screen Transitions
- **Lobby -> Match**: quick fade to black (0.2s), hold (0.1s), fade in match board (0.3s)
- **Match -> Game Over**: the overlay fade from 3G handles this
- **Game Over -> Lobby**: fade to black (0.2s), hold (0.1s), fade in lobby (0.3s)
- Implement as a shared `screenTransition(callback)` utility function

---

## Phase 7: Mobile & Responsiveness

**Goal:** Playable and readable on every device.

### 7A. Touch Target Verification
With 1x3 grid, slot sizes on mobile (812x375) are ~74x98px — well above the 44px minimum. No changes needed for slots.

Verify these elements also meet 44px minimum:
- Confirm button (currently 0.22 width x 34px height — height is below 44px on all devices, increase to 44px)
- Energy indicator (44x44 per redesign — good)
- Hand cards at 110x147 — good

### 7B. Scale-Based Layout
Convert fixed-pixel dimensions to proportional where appropriate:
- Score bar: `UDim2.new(1, 0, 0.045, 0)` instead of `(1, 0, 0, 40)`
- Control row: `UDim2.new(1, 0, 0.055, 0)` instead of `(1, 0, 0, 40)`
- Board area: keep at 60% (already proportional)
- Bottom area: keep at 32% (already proportional)
- Card sizes (hand, detail): keep as fixed Offset with 3:4 ratio — scale the fixed values based on screen height at initialization using `Camera.ViewportSize`

### 7C. Safe Area & GUI Inset
- Set `IgnoreGuiInset = true` on both lobby and match ScreenGuis for consistency
- Add top padding to the score bar (UIPadding, PaddingTop = 4-8px) to clear Roblox's top bar
- On mobile: detect `UserInputService.TouchEnabled` and add extra bottom padding to the hand tray for the home indicator

### 7D. Aspect Ratio Handling
- **Portrait phones** (rare for Roblox but possible): stack the two location panels vertically instead of horizontally. Detect with `ViewportSize.X < ViewportSize.Y`
- **Ultrawide (>2.5:1 aspect)**: cap the board frame width at a maximum and center it. Fill the sides with the dark background
- **Standard landscape (16:9 to 16:10)**: default layout, no changes needed

---

## Implementation Notes

### Sequencing
Phases 1 and 2 should be done together — the layout restructure and color update are tightly coupled. After that, each phase is truly independent.

### Testing Checklist
For each phase, verify in Roblox Studio device emulator:
- [ ] iPhone SE (smallest common phone)
- [ ] iPhone 14 Pro (standard phone)
- [ ] iPad (tablet)
- [ ] 1080p desktop
- [ ] Full 7-card hand + partially filled boards (worst-case readability)
- [ ] Before/after screenshots archived

### Animation Performance
- All tweens via `TweenService:Create()`, durations under 0.5s
- Cancel active tweens before starting new ones on the same property (`:Cancel()`)
- Target max ~15 simultaneous tweens (card placement + slot highlights + pending pulses)
- Test on Roblox graphics quality level 1 (lowest) for frame drops

### Color Tuning
- All RGB values are starting points — fine-tune by eye with the game running
- Test on a low-brightness monitor and on mobile in bright ambient light
- The glow/stroke effects in Phase 2B may need transparency adjustments per device — keep these as tunable constants at the top of the file

### What Doesn't Change
- Server protocol, RemoteEvents, game logic — untouched
- CardDatabase schema — ability indicator reads existing `ability` field
- Turn/energy/scoring mechanics — purely visual changes
- Number of locations (2) — unchanged
