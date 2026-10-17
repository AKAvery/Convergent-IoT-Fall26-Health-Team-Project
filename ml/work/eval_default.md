# Live-pipeline evaluation: default

params: `hop_s=0.1, buffer_s=1.0, gate_db=-70.0, gate_window_s=0.1, persist=5, other_veto=True, other_veto_margin=0.15, veto_exempt_priority=8, label_margin=0.1, loud_ref_db=-60.0, loud_floor=0.2, input_gain_db=0.0, clip_level=0.99`  
model: `/Users/averyallen/Coding Projects/Convergent-IoT-Fall26-Health-Team-Project/pi`  
background: white noise at -70 dBFS  
test split: 336 clips from work/manifest.csv

> Digital attenuation has no room acoustics or mic self-noise, so the -40/-50 dB rows measure the gate and ranking, not the microphone. `--playback` is the honest test of the laptop setup.

## Streamed confusion (every test clip at -20 dBFS peak)

| class | n | caught | wrong label | wrong shown big | big-label acc | onset med / p90 s |
|---|---|---|---|---|---|---|
| alarm | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.70 / 1.03 |
| appliance | 16 | 0.94 | 0.00 | 0.00 | 1.00 | 1.20 / 3.84 |
| baby_cry | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 1.95 / 2.73 |
| car_horn | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.95 / 1.73 |
| cat | 8 | 1.00 | 0.12 | 0.12 | 0.98 | 0.75 / 1.28 |
| clap | 8 | 1.00 | 0.12 | 0.12 | 0.99 | 0.60 / 1.06 |
| dog | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.70 / 1.04 |
| footsteps | 8 | 0.75 | 0.38 | 0.38 | 0.79 | 1.55 / 3.85 |
| glass_break | 8 | 1.00 | 0.00 | 0.00 | 1.00 | 0.80 / 1.19 |
| knock | 8 | 1.00 | 0.12 | 0.12 | 0.99 | 0.85 / 0.93 |
| siren | 8 | 1.00 | 0.12 | 0.12 | 1.00 | 1.00 / 1.64 |
| speech | 120 | 1.00 | 0.00 | 0.00 | 1.00 | 0.50 / 0.80 |
| **mean** | | **0.97** | **0.07** | | | |

'other' test clips with any target fired: 0.18 (n=120)

Fired-class matrix (rows = true, cols = fired at least once; clips):

| true \ fired | alarm | appli | baby_ | car_h | cat | clap | dog | foots | glass | knock | siren | speec |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| alarm | 8 | · | · | · | · | · | · | · | · | · | · | · |
| appliance | · | 15 | · | · | · | · | · | · | · | · | · | · |
| baby_cry | · | · | 8 | · | · | · | · | · | · | · | · | · |
| car_horn | · | · | · | 8 | · | · | · | · | · | · | · | · |
| cat | · | · | · | · | 8 | · | 1 | · | · | · | · | · |
| clap | · | · | · | · | · | 8 | · | · | · | 1 | · | · |
| dog | · | · | · | · | · | · | 8 | · | · | · | · | · |
| footsteps | · | · | · | · | · | · | · | 6 | · | 3 | · | · |
| glass_break | · | · | · | · | · | · | · | · | 8 | · | · | · |
| knock | · | · | · | · | · | · | · | 1 | · | 8 | · | · |
| siren | 1 | · | · | · | · | · | · | · | · | · | 8 | · |
| speech | · | · | · | · | · | · | · | · | · | · | · | 120 |
| other | · | 4 | · | 1 | · | 2 | 4 | 5 | 2 | 6 | · | · |

## Level sweep (clip peak dBFS; digital attenuation, no room)

Caught rate:

| class | -10 dB | -20 dB | -30 dB | -40 dB | -50 dB |
|---|---|---|---|---|---|
| alarm | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| appliance | 0.94 | 0.94 | 0.94 | 0.94 | 0.94 |
| baby_cry | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| car_horn | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| cat | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| clap | 1.00 | 1.00 | 1.00 | 1.00 | 0.88 |
| dog | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| footsteps | 0.75 | 0.75 | 0.75 | 0.75 | 0.75 |
| glass_break | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| knock | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| siren | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 |
| speech | 0.94 | 0.99 | 0.99 | 0.98 | 0.99 |
| **mean** | **0.95** | **0.98** | **0.98** | **0.98** | **0.98** |

Wrong-label rate:

| class | -10 dB | -20 dB | -30 dB | -40 dB | -50 dB |
|---|---|---|---|---|---|
| alarm | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| appliance | 0.06 | 0.00 | 0.00 | 0.00 | 0.00 |
| baby_cry | 0.00 | 0.00 | 0.12 | 0.12 | 0.12 |
| car_horn | 0.00 | 0.00 | 0.00 | 0.00 | 0.12 |
| cat | 0.12 | 0.12 | 0.12 | 0.12 | 0.12 |
| clap | 0.12 | 0.12 | 0.25 | 0.12 | 0.00 |
| dog | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| footsteps | 0.38 | 0.38 | 0.38 | 0.38 | 0.50 |
| glass_break | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| knock | 0.00 | 0.12 | 0.12 | 0.00 | 0.00 |
| siren | 0.25 | 0.12 | 0.12 | 0.00 | 0.12 |
| speech | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| **mean** | **0.04** | **0.03** | **0.04** | **0.03** | **0.04** |

Onset latency (s after clip start, caught clips only):

| level | median | p90 | n |
|---|---|---|---|
| -10 dB | 0.60 | 1.40 | 206 |
| -20 dB | 0.60 | 1.29 | 212 |
| -30 dB | 0.60 | 1.39 | 212 |
| -40 dB | 0.60 | 1.40 | 211 |
| -50 dB | 0.60 | 1.40 | 211 |

## False fires (fire episodes per minute)

| source | minutes | total/min | safety | babies | privacy | household | worst classes |
|---|---|---|---|---|---|---|---|
| other clips | 10.0 | 2.40 | 0.50 | 0.00 | 0.00 | 1.90 | footsteps 0.50, knock 0.40, dog 0.40 |
| background only | 5.0 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | — |

## Out-of-vocabulary sounds (ESC-50 test-fold categories we never trained as labels)

55/304 clips made some target class fire. Categories with fires, most first (fraction of that category's clips in which each label fired):

| ESC-50 category | n | fired as |
|---|---|---|
| fireworks | 8 | footsteps 0.62, clap 0.38 |
| door_wood_creaks | 8 | knock 0.38, footsteps 0.12 |
| laughing | 8 | speech 0.12, baby_cry 0.12, footsteps 0.12, dog 0.12 |
| chainsaw | 8 | appliance 0.38 |
| rooster | 8 | dog 0.25, cat 0.12 |
| mouse_click | 8 | knock 0.38 |
| can_opening | 8 | appliance 0.12, clap 0.12, glass_break 0.12 |
| hen | 8 | dog 0.25, cat 0.12 |
| pig | 8 | dog 0.25 |
| wind | 8 | appliance 0.25 |
| crackling_fire | 8 | glass_break 0.12, footsteps 0.12 |
| train | 8 | glass_break 0.12, appliance 0.12 |
| drinking_sipping | 8 | knock 0.25 |
| airplane | 8 | car_horn 0.12, appliance 0.12 |
| snoring | 8 | appliance 0.25 |
| water_drops | 8 | glass_break 0.12, car_horn 0.12 |
| hand_saw | 8 | knock 0.25 |
| brushing_teeth | 8 | glass_break 0.12 |
| frog | 8 | dog 0.12 |
| thunderstorm | 8 | glass_break 0.12 |
| coughing | 8 | knock 0.12 |
| sneezing | 8 | knock 0.12 |
| cow | 8 | dog 0.12 |
| insects | 8 | knock 0.12 |
| sheep | 8 | dog 0.12 |
| sea_waves | 8 | clap 0.12 |
| engine | 8 | appliance 0.12 |

## Overlap (two target sounds mixed, second at -12..+6 dB; reported only)

| pairs | at least one | both | a third class fired |
|---|---|---|---|
| 117 | 0.98 | 0.33 | 0.04 |

## Threshold sweep under the streaming rule (confusion streams replayed)

beta as in train_head.py: 2.0 for priority>=7, 1.0 for >=4, else 0.7. 'suggested' is the F-beta argmax on these same clips (optimistic); nothing is written.

| class | current thr | recall @cur | FP clips @cur | suggested thr | recall @sug | FP clips @sug | F-beta cur -> sug |
|---|---|---|---|---|---|---|---|
| alarm | 0.80 | 1.00 | 1 / 328 | 0.80 | 1.00 | 1 / 328 | 0.98 -> 0.98 |
| appliance | 0.60 | 0.94 | 4 / 320 | 0.60 | 0.94 | 4 / 320 | 0.83 -> 0.83 |
| baby_cry | 0.80 | 1.00 | 0 / 328 | 0.80 | 1.00 | 0 / 328 | 1.00 -> 1.00 |
| car_horn | 0.75 | 1.00 | 1 / 328 | 0.75 | 1.00 | 1 / 328 | 0.98 -> 0.98 |
| cat | 0.30 | 1.00 | 0 / 328 | 0.30 | 1.00 | 0 / 328 | 1.00 -> 1.00 |
| clap | 0.28 | 1.00 | 2 / 328 | 0.80 | 0.88 | 0 / 328 | 0.89 -> 0.93 |
| dog | 0.28 | 1.00 | 4 / 328 | 0.85 | 0.88 | 0 / 328 | 0.75 -> 0.96 |
| footsteps | 0.50 | 0.75 | 6 / 328 | 0.85 | 0.62 | 0 / 328 | 0.56 -> 0.84 |
| glass_break | 0.50 | 1.00 | 2 / 328 | 0.50 | 1.00 | 2 / 328 | 0.95 -> 0.95 |
| knock | 0.26 | 1.00 | 10 / 328 | 0.85 | 0.75 | 0 / 328 | 0.62 -> 0.86 |
| siren | 0.60 | 1.00 | 0 / 328 | 0.60 | 1.00 | 0 / 328 | 1.00 -> 1.00 |
| speech | 0.80 | 1.00 | 0 / 216 | 0.80 | 1.00 | 0 / 216 | 1.00 -> 1.00 |

Honest estimate (2-fold: thresholds picked on one half of the clips, scored on the other half):

| thresholds | caught | wrong label | other clips with a fire |
|---|---|---|---|
| current (thresholds.json) | 0.99 | 0.03 | 0.17 |
| picked on the other half | 0.95 | 0.05 | 0.19 |

_104 s_
