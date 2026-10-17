# Compare: baseline -> default

base: `hop_s=0.25, buffer_s=1.0, gate_db=-50.0, gate_window_s=0.0, persist=2, other_veto=False, other_veto_margin=0.15, veto_exempt_priority=8, label_margin=0.0, loud_ref_db=-50.0, loud_floor=0.2, input_gain_db=0.0, clip_level=0.99`  
new:  `hop_s=0.1, buffer_s=1.0, gate_db=-70.0, gate_window_s=0.1, persist=5, other_veto=True, other_veto_margin=0.15, veto_exempt_priority=8, label_margin=0.1, loud_ref_db=-60.0, loud_floor=0.2, input_gain_db=0.0, clip_level=0.99`

## Per class at -20 dBFS

| class | caught base -> new | wrong base -> new |
|---|---|---|
| alarm | 1.00 -> 1.00 | 0.12 -> 0.00 |
| appliance | 0.94 -> 0.94 | 0.50 -> 0.00 |
| baby_cry | 1.00 -> 1.00 | 0.25 -> 0.00 |
| car_horn | 1.00 -> 1.00 | 0.12 -> 0.00 |
| cat | 1.00 -> 1.00 | 0.38 -> 0.12 |
| clap | 1.00 -> 1.00 | 0.38 -> 0.12 |
| dog | 1.00 -> 1.00 | 0.00 -> 0.00 |
| footsteps | 0.75 -> 0.75 | 0.62 -> 0.38 |
| glass_break | 1.00 -> 1.00 | 0.00 -> 0.00 |
| knock | 1.00 -> 1.00 | 0.00 -> 0.12 |
| siren | 1.00 -> 1.00 | 0.75 -> 0.12 |
| speech | 1.00 -> 1.00 | 0.00 -> 0.00 |

## Mean caught / wrong per level

| level | caught base -> new | wrong base -> new |
|---|---|---|
| -50 dB | 0.00 -> 0.98 | 0.00 -> 0.04 |
| -40 dB | 0.05 -> 0.98 | 0.01 -> 0.03 |
| -30 dB | 0.81 -> 0.98 | 0.08 -> 0.04 |
| -20 dB | 0.99 -> 0.98 | 0.13 -> 0.03 |
| -10 dB | 0.99 -> 0.95 | 0.14 -> 0.04 |

## False fires per minute

| source | total base -> new | safety | babies | privacy | household |
|---|---|---|---|---|---|
| other clips | 9.30 -> 2.40 | 4.00 -> 0.50 | 0.40 -> 0.00 | 0.60 -> 0.00 | 4.30 -> 1.90 |
| background only | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 |

## Overlap

at least one 1.00 -> 0.98, both 0.57 -> 0.33, third class 0.20 -> 0.04


## OOV

clips with any fire: 146/304 -> 55/304


## Regression guard

passed (no class lost more than 0.05 caught rate at -20 dBFS, no source gained more than 0.2 false fires/min)
