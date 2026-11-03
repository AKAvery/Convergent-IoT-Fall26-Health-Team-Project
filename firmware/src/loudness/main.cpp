// loudness: read the INMP441 over I2S at 16 kHz and print the peak level (dBFS) of
// every 100 ms window over USB serial. No Bluetooth. Fixed gain, no AGC.
// This is all the body-shadow test and the gain-match / clipping checks need.
//
// Output is one CSV line per window (easy to read, easy to paste into Python):
//   t_ms,peak_dbfs,clipped,other_slot_dbfs
// `other_slot_dbfs` is the unused I2S slot. With L/R on GND it should sit at the
// floor (-100.0). If the mic signal shows up there instead, flip MIC_SLOT in box_config.h.
//
// I2S setup and sample conversion live in include/mic.h (shared with the `box` firmware).
#include <Arduino.h>
#include "box_config.h"
#include "led.h"
#include "mic.h"

static int16_t window[LEVEL_WINDOW_SAMPLES];                // one 100 ms window

void setup() {
  ledInit();
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);

  Serial.printf("\n=== loudness: %s, INMP441 SCK=GPIO%d WS=GPIO%d SD=GPIO%d, %lu Hz, gain +%d dB, slot %d ===\n",
                BOX_BLE_NAME, PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, (unsigned long)SAMPLE_RATE_HZ,
                MIC_GAIN_BITS * 6, MIC_SLOT);
  if (!micBegin()) {
    while (true) {   // fast blink = I2S setup failed
      ledSet(true);  delay(100);
      ledSet(false); delay(100);
    }
  }

  Serial.println("t_ms,peak_dbfs,clipped,other_slot_dbfs");
}

void loop() {
  int32_t peak = 0, otherPeak = 0;
  bool clipped = false;

  micRead(window, LEVEL_WINDOW_SAMPLES, &otherPeak);
  for (uint32_t i = 0; i < LEVEL_WINDOW_SAMPLES; i++) {
    int32_t s = window[i];
    if (s >= 32767 || s <= -32768) clipped = true;
    int32_t a = s < 0 ? -s : s;
    if (a > peak) peak = a;
  }

  int16_t dbX10 = peakToDbX10(peak);
  int16_t otherX10 = peakToDbX10(otherPeak);
  Serial.printf("%lu,%.1f,%d,%.1f\n", (unsigned long)millis(), dbX10 / 10.0f, (int)clipped, otherX10 / 10.0f);

  ledSet(clipped);   // LED flashes on clipping
}
