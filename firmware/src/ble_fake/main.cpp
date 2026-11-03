// ble_fake: a BLE peripheral that speaks the box contract with made-up data.
// No mic needed. Use it to test the iPhone side (LightBlue first, then the app).
//
// - Advertises as SoundBox-<POSITION> with the SoundBox service UUID.
// - `level`  notifies at 10 Hz: seq (uint16 LE), peak_db x10 (int16 LE), flags (uint8).
//            peak_db is a slow sine between -60 and -10 dBFS (20 s period).
// - `audio`  is defined (notify, 169 bytes of zeros) but never sent. The `box` firmware sends it.
// - `control` writes are logged to serial (1 = start audio, 0 = stop).
// - The user LED is on while a phone is connected.
//
// The BLE service itself lives in include/soundbox_ble.h (shared with `box`).
#include <Arduino.h>
#include <math.h>
#include "box_config.h"
#include "led.h"
#include "soundbox_ble.h"

void setup() {
  ledInit();
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);

  bool ok = soundBoxBleBegin();
  Serial.printf("\n=== ble_fake: %s (angle %d deg) ===\n", BOX_BLE_NAME, BOX_ANGLE_DEG);
  soundBoxPrintUuids();
  Serial.println("  (audio stays idle in ble_fake)");
  Serial.printf("  advertising  %s\n\n", ok ? "started" : "FAILED to start");
}

void loop() {
  static uint16_t seq = 0;
  static uint32_t nextMs = millis();

  uint32_t now = millis();
  if ((int32_t)(now - nextMs) < 0) {
    delay(1);
    return;
  }
  nextMs += LEVEL_WINDOW_MS;   // fixed 10 Hz schedule, no drift

  // Slow sine: centre -35 dBFS, amplitude 25 dB -> -60 .. -10 dBFS, period 20 s.
  float db = -35.0f + 25.0f * sinf(2.0f * (float)M_PI * (float)now / 20000.0f);
  int16_t dbX10 = (int16_t)lroundf(db * 10.0f);

  uint8_t pkt[LEVEL_LEN];
  soundBoxNotifyLevel(seq, dbX10, 0, pkt);

  if (seq % 10 == 0) {   // log once a second, not 10x
    const SoundBoxBle& b = soundBoxBle();
    Serial.printf("[level] seq=%5u peak=%6.1f dBFS bytes=%02X %02X %02X %02X %02X  subs=%s audio_req=%d\n",
                  seq, dbX10 / 10.0f, pkt[0], pkt[1], pkt[2], pkt[3], pkt[4],
                  b.levelSubscribed ? "yes" : "no", (int)b.audioRequested);
  }
  seq++;   // uint16, wraps at 65535 -> 0
}
