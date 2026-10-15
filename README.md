# Sound Ring

Fortnite's "visualize sound effects," in real life, for under $100.

A hat-mounted wearable that identifies common sounds (siren, dog, doorbell, baby crying,
someone talking…) and lights an LED ring in the direction they came from. Built for people
who are deaf or hard of hearing. Texas Convergent IoT, Fall 2026.

```
┌──────────────┐    4 mics     ┌───────────────┐   direction    ┌───────────┐
│  sound       │ ───────────▶ │  Raspberry Pi │ ─────────────▶ │ LED ring  │
│  (anywhere)  │              │  + YAMNet +   │   + label      │  on hat   │
└──────────────┘              │  our head     │                └───────────┘
                              └───────────────┘
```

## Repo layout

| Folder | What's in it |
|---|---|
| `pi/` | Code that runs on the Raspberry Pi: mic reading, direction finding, classification, LEDs. Start with `pi/README.md`. |
| `demo/` | **Try it now on your laptop**: mic in, live ring in the browser, no hardware. See `demo/README.md`. |
| `ml/` | Training pipeline for the sound classifier. Already trained; re-run if you add your own recordings. See `ml/README.md`. |
| `docs/` | Project overview PDF, physical/UI mockup. |

## Hardware (~$60–75)

- Raspberry Pi Zero 2 W (or Pi 4)
- Seeed ReSpeaker 4-Mic Array HAT (4 mics + 12 RGB LEDs on one board)
- microSD card, USB power bank, a cap or headband

## Status

- [x] Direction of arrival from 4-mic array (GCC-PHAT)
- [x] Sound classifier: 13 classes, multi-label, 93.8% on held-out data, noise/overlap augmentation
- [x] LED ring output
- [ ] Test on real hardware and calibrate
- [ ] Record our own doorbell / dryer / smoke alarm clips and retrain
- [x] Laptop live demo (`demo/`)
- [ ] Phone "radar" view (optional demo mode)
