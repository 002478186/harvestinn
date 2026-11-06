# Economy design

Every number here comes from `data/*.json`. The tables are generated with
`python3 tools/simulate_economy.py --tables`, so edit the data, not this file.
CI runs `simulate_economy.py --check`, which fails if any recipe loses value or
if the 7-day pacing drifts out of its target range.

## Currencies
- **Coins**: earned by serving guests, selling, deliveries and guest rooms; spent on seeds, buildings, upgrades, land and cosmetics.
- **Gems** (rare): +1 per level-up, +4 bonus every 5th level, daily rewards, achievements, tutorial. Used to finish timers: `gems = max(1, ceil(remaining_seconds / 600))`. Also used for a few premium cosmetics. **Nothing requires gems or money.**
- **XP → levels 1–50**: `xp_to_next(L) = round(20 · L^1.55)`.
- **Reputation**: +1 per meal served (+ furniture bonuses). Tiers unlock tables, order sizes and tips.

## Value chain (why each tier is worth the extra time)
| Tier | Example | Coins | Time |
|---|---|---|---|
| Raw crop | 2 carrot + 2 wheat sold at market | 20 | 5 min |
| Processed | the same, cooked into Carrot Stew, sold | 30 (×1.5) | +30 s |
| Inn service | Carrot Stew served to a guest | 38–45 (×1.9–2.25) | + waiting for a guest |
| Multi-tier | flour → bread + jam → Toast & Jam served | 213 from ~78 of raw crops (6 wheat + 3 strawberries) | 30–45 min |

Formulas:
- Recipe value ratio `Σ price(outputs) / Σ price(inputs)` is **≥ 1.15** for every recipe (checked in CI and unit tests; animal feed is exempt because it exists to feed animals). Longer chains have higher ratios, rewarding planning.
- Guest payment `round(Σ meal price × qty × 1.25 × (1 + 0.05 × tier_index))`.
- Market sell price `round(base price × demand)`, where `demand ∈ [0.8, 1.3]` is a deterministic hash of (item, UTC day). Everyone sees the same prices, and they change daily. Cap: 200 of each item per day.
- Deliveries: `coins = round(order value × 1.5)`, `xp = round(order value × 0.08)`, 3 slots, refilled 30 min after completion or skip.
- Guest rooms: `coins = coins_per_hour × min(hours since collect, 12)`.
- Animal happiness: +8 per feed, +15 per pet (1 h cooldown), −3 per hour; at ≥ 75 every cycle yields +1 of the main product.
- Online trading: list price must be within `[0.5×, 3×]` base price; a 5% listing fee (coin sink) is charged on sale.

## 7-day pacing (simulated)
The simulated player opens the app 4 times a day for 10 minutes and plays sensibly
(`tools/simulate_economy.py`). Targets: day 1 → L5–9, day 3 → L8–13, day 7 → L11–18.

```
day | level | coins | gems | rep | workshops | plots
  1 |     6 |  1170 |   19 |  12 |         2 |    20
  2 |     9 |  2900 |   22 |  36 |         3 |    24
  3 |    11 |  4521 |   28 |  56 |         4 |    30
  4 |    13 | 10339 |   30 |  77 |         4 |    30
  5 |    14 |  3431 |   31 |  91 |         5 |    35
  6 |    16 | 13889 |   37 | 113 |         5 |    35
  7 |    17 | 22981 |   38 | 121 |         5 |    35
```

So: tutorial and the first unlocks on day 1, the online market (L5) on day 1, chickens (L10) around day 3, cows (L14) around day 5, and goats/sheep in week 2–3.

## Tables

| Crop | Seed | Grow | Yield | Sell each | Profit/harvest | XP | Unlock |
|---|---|---|---|---|---|---|---|
| Wheat | 1 | 1 min | 2 | 3 | 5 | 1 | 1 |
| Carrot | 3 | 5 min | 2 | 7 | 11 | 2 | 1 |
| Potato | 4 | 10 min | 2 | 9 | 14 | 3 | 2 |
| Tomato | 6 | 20 min | 2 | 14 | 22 | 4 | 3 |
| Corn | 5 | 15 min | 2 | 11 | 17 | 3 | 4 |
| Onion | 7 | 30 min | 2 | 18 | 29 | 5 | 6 |
| Lettuce | 6 | 25 min | 2 | 16 | 26 | 5 | 7 |
| Strawberry | 10 | 60 min | 3 | 20 | 50 | 8 | 8 |
| Herbs | 8 | 40 min | 2 | 20 | 32 | 6 | 9 |
| Sunflower | 12 | 90 min | 2 | 32 | 52 | 10 | 11 |
| Pumpkin | 18 | 120 min | 2 | 45 | 72 | 12 | 12 |
| Blueberry | 20 | 180 min | 3 | 38 | 94 | 14 | 16 |
| Cabbage | 24 | 240 min | 2 | 52 | 80 | 16 | 20 |
| Bell Pepper | 28 | 300 min | 2 | 60 | 92 | 18 | 25 |

| Recipe | Building | Inputs | Output | Input value | Output value | Ratio | Time | XP | Unlock |
|---|---|---|---|---|---|---|---|---|---|
| bread | bakery | 2 Flour | 1 Bread | 28 | 40 | 1.43 | 10 min | 5 | 6 |
| corn_bread | bakery | 1 Flour, 2 Corn | 1 Corn Bread | 36 | 60 | 1.67 | 15 min | 7 | 7 |
| pumpkin_pie | bakery | 2 Flour, 2 Pumpkin, 2 Egg | 1 Pumpkin Pie | 142 | 260 | 1.83 | 60 min | 22 | 13 |
| strawberry_pie | bakery | 2 Flour, 3 Strawberry, 1 Butter | 1 Strawberry Pie | 138 | 210 | 1.52 | 40 min | 20 | 15 |
| cake | bakery | 2 Flour, 3 Egg, 1 Butter, 1 Cream | 1 Honey-Oat Cake | 162 | 330 | 2.04 | 90 min | 30 | 17 |
| pillow | craft_table | 4 Feather | 1 Pillow | 32 | 50 | 1.56 | 15 min | 6 | 11 |
| butter | dairy | 2 Milk | 1 Butter | 36 | 50 | 1.39 | 10 min | 5 | 14 |
| cream | dairy | 2 Milk | 1 Cream | 36 | 48 | 1.33 | 8 min | 5 | 14 |
| cheese | dairy | 3 Milk | 1 Cheese | 54 | 80 | 1.48 | 30 min | 10 | 15 |
| goat_cheese | dairy | 3 Goat Milk | 1 Goat Cheese | 66 | 100 | 1.52 | 30 min | 12 | 18 |
| strawberry_jam | jam_kitchen | 3 Strawberry | 1 Strawberry Jam | 60 | 90 | 1.50 | 15 min | 8 | 8 |
| tomato_sauce | jam_kitchen | 3 Tomato, 1 Onion, 1 Herbs | 1 Tomato Sauce | 80 | 110 | 1.38 | 15 min | 9 | 9 |
| blueberry_jam | jam_kitchen | 3 Blueberry | 1 Blueberry Jam | 114 | 160 | 1.40 | 30 min | 14 | 16 |
| carrot_stew | kitchen | 2 Carrot, 2 Wheat | 1 Carrot Stew | 20 | 30 | 1.50 | 30 s | 3 | 1 |
| baked_potato | kitchen | 2 Potato, 1 Wheat | 1 Baked Potato | 21 | 32 | 1.52 | 1 min | 3 | 2 |
| tomato_soup | kitchen | 2 Tomato, 1 Carrot | 1 Tomato Soup | 35 | 55 | 1.57 | 2 min | 5 | 3 |
| corn_chowder | kitchen | 2 Corn, 2 Potato | 1 Corn Chowder | 40 | 60 | 1.50 | 3 min | 5 | 4 |
| garden_salad | kitchen | 2 Lettuce, 1 Tomato, 1 Carrot | 1 Garden Salad | 53 | 90 | 1.70 | 2 min | 7 | 7 |
| toast_and_jam | kitchen | 1 Bread, 1 Strawberry Jam | 1 Toast & Jam | 130 | 170 | 1.31 | 2 min | 8 | 8 |
| herb_roast | kitchen | 2 Potato, 2 Carrot, 1 Herbs, 1 Onion | 1 Herb Roast Veggies | 70 | 120 | 1.71 | 5 min | 9 | 9 |
| veggie_omelette | kitchen | 2 Egg, 1 Onion, 1 Tomato | 1 Veggie Omelette | 56 | 95 | 1.70 | 3 min | 8 | 10 |
| pasta_pomodoro | kitchen | 2 Flour, 1 Tomato Sauce, 1 Herbs | 1 Pasta Pomodoro | 158 | 190 | 1.20 | 5 min | 12 | 10 |
| pancakes | kitchen | 1 Flour, 2 Egg, 2 Milk | 1 Fluffy Pancakes | 74 | 140 | 1.89 | 4 min | 10 | 14 |
| pumpkin_soup | kitchen | 1 Pumpkin, 1 Onion, 1 Cream | 1 Pumpkin Soup | 111 | 150 | 1.35 | 5 min | 11 | 14 |
| cheese_toastie | kitchen | 1 Bread, 1 Cheese | 1 Cheese Toastie | 120 | 175 | 1.46 | 4 min | 11 | 15 |
| goat_cheese_salad | kitchen | 1 Goat Cheese, 2 Lettuce, 1 Herbs | 1 Goat Cheese Salad | 152 | 230 | 1.51 | 5 min | 14 | 18 |
| stuffed_peppers | kitchen | 2 Bell Pepper, 1 Cheese, 1 Herbs | 1 Stuffed Peppers | 220 | 260 | 1.18 | 7 min | 16 | 25 |
| harvest_feast | kitchen | 1 Pumpkin Pie, 1 Herb Roast Veggies, 1 Bread, 1 Cheese | 1 Harvest Feast | 500 | 620 | 1.24 | 10 min | 35 | 28 |
| yarn | loom | 2 Wool | 1 Yarn | 60 | 80 | 1.33 | 20 min | 9 | 22 |
| blanket | loom | 3 Yarn | 1 Blanket | 240 | 300 | 1.25 | 60 min | 25 | 23 |
| sweater | loom | 2 Yarn | 1 Sweater | 160 | 240 | 1.50 | 45 min | 20 | 24 |
| flour | mill | 3 Wheat | 1 Flour | 9 | 14 | 1.56 | 2 min | 2 | 4 |
| animal_feed | mill | 2 Corn, 1 Wheat | 3 Animal Feed | 25 | 24 | 0.96 | 3 min | 2 | 9 |
| sunflower_oil | mill | 2 Sunflower | 1 Sunflower Oil | 64 | 95 | 1.48 | 20 min | 8 | 11 |
| soap | soap_maker | 2 Goat Milk, 2 Herbs | 1 Herb Soap | 84 | 120 | 1.43 | 30 min | 12 | 19 |

| Level | XP to next |  | Level | XP to next |
|---|---|---|---|---|
| 1 | 20 | | 26 | 3121 |
| 2 | 59 | | 27 | 3309 |
| 3 | 110 | | 28 | 3500 |
| 4 | 171 | | 29 | 3696 |
| 5 | 242 | | 30 | 3896 |
| 6 | 321 | | 31 | 4099 |
| 7 | 408 | | 32 | 4305 |
| 8 | 502 | | 33 | 4516 |
| 9 | 603 | | 34 | 4730 |
| 10 | 710 | | 35 | 4947 |
| 11 | 823 | | 36 | 5168 |
| 12 | 941 | | 37 | 5392 |
| 13 | 1066 | | 38 | 5619 |
| 14 | 1195 | | 39 | 5850 |
| 15 | 1330 | | 40 | 6084 |
| 16 | 1470 | | 41 | 6322 |
| 17 | 1615 | | 42 | 6562 |
| 18 | 1765 | | 43 | 6806 |
| 19 | 1919 | | 44 | 7053 |
| 20 | 2078 | | 45 | 7303 |
| 21 | 2241 | | 46 | 7556 |
| 22 | 2409 | | 47 | 7812 |
| 23 | 2581 | | 48 | 8071 |
| 24 | 2756 | | 49 | 8334 |
| 25 | 2937 | | 50 | 8599 |
