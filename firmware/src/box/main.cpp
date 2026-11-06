// box: the real sound box. INMP441 -> BLE, speaking the contract in docs/team-plan.md.
//
// - `level`  notifies at 10 Hz: peak dBFS x10 of the last 100 ms from the mic above 300 Hz
//            (LevelHighPass in mic_dsp.h: rumble and handling noise would pick the wrong box), flags bit0 =
//            clipped (the mic hit its own rail or the limiter in mic_dsp.h turned the gain
//            down). (bit1 = low battery is never set yet: there is no battery-voltage divider.)
// - `audio`  after the phone writes `control` = 01: one 169-byte packet per 20 ms (50 Hz),
//            320 samples IMA ADPCM (lib/ima_adpcm, matches ml/adpcm.py). On every START the
//            encoder restarts at state (0, 0) and the audio seq at 0. `control` = 00 stops it.
//            A seq gap on the phone = a packet the BLE stack had no room for.
// - Serial prints one status line per second.
//
// The I2S clock paces everything: each loop reads 20 ms of audio (blocking), sends one audio
// packet if streaming, and every 5th loop sends `level`. No timers.
#include <Arduino.h>
#include "box_config.h"
#include "ima_adpcm.h"
#include "led.h"
#include "mic.h"
#include "soundbox_ble.h"

static_assert(adpcm::BLE_PACKET_BYTES == AUDIO_LEN, "ADPCM packet must match the BLE contract");
static_assert(LEVEL_WINDOW_SAMPLES % adpcm::SAMPLES_PER_PACKET == 0, "level window must be whole audio blocks");
static constexpr uint32_t BLOCKS_PER_LEVEL = LEVEL_WINDOW_SAMPLES / adpcm::SAMPLES_PER_PACKET;   // 5

static int16_t block[adpcm::SAMPLES_PER_PACKET];   // 20 ms of mic samples
static micdsp::LevelHighPass levelFilter;           // for `level` only; the audio is unfiltered
static uint8_t audioPkt[AUDIO_LEN];

// Audio stream state (only touched from loop()).
static bool streaming = false;
static adpcm::State encoder;
static uint16_t audioSeq = 0;

// Counters for the once-a-second status line.
static uint32_t audioSent = 0, audioBusy = 0, audioNoSub = 0, audioSmallMtu = 0;

static void startOrStopAudio() {
  const SoundBoxBle& b = soundBoxBle();
  if (b.audioRequested && !streaming) {
    streaming = true;
    encoder = adpcm::State();
    audioSeq = 0;
    Serial.println("[audio] streaming started");
  } else if (!b.audioRequested && streaming) {
    streaming = false;
    Serial.printf("[audio] streaming stopped after %u packets\n", (unsigned)audioSeq);
  }
}

static void sendAudio() {
  const SoundBoxBle& b = soundBoxBle();
  adpcm::encodeBlePacket(audioSeq, 0, block, encoder, audioPkt);
  audioSeq++;   // counts every packet made, so the phone sees a gap when one isn't sent
  if (!b.audioSubscribed) {
    audioNoSub++;
  } else if (b.mtu < AUDIO_LEN + 3) {
    audioSmallMtu++;
  } else if (soundBoxNotifyAudio(audioPkt)) {
    audioSent++;
  } else {
    audioBusy++;
  }
}

void setup() {
  ledInit();
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);

  Serial.printf("\n=== box: %s (angle %d deg) ===\n", BOX_BLE_NAME, BOX_ANGLE_DEG);
  Serial.printf("  mic          INMP441 SCK=GPIO%d WS=GPIO%d SD=GPIO%d, %lu Hz, gain +%d dB, slot %d\n",
                PIN_I2S_SCK, PIN_I2S_WS, PIN_I2S_SD, (unsigned long)SAMPLE_RATE_HZ, MIC_GAIN_BITS * 6, MIC_SLOT);
  if (!micBegin()) {
    Serial.println("  mic          FAILED to start; halting");
    while (true) {   // fast blink = I2S setup failed
      ledSet(true);  delay(100);
      ledSet(false); delay(100);
    }
  }
  bool ok = soundBoxBleBegin();
  soundBoxPrintUuids();
  Serial.printf("  advertising  %s\n\n", ok ? "started" : "FAILED to start");
}

void loop() {
  static uint32_t blockInWindow = 0;
  static int32_t peak = 0, otherPeak = 0;
  static bool clipped = false;
  static uint16_t levelSeq = 0;

  micRead(block, adpcm::SAMPLES_PER_PACKET, &otherPeak, &clipped);
  for (size_t i = 0; i < adpcm::SAMPLES_PER_PACKET; i++) {
    int32_t s = levelFilter.step(block[i]);
    int32_t a = s < 0 ? -s : s;
    if (a > peak) peak = a;
  }

  startOrStopAudio();
  if (streaming) sendAudio();

  if (++blockInWindow < BLOCKS_PER_LEVEL) return;

  // End of a 100 ms window: send `level`, then reset.
  int16_t dbX10 = peakToDbX10(peak);
  uint8_t levelPkt[LEVEL_LEN];
  soundBoxNotifyLevel(levelSeq, dbX10, clipped ? LEVEL_FLAG_CLIPPED : 0, levelPkt);

  if (levelSeq % 10 == 0) {   // once a second
    const SoundBoxBle& b = soundBoxBle();
    Serial.printf("[box] level %6.1f dBFS%s (other slot %6.1f) | phone: %s, mtu %u",
                  dbX10 / 10.0f, clipped ? " CLIPPED" : "", peakToDbX10(otherPeak) / 10.0f,
                  b.server->getConnectedCount() ? (b.levelSubscribed ? "level on" : "connected") : "none",
                  (unsigned)b.mtu);
    if (streaming) {
      Serial.printf(" | audio sent %u, busy %u, not subscribed %u, mtu too small %u",
                    (unsigned)audioSent, (unsigned)audioBusy, (unsigned)audioNoSub, (unsigned)audioSmallMtu);
    }
    Serial.println();
    audioSent = audioBusy = audioNoSub = audioSmallMtu = 0;
  }

  levelSeq++;
  blockInWindow = 0;
  peak = otherPeak = 0;
  clipped = false;
}
