// mic.h: the INMP441 over I2S at 16 kHz, shared by `loudness` and `box`.
//
// Uses the legacy ESP-IDF 4.4 I2S driver (driver/i2s.h), the one Arduino-ESP32 2.0.x ships.
// Both I2S slots are read; MIC_SLOT (box_config.h) picks the one with the mic, and the other
// slot's peak is reported so a wrong MIC_SLOT shows up on hardware.
#pragma once

#include <Arduino.h>
#include <driver/i2s.h>
#include <math.h>
#include "box_config.h"
#include "mic_dsp.h"

static constexpr i2s_port_t MIC_I2S_PORT = I2S_NUM_0;
static constexpr int MIC_FRAMES_PER_DMA = 160;              // 10 ms per DMA buffer
static constexpr uint32_t MIC_WARMUP_MS = 300;              // INMP441 needs a moment after SCK starts

// 32-bit I2S slot (24-bit sample, left-aligned) -> int16 with fixed gain, saturating. Only the
// unused slot's peak goes through this now; the mic slot goes through mic_dsp.h.
inline int32_t micToInt16(int32_t raw) {
  int32_t v = raw >> (16 - MIC_GAIN_BITS);
  if (v > 32767) v = 32767;
  if (v < -32768) v = -32768;
  return v;
}

// Peak magnitude (0..32768) -> dBFS x 10, rounded, floored at PEAK_DB_X10_FLOOR.
inline int16_t peakToDbX10(int32_t peakAbs) {
  if (peakAbs <= 0) return PEAK_DB_X10_FLOOR;
  float db = 20.0f * log10f((float)peakAbs / 32768.0f);
  int32_t x10 = lroundf(db * 10.0f);
  return x10 < PEAK_DB_X10_FLOOR ? PEAK_DB_X10_FLOOR : (int16_t)x10;
}

// Read exactly `n` frames (blocking; the I2S clock paces the caller); `n` must be a multiple of
// micdsp::CHUNK. Writes the mic slot to `out` as int16 after gain, DC removal and the limiter
// (mic_dsp.h; the output is 10 ms behind the I2S input). Raises `*otherPeakAbs` to the unused
// slot's peak, and sets `*clipped` if the mic hit its own rail or the limiter turned the gain
// down (int16 itself can no longer clip).
inline void micRead(int16_t* out, size_t n, int32_t* otherPeakAbs, bool* clipped = nullptr) {
  static_assert(MIC_FRAMES_PER_DMA == (int)micdsp::CHUNK, "one I2S DMA buffer per DSP chunk");
  static_assert(MIC_GAIN_BITS >= 0 && MIC_GAIN_BITS <= 6, "gain is applied in the 24-bit domain");
  static int32_t rx[micdsp::CHUNK * 2];                     // stereo frames: [slot0, slot1]
  static int32_t filtered[micdsp::CHUNK];
  static micdsp::DcBlock dc;
  static micdsp::Limiter limiter;
  for (size_t done = 0; done + micdsp::CHUNK <= n; done += micdsp::CHUNK) {
    size_t have = 0;
    while (have < micdsp::CHUNK) {
      size_t bytes = 0;
      i2s_read(MIC_I2S_PORT, rx + 2 * have, (micdsp::CHUNK - have) * 2 * sizeof(int32_t), &bytes,
               portMAX_DELAY);
      have += bytes / (2 * sizeof(int32_t));
    }
    for (size_t i = 0; i < micdsp::CHUNK; i++) {
      int32_t raw24 = rx[2 * i + MIC_SLOT] >> 8;              // 24-bit sample
      if (clipped && (raw24 >= micdsp::OVERLOAD_24 || raw24 <= -micdsp::OVERLOAD_24)) *clipped = true;
      filtered[i] = dc.step(raw24 * (1 << MIC_GAIN_BITS));
      int32_t o = micToInt16(rx[2 * i + (1 - MIC_SLOT)]);
      if (o < 0) o = -o;
      if (otherPeakAbs && o > *otherPeakAbs) *otherPeakAbs = o;
    }
    if (limiter.process(filtered, out + done) && clipped) *clipped = true;
  }
}

// Install the driver, set the pins and throw away the mic's start-up samples.
inline bool micBegin() {
  i2s_config_t cfg = {};
  cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX);
  cfg.sample_rate = SAMPLE_RATE_HZ;
  cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT;   // INMP441: 24 bits in a 32-bit slot
  cfg.channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT;   // read both slots; pick MIC_SLOT in micRead
  cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  cfg.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  cfg.dma_buf_count = 8;                             // 80 ms of slack if the reader stalls
  cfg.dma_buf_len = MIC_FRAMES_PER_DMA;              // 160 frames x 8 B = 1280 B per DMA buffer
  cfg.use_apll = false;

  i2s_pin_config_t pins = {};
  pins.mck_io_num = I2S_PIN_NO_CHANGE;               // INMP441 has no MCLK input
  pins.bck_io_num = PIN_I2S_SCK;
  pins.ws_io_num = PIN_I2S_WS;
  pins.data_out_num = I2S_PIN_NO_CHANGE;
  pins.data_in_num = PIN_I2S_SD;

  esp_err_t err = i2s_driver_install(MIC_I2S_PORT, &cfg, 0, nullptr);
  if (err != ESP_OK) {
    Serial.printf("i2s_driver_install failed: %s\n", esp_err_to_name(err));
    return false;
  }
  err = i2s_set_pin(MIC_I2S_PORT, &pins);
  if (err != ESP_OK) {
    Serial.printf("i2s_set_pin failed: %s\n", esp_err_to_name(err));
    return false;
  }
  i2s_zero_dma_buffer(MIC_I2S_PORT);

  int16_t scratch[MIC_FRAMES_PER_DMA];
  uint32_t w0 = millis();
  while (millis() - w0 < MIC_WARMUP_MS) micRead(scratch, MIC_FRAMES_PER_DMA, nullptr);
  return true;
}
