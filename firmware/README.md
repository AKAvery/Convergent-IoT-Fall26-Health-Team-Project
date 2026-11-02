# Sound box firmware

One PlatformIO project for all 4 body-worn boxes (FRONT, BACK, LEFT, RIGHT). Each box is a
**Seeed XIAO ESP32-S3** (plain, not Sense) with one **INMP441** I2S mic. Arduino framework,
NimBLE for Bluetooth LE. The BLE contract (byte layouts) is in `docs/team-plan.md`,
"### 1. BLE: each box → iPhone". The shared values below come from
[`include/box_config.h`](include/box_config.h), the file the iPhone side should copy from.

| Environment | What it does | Needs the mic? |
|---|---|---|
| `board_check` | Blinks the user LED at 1 Hz and prints chip model, MACs, flash and PSRAM size once a second | No |
| `ble_fake` | BLE peripheral `SoundBox-<POSITION>` with the contract service. Sends fake `level` at 10 Hz and logs `control` writes. `audio` is defined but idle | No |
| `loudness` | Reads the INMP441 at 16 kHz (fixed gain, no AGC) and prints peak dBFS for each 100 ms window | **Yes** |
| `wifi_check` | Scans for networks, joins the one in `include/wifi_secrets.h` and checks internet access. Bring-up test only, the boxes talk BLE | No |

Code layout: `src/<env>/main.cpp` per environment (picked by `build_src_filter`), with
everything shared in `include/box_config.h`.

Pinned versions: platform `platformio/espressif32 @ 7.1.3` (Arduino-ESP32 2.0.17, ESP-IDF 4.4),
`h2zero/NimBLE-Arduino @ 2.5.1`.

## Flash and monitor

PlatformIO is installed but not on PATH. Either use the full path or add an alias:

```sh
alias pio=~/.platformio/penv/bin/pio
cd firmware
```

```sh
pio run -e board_check                  # build only
pio run -e board_check -t upload        # build + flash (board on USB-C)
pio device monitor                      # serial monitor (Ctrl+C to quit)
pio run -e board_check -t upload -t monitor   # all in one
```

Swap `board_check` for `ble_fake` or `loudness`. With more than one board plugged in, pick the
port: `pio device list`, then add `--upload-port /dev/cu.usbmodemXXXX` (and
`pio device monitor -p /dev/cu.usbmodemXXXX`).

Serial runs over the board's native USB (CDC), so the baud rate doesn't matter. After a flash
the port re-enumerates. If the monitor shows nothing, press the board's **R** (reset) button or
restart the monitor.

**If an upload fails** ("No serial data received", or no port shows up): hold **B** (BOOT),
press and release **R** (or plug in USB while holding B), let go of B, and upload again. Press
R afterwards to run the new firmware.

### Setting the box position

Change the one line in `platformio.ini` before flashing each box:

```ini
[box]
position = FRONT      ; FRONT, BACK, LEFT or RIGHT
```

It becomes `-DBOX_POS_<POSITION>`. `box_config.h` turns that into the name `SoundBox-<POSITION>`
and the angle (FRONT 0°, RIGHT 90°, BACK 180°, LEFT 270°). An invalid value fails the build.
All three environments print the position, so `board_check` also confirms which box a
board was flashed as.

## Wi-Fi check (`wifi_check`)

Confirms a board's radio works and shows why a join fails. Wi-Fi is not part of the box
contract. Setup, once per laptop:

```sh
cp include/wifi_secrets.example.h include/wifi_secrets.h   # gitignored, never commit it
# edit WIFI_SSID / WIFI_PASSWORD in include/wifi_secrets.h
pio run -e wifi_check -t upload -t monitor
```

What it prints, in order: a scan of every network it hears (the target is marked `->`), the
join result, IP/gateway/DNS/RSSI, then `[net] INTERNET OK`, and an RSSI line every 5 s. The LED
blinks fast while connecting and stays on while connected.

- The ESP32-S3 is **2.4 GHz only** and needs WPA2/WPA3-Personal or an open network.
  Campus networks with an EID login (WPA2-Enterprise) won't work. Neither will captive
  portals: the sketch reports those as `captive portal`.
- **iPhone hotspot:** Settings → Personal Hotspot → turn on **Maximize Compatibility**
  (that switches it to 2.4 GHz) and keep that screen open while the board connects.
- Common reasons it prints: `NO_AP_FOUND` = SSID not heard (spelling, 5 GHz, range);
  `AUTH_FAIL` / `4WAY_HANDSHAKE_TIMEOUT` / `HANDSHAKE_TIMEOUT` = wrong password;
  `ASSOC_FAIL` = the router refused the board (MAC filtering or registration needed; the
  Wi-Fi MAC is printed at boot).
- If the scan is empty or every RSSI is below about −80 dBm, attach the board's U.FL antenna
  if the pack came with one. BLE uses the same antenna.

## BLE UUIDs

The same on every box. Boxes are told apart by their advertised name, `SoundBox-FRONT`,
`SoundBox-BACK`, `SoundBox-LEFT` or `SoundBox-RIGHT`.

| What | UUID | Properties | Payload |
|---|---|---|---|
| Service | `f36b9eba-c1e3-4a55-a725-f566c01a5bdf` | primary, in the advertisement | |
| `level` | `e89a434d-2aa6-4a70-ae89-a47761df7c97` | read, notify | 5 B, 10 Hz: `seq` u16 LE, `peak_db` i16 LE (dBFS × 10), `flags` u8 (bit0 clipped, bit1 low battery) |
| `audio` | `a6c379f3-83f3-4927-be5c-ae2966376ec4` | notify | 169 B, 50 Hz after `control` = 1 (**not sent yet**) |
| `control` | `f2b50bb3-d6c1-46a0-b5cf-ff3b5a2396f0` | write, write without response | 1 B: `01` start audio, `00` stop |

Advertising: the advertisement carries flags and the 128-bit service UUID, which is what iOS
filters on in `scanForPeripherals(withServices:)`. The full name is in the scan response
(the UUID and name together don't fit in 31 bytes). The GAP device name is also
`SoundBox-<POSITION>`. The firmware asks for a 247-byte MTU, and iOS usually settles on 185.
`audio` needs at least 172.

Example `level` packet: `34 12 A8 FD 00` = seq 0x1234, peak −60.0 dBFS, no flags.

### Checking `ble_fake` with LightBlue (iPhone)

1. Flash `ble_fake` and open the serial monitor. It prints the UUIDs and `advertising started`.
2. In LightBlue, find `SoundBox-FRONT` and connect. The board's LED turns on while connected.
3. Open the service `F36B9EBA-…`, tap the `level` characteristic (`E89A434D-…`) and tap
   **Listen for notifications**. Values arrive 10×/s. Bytes 2–3 (little-endian) sweep between
   `A8 FD` (−600, −60.0 dBFS) and `9C FF` (−100, −10.0 dBFS) over 20 s, and bytes 0–1 count up.
   The serial log shows the same bytes once a second.
4. Tap `control` (`F2B50BB3-…`) and write hex `01`, then `00`. The serial monitor logs
   `[control] write of 1 byte(s): 01 -> START audio …`.

iOS caches names. If a box was flashed under a different position, toggle Bluetooth off
and on before trusting the name in LightBlue.

## Pins

The same on all 4 boxes. The mic sits on the right-hand header (USB-C at the top, chip facing
you), next to 3V3 and GND, so all its wires stay on one side. Check the silkscreen labels.

| INMP441 pin | XIAO pin | GPIO | `box_config.h` |
|---|---|---|---|
| VDD | 3V3 | — | |
| GND | GND | — | |
| SCK (bit clock) | D8 | GPIO7 | `PIN_I2S_SCK` |
| WS (word select) | D9 | GPIO8 | `PIN_I2S_WS` |
| SD (data out) | D10 | GPIO9 | `PIN_I2S_SD` |
| L/R | GND | — | left channel |

| Onboard | GPIO | Notes |
|---|---|---|
| User LED (yellow) | GPIO21 | **Active LOW**: LOW = on (Seeed wiki) |

Why these pins: D8/D9/D10 are free (no SPI is used) and sit next to 3V3/GND. They avoid the
strapping pins GPIO0/3/45/46 and the UART pins D6/D7 (GPIO43/44), and they leave D0–D5 free
(for example a battery-voltage divider on an ADC pin later).

## Audio and gain (`loudness`)

- I2S master RX at 16 kHz, 32-bit slots (the INMP441 sends 24-bit, left-aligned), standard
  Philips format. The legacy `driver/i2s.h` driver is the one ESP-IDF 4.4 ships.
- Samples are shifted to int16 (`>> 16`), so int16 full scale = mic full scale (~120 dB SPL).
  `MIC_GAIN_BITS` adds fixed digital gain in 6 dB steps and defaults to 0 (unity). There is no
  AGC. Keep it identical on all 4 boxes, and low enough that a car horn at 1 m doesn't clip.
- Peak dBFS = 20·log10(|peak| / 32768) over each 1600-sample window. A window that is all
  zeros reads −100.0. Clipped = any sample hit ±32767/−32768, and the LED flashes when it does.
- Output, one CSV line per 100 ms: `t_ms,peak_dbfs,clipped,other_slot_dbfs`.
  The firmware reads both I2S slots. With L/R on GND the mic should be in slot 0 and
  `other_slot_dbfs` should sit at about −100. **If the signal shows up in the last column
  instead, set `MIC_SLOT = 1`** in `box_config.h`. This hasn't been confirmed on hardware yet.
- Quick sanity check once soldered (estimates from the INMP441 datasheet sensitivity of −26
  dBFS at 94 dB SPL, not measured yet): a quiet room should read roughly −65 to −85 dBFS
  peak, talking at 30 cm about −40 to −30, and a clap close to the mic −20 to 0 (it may
  clip). If the reading is stuck at −100 the mic isn't talking (check wiring and L/R). If
  it's stuck near 0 with `clipped=1`, check SD and WS.

## First time plugging in a board

1. **No battery yet.** Run each board from USB-C only.
2. Plug in and run `pio device list`. A `/dev/cu.usbmodem…` port (Espressif or Seeed USB ID
   `2886:0056`/`303a:…`) should appear. If nothing shows up, try another cable, since some
   USB-C cables are charge-only.
3. `pio run -e board_check -t upload -t monitor`. Expect the yellow LED blinking at 1 Hz and,
   once a second: `ESP32-S3`, 2 cores at 240 MHz, **8 MB flash on chip**, **~8 MB PSRAM**. A
   board showing `PSRAM NOT FOUND` or the wrong flash size isn't the expected part, so set it aside.
4. Write down each board's **BLE MAC** with a sticker number (1–6), and note which 4 become
   FRONT/BACK/LEFT/RIGHT and which 2 are spares.
5. Optional: flash `ble_fake` on one board and run the LightBlue check above.
6. The red charge LED on a USB-only board lights and then turns off after about 30 s. That's normal.
7. **Before connecting any LiPo:** check the battery lead polarity **with a multimeter**.
   Generic LiPo leads don't follow one red/black convention, and reversed polarity can destroy
   the charger (`docs/hardware-bom.md`, "Check before powering anything"). The XIAO has only
   **BAT+ / BAT− solder pads** on the underside. Per the Seeed wiki, the negative pad is the one
   closer to the USB port.
8. After soldering the mic headers: wire per the pin table, flash `loudness`, and check the
   sanity readings above on **one box first** before building the other three.

## Relation to the week-1 task list

`docs/week1-tasks.md` B0 asked for `firmware/level_sketch/`. That job is now the `loudness`
environment of this project. B2 names the environments `seeed_xiao_esp32s3` and `native`.
This project uses `board_check`/`ble_fake`/`loudness` for now. The real BLE firmware (`level`
from the mic, ADPCM `audio`) and a `native` test env are still to do.
