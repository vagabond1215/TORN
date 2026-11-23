# Torn City Stats & Happy-Jump Calculator

Scope: only the \`docs/\` Torn City Guide subtree of \`vagabond1215/TORN\`.

This page is available at [Torn City Guide › Stats](https://vagabond1215.github.io/TORN/#stats).

## Live inputs

The application calls Torn API v2 using the browser's existing in-memory key connection. Added selections:
- \`/v2/user/perks\` to identify faction Steadfast, education, property, job/company, book and other gym gain modifiers.
- \`/v2/torn/gyms\` for active and other gym dots and energy/train.

It also reads existing selections: \`/v2/user/battlestats\`, \`/v2/user/bars\`, \`/v2/user/gym\`. A limited API key is sufficient for most of these; the guide never stores the key.

Battle-stat modifiers (\`battlestats[stat].modifiers\`) reflect *effective combat* and are shown separately from the \`perks\` gym-gain modifiers. This avoids treating drug-induced combat reductions or combat merits as gym gain changes. Stat values and Energy, Happy, gym, individual bonuses, and scenario settings can be edited locally for what-if planning.

When API data is absent or restricted, fields show demo values or unavailable labels. The math does not silently claim bonuses were verified.

## Gain model

For each train of \`E\` energy, at gym effectiveness \`D\` (API tenths, e.g. 20 means 2.0), \`H\` happiness, and current trained stat \`S\`:

\`\`\`
S_cap = S > 50,000,000 ? 50,000,000 + 0.057406 * (S - 50,000,000)^0.928996 : S
m_H   = 1 + 0.07 * ln(1 + H/250)
adj   = (1 - (min(H,99999)/99999)^2) * A
gain  = (S_cap*m_H + 8*H^1.05 + adj + B) / 200000 * (D/10) * E * Π(1+source_bonus)
\`\`\`

Per-stat A/B: STR 1600/1700, DEF 2100/-600, SPD 1600/2000, DEX 1800/1500. Bonuses within a source group are additive, between sources multiplicative. Each train loses an estimated \`0.5 × E\` happiness, with stat value updated before the next train.

Sources:
- Official [Torn Gym wiki](https://wiki.torn.com/wiki/Gym#Training_Formulas): training variables, gym dots, happiness depletion.
- [Gym Gains Calculator+](https://github.com/Rowage3/torn-gym-gains-calculator-plus): calibrated post-50-million stat gain formula and source-grouped API v2 perks.
- [Happy Jump Guide](https://aidapaul.github.io/torn-happy-jumps/): drug/booster cadence, 30-point refill, Xanax energy stacking and happy-reset mechanics.

## Time comparison

The scenario engine runs in 5-minute ticks for 1–168 hours. Natural training spends energy promptly so +5 energy per 10/15 minutes continues while below the cap. Optional Xanax gives 250 energy with 8-hour spacing, Ecstasy doubles happiness, and selected candy contributes its configurable happiness. A points refill resets the energy bar to its normal maximum (30 points, at most once each 24h).

A stacked jump first trains starting energy before banking Xanax, banks 250 energy/dose (up to 1000), waits a final 8-hour cooldown, consumes eDVDs/candy, uses Ecstasy and trains the banked energy plus an optional refill in one session. For the **same wall-clock period**, unstacked energy regenerates after the jump.

There are scenario feasibility warnings for insufficient time and exceeding booster cooldown capacity. These are **estimates** and assume successful drug use, predictable 8-hour Xanax cooldown, one Ecstasy per scenario, 15-minute over-cap happy reset, 0.5 happiness spent per energy, instantaneous training, and a static selected gym/perks. No overdose, addiction-related gym disruption, shop-job training conversion, extra item perks/seasonal effects, real-time pricing changes, or special-gym eligibility transitions are simulated. Item prices are user-editable illustrative values, not live market quotes.

The graph displays projected **final stat totals** through time for both strategies. Results separately show gains, energy used, and item costs. Caution: the advanced gain formula is fitted, not guaranteed by the game; small stochastic errors are expected.
