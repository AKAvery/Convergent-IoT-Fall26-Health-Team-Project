# Live-pipeline evaluation: adpcm

params: `hop_s=0.1, buffer_s=1.0, gate_db=-70.0, gate_window_s=0.1, persist=5, other_veto=True, other_veto_margin=0.15, veto_exempt_priority=8, label_margin=0.1, loud_ref_db=-60.0, loud_floor=0.2, input_gain_db=0.0, clip_level=0.99`  
model: `/Users/averyallen/Coding Projects/Convergent-IoT-Fall26-Health-Team-Project/pi`  
background: white noise at -70 dBFS  
test split: 336 clips from work/manifest.csv

> Digital attenuation has no room acoustics or mic self-noise, so the -40/-50 dB rows measure the gate and ranking, not the microphone. `--playback` is the honest test of the laptop setup.

## Streamed confusion (every test clip at -20 dBFS peak)

| class | n | caught | wrong label | wrong shown big | big-label acc | onset med / p90 s |
|---|---|---|---|---|---|---|
| alarm | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.75 / 1.06 |
| appliance | 16 | 0.88 | 0.00 | 0.00 | 1.00 | 1.20 / 2.48 |
| baby_cry | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 1.95 / 3.09 |
| car_horn | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.95 / 1.38 |
| cat | 8 | 1.00 | 0.12 | 0.12 | 0.98 | 0.70 / 1.54 |
| clap | 8 | 1.00 | 0.12 | 0.12 | 0.99 | 0.75 / 1.13 |
| dog | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.70 / 1.04 |
| footsteps | 8 | 0.75 | 0.50 | 0.50 | 0.81 | 1.55 / 3.85 |
| glass_break | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.95 / 1.19 |
| knock | 8 | 1.00 | 0.25 | 0.12 | 0.99 | 0.75 / 0.93 |
| siren | 8 | 1.00 | 0.12 | 0.12 | 1.00 | 1.25 / 2.41 |
| speech | 120 | 1.00 | 0.00 | 0.00 | 1.00 | 0.50 / 0.80 |
| **mean** | | **0.97** | **0.09** | | | |

'other' test clips with any target fired: 0.22 (n=120)

Fired-class matrix (rows = true, cols = fired at least once; clips):

| true \ fired | alarm | appli | baby_ | car_h | cat | clap | dog | foots | glass | knock | siren | speec |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| alarm | 8 | · | · | · | · | · | · | · | · | · | · | · |
| appliance | · | 14 | · | · | · | · | · | · | · | · | · | · |
| baby_cry | · | · | 8 | · | · | · | · | · | · | · | · | · |
| car_horn | · | · | · | 8 | · | · | · | · | · | · | · | · |
| cat | · | · | · | · | 8 | · | 1 | · | · | · | · | · |
| clap | · | · | · | · | · | 8 | · | · | · | 1 | · | · |
| dog | · | · | · | · | · | · | 8 | · | · | · | · | · |
| footsteps | · | · | · | · | · | · | · | 6 | 1 | 3 | · | · |
| glass_break | · | · | · | · | · | · | · | · | 8 | · | · | · |
| knock | · | · | · | · | · | · | · | 2 | · | 8 | · | · |
| siren | 1 | · | · | · | · | · | · | · | · | · | 8 | · |
| speech | · | · | · | · | · | · | · | · | · | · | · | 120 |
| other | 1 | 5 | · | 1 | 1 | 3 | 4 | 5 | 2 | 6 | · | · |

## Level sweep (clip peak dBFS; digital attenuation, no room)

Caught rate:

| class | -10 dB | -20 dB | -30 dB | -40 dB | -50 dB |
|---|---|---|---|---|---|
| alarm | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| appliance | 0.94 | 0.94 | 0.94 | 0.94 | 1.00 |
| baby_cry | 1.00 | 1.00 | 1.00 | 1.00 | 0.88 |
| car_horn | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| cat | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| clap | 1.00 | 1.00 | 1.00 | 1.00 | 0.75 |
| dog | 1.00 | 1.00 | 1.00 | 1.00 | 0.88 |
| footsteps | 0.88 | 0.75 | 0.88 | 0.62 | 0.62 |
| glass_break | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| knock | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| siren | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| speech | 0.98 | 1.00 | 0.99 | 0.99 | 0.99 |
| **mean** | **0.98** | **0.99** | **0.99** | **0.98** | **0.96** |

Wrong-label rate:

| class | -10 dB | -20 dB | -30 dB | -40 dB | -50 dB |
|---|---|---|---|---|---|
| alarm | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| appliance | 0.06 | 0.00 | 0.00 | 0.00 | 0.00 |
| baby_cry | 0.00 | 0.00 | 0.25 | 0.12 | 0.00 |
| car_horn | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| cat | 0.12 | 0.12 | 0.12 | 0.12 | 0.12 |
| clap | 0.12 | 0.12 | 0.25 | 0.12 | 0.00 |
| dog | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| footsteps | 0.50 | 0.50 | 0.38 | 0.50 | 0.50 |
| glass_break | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| knock | 0.12 | 0.25 | 0.25 | 0.12 | 0.12 |
| siren | 0.12 | 0.25 | 0.00 | 0.12 | 0.25 |
| speech | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| **mean** | **0.04** | **0.05** | **0.05** | **0.04** | **0.04** |

Onset latency (s after clip start, caught clips only):

| level | median | p90 | n |
|---|---|---|---|
| -10 dB | 0.60 | 1.49 | 212 |
| -20 dB | 0.60 | 1.30 | 213 |
| -30 dB | 0.70 | 1.40 | 213 |
| -40 dB | 0.60 | 1.60 | 211 |
| -50 dB | 0.60 | 1.46 | 208 |

## False fires (fire episodes per minute)

| source | minutes | total/min | safety | babies | privacy | household | worst classes |
|---|---|---|---|---|---|---|---|
| other clips | 10.0 | 2.90 | 0.60 | 0.00 | 0.00 | 2.30 | appliance 0.60, knock 0.50, dog 0.50 |
| background only | 5.0 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | — |

## Out-of-vocabulary sounds (ESC-50 test-fold categories we never trained as labels)

62/304 clips made some target class fire. Categories with fires, most first (fraction of that category's clips in which each label fired):

| ESC-50 category | n | fired as |
|---|---|---|
| fireworks | 8 | footsteps 0.62, clap 0.38 |
| door_wood_creaks | 8 | knock 0.25, footsteps 0.25, baby_cry 0.12 |
| laughing | 8 | speech 0.12, baby_cry 0.12, footsteps 0.12, dog 0.12 |
| crackling_fire | 8 | footsteps 0.38, glass_break 0.12 |
| chainsaw | 8 | appliance 0.38 |
| clock_tick | 8 | knock 0.25, dog 0.12 |
| mouse_click | 8 | knock 0.38 |
| hen | 8 | dog 0.25, cat 0.12 |
| pig | 8 | dog 0.25 |
| wind | 8 | appliance 0.25 |
| brushing_teeth | 8 | glass_break 0.12, footsteps 0.12 |
| train | 8 | glass_break 0.12, appliance 0.12 |
| rooster | 8 | dog 0.12, cat 0.12 |
| drinking_sipping | 8 | knock 0.25 |
| crickets | 8 | alarm 0.25 |
| engine | 8 | appliance 0.25 |
| airplane | 8 | car_horn 0.12, appliance 0.12 |
| snoring | 8 | appliance 0.25 |
| can_opening | 8 | clap 0.25 |
| hand_saw | 8 | knock 0.25 |
| frog | 8 | dog 0.12 |
| thunderstorm | 8 | glass_break 0.12 |
| sneezing | 8 | knock 0.12 |
| cow | 8 | cat 0.12 |
| insects | 8 | knock 0.12 |
| sheep | 8 | dog 0.12 |
| sea_waves | 8 | clap 0.12 |
| breathing | 8 | appliance 0.12 |
| water_drops | 8 | car_horn 0.12 |

## Overlap (two target sounds mixed, second at -12..+6 dB; reported only)

| pairs | at least one | both | a third class fired |
|---|---|---|---|
| 117 | 0.97 | 0.37 | 0.03 |

## Threshold sweep under the streaming rule (confusion streams replayed)

beta as in train_head.py: 2.0 for priority>=7, 1.0 for >=4, else 0.7. 'suggested' is the F-beta argmax on these same clips (optimistic); nothing is written.

| class | current thr | recall @cur | FP clips @cur | suggested thr | recall @sug | FP clips @sug | F-beta cur -> sug |
|---|---|---|---|---|---|---|---|
| alarm | 0.80 | 1.00 | 2 / 328 | 0.80 | 1.00 | 2 / 328 | 0.95 -> 0.95 |
| appliance | 0.60 | 0.88 | 5 / 320 | 0.50 | 0.94 | 5 / 320 | 0.78 -> 0.80 |
| baby_cry | 0.80 | 1.00 | 0 / 328 | 0.80 | 1.00 | 0 / 328 | 1.00 -> 1.00 |
| car_horn | 0.75 | 1.00 | 1 / 328 | 0.90 | 1.00 | 0 / 328 | 0.98 -> 1.00 |
| cat | 0.30 | 1.00 | 1 / 328 | 0.40 | 1.00 | 0 / 328 | 0.92 -> 1.00 |
| clap | 0.28 | 1.00 | 3 / 328 | 0.50 | 1.00 | 1 / 328 | 0.84 -> 0.94 |
| dog | 0.28 | 1.00 | 5 / 328 | 0.90 | 0.88 | 0 / 328 | 0.70 -> 0.96 |
| footsteps | 0.50 | 0.75 | 7 / 328 | 0.80 | 0.62 | 0 / 328 | 0.53 -> 0.84 |
| glass_break | 0.50 | 1.00 | 3 / 328 | 0.60 | 1.00 | 2 / 328 | 0.93 -> 0.95 |
| knock | 0.26 | 1.00 | 10 / 328 | 0.85 | 0.75 | 0 / 328 | 0.62 -> 0.86 |
| siren | 0.60 | 1.00 | 0 / 328 | 0.40 | 1.00 | 0 / 328 | 1.00 -> 1.00 |
| speech | 0.80 | 1.00 | 0 / 216 | 0.80 | 1.00 | 0 / 216 | 1.00 -> 1.00 |

Honest estimate (2-fold: thresholds picked on one half of the clips, scored on the other half):

| thresholds | caught | wrong label | other clips with a fire |
|---|---|---|---|
| current (thresholds.json) | 0.98 | 0.04 | 0.22 |
| picked on the other half | 0.94 | 0.03 | 0.17 |

_151 s_
