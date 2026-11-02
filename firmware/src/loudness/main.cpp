// loudness: read the INMP441 over I2S at 16 kHz and print the peak level (dBFS) of
// every 100 ms window over USB serial. No Bluetooth. Fixed gain, no AGC.
// This is all the body-shadow test and the gain-match / clipping checks need.
//
// Output is one CSV line per window (easy to read, easy to paste into Python):
//   t_ms,peak_dbfs,clipped,other_slot_dbfs
// `other_slot_dbfs` is the unused I2S slot. With L/R on GND it should sit at the
// floor (-100.0). If the mic signal shows up there instead, flip MIC_SLOT in box_config.h.
//
// Uses the legacy ESP-IDF 4.4 I2S driver (driver/i2s.h), the one Arduino-ESP32 2.0.x ships.
#include <Arduino.h>
#include <driver/i2s.h>
#include <math.h>
#include "box_config.h"
#include "led.h"

static constexpr i2s_port_t I2S_PORT = I2S_NUM_0;
static constexpr int FRAMES_PER_READ = 160;                 // 10 ms; 10 reads = one 100 ms window
static constexpr uint32_t WARMUP_MS = 300;                  // INMP441 needs a moment after SCK starts
static int32_t rxBuf[FRAMES_PER_READ * 2];                  // stereo frames: [slot0, slot1]

// 32-bit I2S slot (24-bit sample, left-aligned) -> int16 with fixed gain, saturating.
static inline int32_t toInt16(int32_t raw) {
  int32_t v = raw >> (16 - MIC_GAIN_BITS);
  if (v > 32767) v = 32767;
  if (v < -32768) v = -32768;
  return v;
}

// Peak magnitude (0..32768) -> dBFS x 10, rounded, floored at PEAK_DB_X10_FLOOR.
static int16_t peakToDbX10(int32_t peakAbs) {
  if (peakAbs <= 0) return PEAK_DB_X10_FLOOR;
  float db = 20.0f * log10f((float)peakAbs / 32768.0f);
  int32_t x10 = lroundf(db * 10.0f);
  return x10 < PEAK_DB_X10_FLOOR ? PEAK_DB_X10_FLOOR : (int16_t)x10;
}

static bool startI2S() {
  i2s_config_t cfg = {};
  cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX);
  cfg.sample_rate = SAMPLE_RATE_HZ;
  cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT;   // INMP441: 24 bits in a 32-bit slot
  cfg.channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT;   // read both slots; pick MIC_SLOT below
  cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  cfg.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  cfg.dma_buf_count = 8;
  cfg.dma_buf_len = FRAMES_PER_READ;                 // 160 frames x 8 B = 1280 B per DMA buffer
  cfg.use_apll = false;

  i2s_pin_config_t pins = {};
  pins.mck_io_num = I2S_PIN_NO_CHANGE;               // INMP441 has no MCLK input
  pins.bck_io_num = PIN_I2S_SCK;
  pins.ws_io_num = PIN_I2S_WS;
  pins.data_out_num = I2S_PIN_NO_CHANGE;
  pins.data_in_num = PIN_I2S_SD;

  esp_err_t err = i2s_driver_install(I2S_PORT, &cfg, 0, nullptr);
  if (err != ESP_OK) {
    Serial.printf("i2s_driver_install failed: %s\n", esp_err_to_name(err));
    return false;
  }
  err = i2s_set_pin(I2S_PORT, &pins);
  if (err != ESP_OK) {
    Serial.printf("i2s_set_pin failed: %s\n", esp_err_to_name(err));
    return false;
  }
  i2s_zero_dma_buffer(I2S_PORT);
  return true;
}

void setup() {
  ledInit();
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);

  Serial.printf("\n=== loudness: %s, INMP441 SCK=GPIO%d WS=GPIO%d SD=GPIO%d, %lu Hz, gain +%d dB, slot %d ===\n",
                BOX_BLE_NAME, PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, (unsigned long)SAMPLE_RATE_HZ,
                MIC_GAIN_BITS * 6, MIC_SLOT);
  if (!startI2S()) {
    while (true) {   // fast blink = I2S setup failed
      ledSet(true);  delay(100);
      ledSet(false); delay(100);
    }
  }

  // Throw away the mic's start-up samples.
  uint32_t w0 = millis();
  size_t got = 0;
  while (millis() - w0 < WARMUP_MS) i2s_read(I2S_PORT, rxBuf, sizeof(rxBuf), &got, portMAX_DELAY);

  Serial.println("t_ms,peak_dbfs,clipped,other_slot_dbfs");
}

void loop() {
  int32_t peak = 0, otherPeak = 0;
  bool clipped = false;
  uint32_t frames = 0;

  while (frames < LEVEL_WINDOW_SAMPLES) {
    size_t bytes = 0;
    i2s_read(I2S_PORT, rxBuf, sizeof(rxBuf), &bytes, portMAX_DELAY);
    size_t n = bytes / (2 * sizeof(int32_t));
    for (size_t i = 0; i < n; i++) {
      int32_t s = toInt16(rxBuf[2 * i + MIC_SLOT]);
      int32_t o = toInt16(rxBuf[2 * i + (1 - MIC_SLOT)]);
      if (s >= 32767 || s <= -32768) clipped = true;
      int32_t a = s < 0 ? -s : s;
      int32_t b = o < 0 ? -o : o;
      if (a > peak) peak = a;
      if (b > otherPeak) otherPeak = b;
    }
    frames += n;
  }

  int16_t dbX10 = peakToDbX10(peak);
  int16_t otherX10 = peakToDbX10(otherPeak);
  Serial.printf("%lu,%.1f,%d,%.1f\n", (unsigned long)millis(), dbX10 / 10.0f, (int)clipped, otherX10 / 10.0f);

  ledSet(clipped);   // LED flashes on clipping
}
