# Torn City stats and action-timeline calculator

Scope: **`vagabond1215/TORN/docs/` only**. Published at [Torn City Guide › Stats](https://vagabond1215.github.io/TORN/#stats).

## Two views

The **four-stat training calculator** shows Strength, Defense, Speed, and Dexterity side by side, with current values, chosen Energy, gym dots, predicted gain, and source-specific bonuses. It uses Torn API v2 fields from `user/battlestats`, `user/bars`, `user/gym`, `user/perks` and `torn/gyms`. Combat modifiers (including drug stat penalties and combat merits) are listed **separately** from gym-gain bonuses.

The **Plan** view runs NAT, MAX E, MINI, LOW#, HJ, 99k and CUSTOM on a common window. It starts at 24 hours and extends as needed for the selected Happy Jump preparations. The chart adds one hour beyond the comparison endpoint for display.

- NAT starts at zero Energy and schedules an editable Train each time the bar fills.
- MAX E, MINI and LOW# start at full Energy. After their opening actions the defaults train full bars and take Xanax as soon as the drug cooldown clears, spending accumulated usable Energy before the dose and training immediately after it.
- HJ and 99k start at zero Energy and stack four Xanax. HJ defaults to five eDVDs. 99k assumes separately arranged Poison Mistletoe to reach at least 50,000 Happy before Ecstasy and has no projected total cost.
- CUSTOM accepts the same individual actions. Candy and eDVD rows can represent immediate batches.

Use the timeline controls to edit, add, remove or reorder player actions. Cooldown waits, Energy waits, relevant Happiness resets and training of any remaining usable Energy at the endpoint are automatic. Edited plans, starting values and comparison selections are saved per account in the browser. Reset regenerates that template's action list for the current comparison window.

## Cooldown model

The engine tracks time in integer seconds. Xanax adds 250 Energy and 75 Happy and has a modeled 420-minute cooldown. Ecstasy doubles Happy up to 99,999 and has a modeled 215-minute cooldown. The Settings disclosure can use live drug and booster cooldowns from the cached Torn API snapshot.

- Natural Energy regenerates below the cap. Standard accounts get 5 Energy every 15 minutes with a 100-Energy cap. Donators and Subscribers get 5 every 10 minutes with a 150-Energy cap.
- A points refill restores the usual Energy cap and can be used once per Torn calendar day.
- An eDVD gives 2,500 Happy and adds 360 minutes of booster cooldown. Candy adds its listed Happy and normally adds 30 minutes of booster cooldown. Applicable detected candy perks reduce that duration.
- The model allows a final booster at the cooldown threshold with zero simulated time between items. From zero cooldown and a 24-hour threshold, that allows five eDVDs or up to 49 candy, subject to inventory for Candy MAX. Existing cooldown can reduce the available batch.
- Happiness above the player's maximum resets at Torn quarter-hour boundaries. Ordinary Happiness recovers by 5 at each boundary up to the player's maximum.

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


## Minimal visual stat summary (November 2026)

The top of the Stats page remains a single horizontal row of Strength, Defense, Speed and Dexterity above Gym, Calc and Plan. On small screens, the row scrolls horizontally rather than wrapping into two columns. The Home and Jobs pages use compact key/value lists for Battle and Working stats so the account summary resembles Torn's in-game sidebar without duplicating the entire interface.
