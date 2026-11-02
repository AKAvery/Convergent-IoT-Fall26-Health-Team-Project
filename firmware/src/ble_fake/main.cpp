// ble_fake: a BLE peripheral that speaks the box contract with made-up data.
// No mic needed. Use it to test the iPhone side (LightBlue first, then the app).
//
// - Advertises as SoundBox-<POSITION> with the SoundBox service UUID.
// - `level`  notifies at 10 Hz: seq (uint16 LE), peak_db x10 (int16 LE), flags (uint8).
//            peak_db is a slow sine between -60 and -10 dBFS (20 s period).
// - `audio`  is defined (notify, 169 bytes of zeros) but never sent yet.
// - `control` writes are logged to serial (1 = start audio, 0 = stop).
// - The user LED is on while a phone is connected.
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <math.h>
#include "box_config.h"
#include "led.h"

static NimBLECharacteristic* levelChar   = nullptr;
static NimBLECharacteristic* audioChar   = nullptr;
static NimBLECharacteristic* controlChar = nullptr;

static volatile bool audioRequested = false;   // set by `control`; audio itself is not implemented yet
static volatile bool levelSubscribed = false;  // for the serial log only

// Pack one `level` packet exactly as in docs/team-plan.md (5 bytes, little-endian).
static void packLevel(uint8_t out[LEVEL_LEN], uint16_t seq, int16_t peakDbX10, uint8_t flags) {
  out[0] = seq & 0xFF;
  out[1] = seq >> 8;
  out[2] = (uint16_t)peakDbX10 & 0xFF;
  out[3] = (uint16_t)peakDbX10 >> 8;
  out[4] = flags;
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    Serial.printf("[ble] connected: %s (%u connection(s))\n", info.getAddress().toString().c_str(),
                  server->getConnectedCount());
    ledSet(true);
  }
  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& info, int reason) override {
    Serial.printf("[ble] disconnected: %s, reason 0x%02X; advertising again\n",
                  info.getAddress().toString().c_str(), reason);
    audioRequested = false;
    levelSubscribed = false;
    if (server->getConnectedCount() == 0) ledSet(false);
  }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo& info) override {
    Serial.printf("[ble] MTU = %u (audio needs >= %u)\n", mtu, AUDIO_LEN + 3);
  }
};

class CharCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& info) override {
    if (c != controlChar) return;
    NimBLEAttValue v = c->getValue();
    Serial.printf("[control] write of %u byte(s):", (unsigned)v.size());
    for (size_t i = 0; i < v.size(); i++) Serial.printf(" %02X", v[i]);
    if (v.size() == 1 && v[0] == CONTROL_START_AUDIO) {
      audioRequested = true;
      Serial.println("  -> START audio (not implemented in ble_fake; audio stays idle)");
    } else if (v.size() == 1 && v[0] == CONTROL_STOP_AUDIO) {
      audioRequested = false;
      Serial.println("  -> STOP audio");
    } else {
      Serial.println("  -> ignored (contract: exactly 1 byte, 0 or 1)");
    }
  }
  void onSubscribe(NimBLECharacteristic* c, NimBLEConnInfo& info, uint16_t subValue) override {
    const char* name = (c == levelChar) ? "level" : (c == audioChar) ? "audio" : "?";
    if (c == levelChar) levelSubscribed = (subValue != 0);
    Serial.printf("[ble] %s %s\n", name, subValue ? "subscribed (notify on)" : "unsubscribed");
  }
};

static ServerCallbacks serverCallbacks;
static CharCallbacks charCallbacks;

static void printBanner() {
  Serial.printf("\n=== ble_fake: %s (angle %d deg) ===\n", BOX_BLE_NAME, BOX_ANGLE_DEG);
  Serial.printf("  BLE address  %s\n", NimBLEDevice::getAddress().toString().c_str());
  Serial.printf("  service      %s\n", SOUNDBOX_SERVICE_UUID);
  Serial.printf("  level        %s  (notify, 10 Hz, 5 B)\n", LEVEL_CHAR_UUID);
  Serial.printf("  audio        %s  (notify, idle in ble_fake)\n", AUDIO_CHAR_UUID);
  Serial.printf("  control      %s  (write 01 = start, 00 = stop)\n", CONTROL_CHAR_UUID);
}

void setup() {
  ledInit();
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);

  NimBLEDevice::init(BOX_BLE_NAME);   // also the GAP device name LightBlue shows after connecting
  NimBLEDevice::setMTU(247);          // iOS usually settles on 185; audio needs >= 172

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(&serverCallbacks);
  server->advertiseOnDisconnect(true);

  NimBLEService* svc = server->createService(SOUNDBOX_SERVICE_UUID);
  levelChar = svc->createCharacteristic(LEVEL_CHAR_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  audioChar = svc->createCharacteristic(AUDIO_CHAR_UUID, NIMBLE_PROPERTY::NOTIFY, AUDIO_LEN);
  controlChar = svc->createCharacteristic(CONTROL_CHAR_UUID,
                                          NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  levelChar->setCallbacks(&charCallbacks);
  audioChar->setCallbacks(&charCallbacks);
  controlChar->setCallbacks(&charCallbacks);

  uint8_t initLevel[LEVEL_LEN];
  packLevel(initLevel, 0, PEAK_DB_X10_FLOOR, 0);
  levelChar->setValue(initLevel, LEVEL_LEN);
  uint8_t zeros[AUDIO_LEN] = {0};
  audioChar->setValue(zeros, AUDIO_LEN);
  uint8_t stop = CONTROL_STOP_AUDIO;
  controlChar->setValue(&stop, 1);
  // (NimBLE 2.x starts services together with the server; no svc->start() needed.)

  // A 128-bit UUID (18 B) plus "SoundBox-FRONT" (16 B) won't fit in one 31-byte
  // advertisement, so: flags + service UUID in the advertisement (what iOS filters
  // on), and the full name in the scan response.
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->enableScanResponse(true);
  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.setCompleteServices(NimBLEUUID(SOUNDBOX_SERVICE_UUID));
  NimBLEAdvertisementData scanData;
  scanData.setName(BOX_BLE_NAME);
  adv->setAdvertisementData(advData);
  adv->setScanResponseData(scanData);
  bool ok = adv->start();

  printBanner();
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
  packLevel(pkt, seq, dbX10, 0);
  levelChar->setValue(pkt, LEVEL_LEN);
  levelChar->notify();   // no-op when nobody is subscribed

  if (seq % 10 == 0) {   // log once a second, not 10x
    Serial.printf("[level] seq=%5u peak=%6.1f dBFS bytes=%02X %02X %02X %02X %02X  subs=%s audio_req=%d\n",
                  seq, dbX10 / 10.0f, pkt[0], pkt[1], pkt[2], pkt[3], pkt[4],
                  levelSubscribed ? "yes" : "no", (int)audioRequested);
  }
  seq++;   // uint16, wraps at 65535 -> 0
}
