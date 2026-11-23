# Torn City stats and action-timeline calculator

Scope: **`vagabond1215/TORN/docs/` only**. Published at [Torn City Guide › Stats](https://vagabond1215.github.io/TORN/#stats).

## Two views

The **four-stat training calculator** shows Strength, Defense, Speed, and Dexterity side by side, with current values, chosen Energy, gym dots, predicted gain, and source-specific bonuses. It uses Torn API v2 fields from `user/battlestats`, `user/bars`, `user/gym`, `user/perks` and `torn/gyms`. Combat modifiers (including drug stat penalties and combat merits) are listed **separately** from gym-gain bonuses.

The **ordered action simulator** replaces the old fixed counts of drugs, eDVDs and candy. Each strategy has an independent list that can be reordered, added to, edited or cleared. Actions are:

- Xanax, Ecstasy, candy, eDVD (each with optional quantity)
- Train available Energy; one daily points refill
- Wait for a fixed duration, or until drug cooldown / booster eligibility
- Turn automatic training of regenerated Energy on or off

Two editable scenarios, **Natural** and **Happy Jump**, simulate the **same** 1–168-hour period from the **same** starting stat/energy/happiness. The comparison plots the projected stat total through time and exposes an action-by-action execution table including time, Energy, Happy, drug cooldown and booster cooldown.

## Cooldown model

The engine uses **integer seconds**, not whole-hour or five-minute cooldown buckets.

- Xanax gives 250 Energy and 75 Happy; typical drug cooldown range **360–480 minutes**. The default model duration is **420 minutes**, configurable.
- Ecstasy doubles Happy and applies a drug cooldown of **200–230 minutes**. Default 215 minutes, configurable.
- A drug action can occur only when drug cooldown is zero. With automatic waiting enabled, the next action waits as long as required.
- An eDVD gives 2,500 Happy and adds 360 minutes of booster cooldown (unless a relevant, explicitly supplied perk changes its effectiveness).
- Each candy adds its chosen amount of Happy and normally 30 minutes of booster cooldown.
- **Booster cooldown is a use threshold, not a post-use hard cap.** A booster is legal while remaining cooldown is **strictly below** the threshold before the action. From zero cooldown, four eDVDs take it to 24 hours; after **one second**, the fifth is legal and leaves approximately **29:59:59**. If automatic waiting is disabled, the user must insert a one-second Wait action.
- Baseline booster limit 24h. Faction Voracity can increase it to 48h. Edit the threshold to match your character.
- Grocery Store 3-star consumable cooldown -10%; Restaurant 10-star -25%; the `Self Control Is For Losers` book -50% for consumables such as **candy**, **not eDVDs**. The model has separate candy and DVD cooldown factors, plus one-click common presets.
- eDVD Happy is increased to 5,000 at 10-star Adult Novelties. Select the corresponding preset where applicable.
- Current drug and booster cooldowns load from `user/cooldowns` when the authenticated API snapshot contains them. Perks that may affect cooldowns are listed for the user to review; they are **not automatically applied** unless their effects are explicitly configured.

All cooldowns decay through elapsed simulation time, including explicit waits. A normal energy refill restores the player's usual Energy cap rather than adding to a stacked Xanax reserve. Points refills are restricted to one per Torn calendar day (default clock from UTC/Torn time). The model applies an assumed +5 Energy per 10 or 15 minutes while below cap, +5 ordinary Happy per quarter-hour, and resets above-cap Happy at Torn's quarter-hour boundaries. The approximate next quarter-hour is editable.

## Gym gain model

For each gym train with `E` energy, normalized gym dots `D`, Happy `H`, current stat `S` and source-grouped perk multiplier:

```text
S_cap = S > 50,000,000 ? 50,000,000 + 0.057406 * (S - 50,000,000)^0.928996 : S
m_H   = 1 + 0.07 * ln(1 + H/250)
adj   = (1 - (min(H,99999)/99999)^2) * A
gain  = (S_cap*m_H + 8*H^1.05 + adj + B) / 200000 * D * E * Π(1+source_bonus)
```

Per-stat A/B values: STR 1600/1700, DEF 2100/-600, SPD 1600/2000, DEX 1800/1500. API effectiveness dots are normalized from ×10 stored units. Each train deducts ~0.5 Happy per Energy and updates the stat prior to the next train.

**This is a statistical estimator, not a guarantee.** In-game drug cooldowns vary; overdose and addiction progression, calendar events, special job-point energy conversions, dynamic prices and unsupported book effects are not simulated. Where the Torn API does not expose a usable perk detail, the estimate requires manual adjustment. No in-game actions or trades are performed.

## Sources

- [Torn Gym](https://wiki.torn.com/wiki/Gym)
- [Torn Item Cooldowns](https://wiki.torn.com/wiki/Item_Cooldowns)
- [Torn Drug](https://wiki.torn.com/wiki/Drug)
- [Torn Erotic DVD](https://wiki.torn.com/wiki/Erotic_DVD)
- [Torn Candy](https://wiki.torn.com/wiki/Candy)
- [Torn Happy](https://wiki.torn.com/wiki/Happy)
- [Torn API](https://www.torn.com/api.html)
