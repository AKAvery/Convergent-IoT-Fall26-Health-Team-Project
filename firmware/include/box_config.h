// box_config.h — the one place for everything both the firmware and the iPhone
// app must agree on: box position, BLE name, UUIDs, pins, audio format.
//
// The BLE contract itself (byte layouts) lives in docs/team-plan.md,
// "### 1. BLE: each box → iPhone". Change UUIDs only together with the iPhone side.
#pragma once

#include <stdint.h>

// ---------------------------------------------------------------------------
// Box position. Set by `[box] position = ...` in platformio.ini, which becomes
// -DBOX_POS_FRONT / -DBOX_POS_BACK / -DBOX_POS_LEFT / -DBOX_POS_RIGHT.
// Angle convention (team-wide): 0° ahead, clockwise positive, 90° right,
// 180° behind, 270° left.
// ---------------------------------------------------------------------------
#if (defined(BOX_POS_FRONT) + defined(BOX_POS_BACK) + defined(BOX_POS_LEFT) + defined(BOX_POS_RIGHT)) != 1
#error "Define exactly one of BOX_POS_FRONT/BACK/LEFT/RIGHT (set [box] position in platformio.ini)"
#endif

#if defined(BOX_POS_FRONT)
#define BOX_POSITION "FRONT"
#define BOX_ANGLE_DEG 0
#elif defined(BOX_POS_RIGHT)
#define BOX_POSITION "RIGHT"
#define BOX_ANGLE_DEG 90
#elif defined(BOX_POS_BACK)
#define BOX_POSITION "BACK"
#define BOX_ANGLE_DEG 180
#elif defined(BOX_POS_LEFT)
#define BOX_POSITION "LEFT"
#define BOX_ANGLE_DEG 270
#endif

#define BOX_BLE_NAME "SoundBox-" BOX_POSITION   // e.g. "SoundBox-FRONT"

// ---------------------------------------------------------------------------
// BLE UUIDs (128-bit, generated with uuidgen on 2026-10-29). Same on all 4 boxes;
// boxes are told apart by their advertised name.
// ---------------------------------------------------------------------------
#define SOUNDBOX_SERVICE_UUID  "f36b9eba-c1e3-4a55-a725-f566c01a5bdf"
#define LEVEL_CHAR_UUID        "e89a434d-2aa6-4a70-ae89-a47761df7c97"  // notify, 5 bytes, 10 Hz
#define AUDIO_CHAR_UUID        "a6c379f3-83f3-4927-be5c-ae2966376ec4"  // notify, 169 bytes, 50 Hz after control=1
#define CONTROL_CHAR_UUID      "f2b50bb3-d6c1-46a0-b5cf-ff3b5a2396f0"  // write, 1 byte: 1 start audio, 0 stop

constexpr uint8_t LEVEL_LEN = 5;
constexpr uint8_t AUDIO_LEN = 169;
constexpr uint8_t LEVEL_FLAG_CLIPPED     = 1 << 0;
constexpr uint8_t LEVEL_FLAG_LOW_BATTERY = 1 << 1;
constexpr uint8_t CONTROL_STOP_AUDIO  = 0;
constexpr uint8_t CONTROL_START_AUDIO = 1;

// ---------------------------------------------------------------------------
// Pins (GPIO numbers; XIAO silkscreen label in the comment). Same on all boxes.
// The INMP441 goes on different pins per chip because the strapping pins differ.
// ---------------------------------------------------------------------------
#include <sdkconfig.h>

#if defined(CONFIG_IDF_TARGET_ESP32C3)
// XIAO ESP32-C3. No user LED (only the charge LED), so PIN_LED = -1 and led.h does nothing.
// Avoid GPIO2/8/9 = D0/D8/D9 (strapping; GPIO9 is the BOOT button) and D6/D7 = GPIO21/20 (UART).
constexpr int PIN_LED      = -1;
constexpr int PIN_I2S_SCK  = 4;    // D2  -> INMP441 SCK (bit clock)
constexpr int PIN_I2S_WS   = 5;    // D3  -> INMP441 WS  (word select / LRCLK)
constexpr int PIN_I2S_SD   = 3;    // D1  <- INMP441 SD  (data out of the mic)
#else
// XIAO ESP32-S3. The mic uses the D8/D9/D10 side of the board, next to 3V3 and GND.
// Avoid GPIO0/3/45/46 (strapping) and D6/D7 = GPIO43/44 (UART TX/RX).
constexpr int PIN_LED      = 21;   // onboard yellow user LED, active LOW (Seeed wiki)
constexpr int PIN_I2S_SCK  = 7;    // D8  -> INMP441 SCK (bit clock)
constexpr int PIN_I2S_WS   = 8;    // D9  -> INMP441 WS  (word select / LRCLK)
constexpr int PIN_I2S_SD   = 9;    // D10 <- INMP441 SD  (data out of the mic)
#endif
constexpr int LED_ON       = 0;    // LOW  = on
constexpr int LED_OFF      = 1;    // HIGH = off

// INMP441 L/R -> GND (left channel), VDD -> 3V3, GND -> GND.

// ---------------------------------------------------------------------------
// Audio format and fixed gain (no AGC; must be identical on all 4 boxes).
// ---------------------------------------------------------------------------
constexpr uint32_t SAMPLE_RATE_HZ  = 16000;
constexpr uint32_t LEVEL_WINDOW_MS = 100;                                   // one `level` per window
constexpr uint32_t LEVEL_WINDOW_SAMPLES = SAMPLE_RATE_HZ * LEVEL_WINDOW_MS / 1000;  // 1600

// The INMP441 sends 24-bit samples left-aligned in a 32-bit slot. We keep the top
// 16 bits (int16 full scale == mic full scale, ~120 dB SPL). MIC_GAIN_BITS adds
// fixed digital gain in 6.02 dB steps (0 = unity). Keep it so a car horn at 1 m
// does not clip (docs/hardware-bom.md, "Rules that matter").
constexpr int MIC_GAIN_BITS = 0;

// Which 32-bit slot of each stereo I2S frame holds the mic (0 = first, 1 = second).
// With L/R tied to GND the mic talks in the left (WS low) slot, which should be
// slot 0. The loudness sketch prints both slots so this can be confirmed on hardware.
constexpr int MIC_SLOT = 0;

// Floor for reported levels when a window is pure digital silence.
constexpr int16_t PEAK_DB_X10_FLOOR = -1000;   // -100.0 dBFS
