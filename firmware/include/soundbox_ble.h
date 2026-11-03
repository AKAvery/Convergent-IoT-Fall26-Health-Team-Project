// soundbox_ble.h: the box side of the BLE contract (docs/team-plan.md), shared by `ble_fake`
// and `box`. One service with three characteristics:
//
//   level    notify, 5 B: seq u16 LE, peak_db x10 i16 LE, flags u8
//   audio    notify, 169 B: built by lib/ima_adpcm (encodeBlePacket)
//   control  write, 1 B: 1 = start audio, 0 = stop
//
// The user LED (if the board has one) is on while a phone is connected.
#pragma once

#include <Arduino.h>
#include <NimBLEDevice.h>
#include "box_config.h"
#include "led.h"

struct SoundBoxBle {
  NimBLEServer* server = nullptr;
  NimBLECharacteristic* level = nullptr;
  NimBLECharacteristic* audio = nullptr;
  NimBLECharacteristic* control = nullptr;
  volatile bool audioRequested = false;   // last `control` write was 1
  volatile bool levelSubscribed = false;
  volatile bool audioSubscribed = false;
  volatile uint16_t mtu = 23;             // negotiated ATT MTU of the latest connection
};

inline SoundBoxBle& soundBoxBle() {
  static SoundBoxBle b;
  return b;
}

// Pack one `level` packet exactly as in docs/team-plan.md (5 bytes, little-endian).
inline void packLevel(uint8_t out[LEVEL_LEN], uint16_t seq, int16_t peakDbX10, uint8_t flags) {
  out[0] = seq & 0xFF;
  out[1] = seq >> 8;
  out[2] = (uint16_t)peakDbX10 & 0xFF;
  out[3] = (uint16_t)peakDbX10 >> 8;
  out[4] = flags;
}

class SoundBoxServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    Serial.printf("[ble] connected: %s (%u connection(s))\n", info.getAddress().toString().c_str(),
                  server->getConnectedCount());
    soundBoxBle().mtu = 23;
    ledSet(true);
  }
  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& info, int reason) override {
    Serial.printf("[ble] disconnected: %s, reason 0x%02X; advertising again\n",
                  info.getAddress().toString().c_str(), reason);
    SoundBoxBle& b = soundBoxBle();
    b.audioRequested = false;
    b.levelSubscribed = false;
    b.audioSubscribed = false;
    if (server->getConnectedCount() == 0) ledSet(false);
  }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo& info) override {
    soundBoxBle().mtu = mtu;
    Serial.printf("[ble] MTU = %u (audio needs >= %u)\n", mtu, AUDIO_LEN + 3);
  }
};

class SoundBoxCharCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& info) override {
    SoundBoxBle& b = soundBoxBle();
    if (c != b.control) return;
    NimBLEAttValue v = c->getValue();
    Serial.printf("[control] write of %u byte(s):", (unsigned)v.size());
    for (size_t i = 0; i < v.size(); i++) Serial.printf(" %02X", v[i]);
    if (v.size() == 1 && v[0] == CONTROL_START_AUDIO) {
      b.audioRequested = true;
      Serial.println("  -> START audio");
    } else if (v.size() == 1 && v[0] == CONTROL_STOP_AUDIO) {
      b.audioRequested = false;
      Serial.println("  -> STOP audio");
    } else {
      Serial.println("  -> ignored (contract: exactly 1 byte, 0 or 1)");
    }
  }
  void onSubscribe(NimBLECharacteristic* c, NimBLEConnInfo& info, uint16_t subValue) override {
    SoundBoxBle& b = soundBoxBle();
    const char* name = (c == b.level) ? "level" : (c == b.audio) ? "audio" : "?";
    if (c == b.level) b.levelSubscribed = (subValue != 0);
    if (c == b.audio) b.audioSubscribed = (subValue != 0);
    Serial.printf("[ble] %s %s\n", name, subValue ? "subscribed (notify on)" : "unsubscribed");
  }
};

// Start the service and advertising as SoundBox-<POSITION>. Returns false if advertising failed.
inline bool soundBoxBleBegin() {
  static SoundBoxServerCallbacks serverCallbacks;
  static SoundBoxCharCallbacks charCallbacks;
  SoundBoxBle& b = soundBoxBle();

  NimBLEDevice::init(BOX_BLE_NAME);   // also the GAP device name LightBlue shows after connecting
  NimBLEDevice::setMTU(247);          // iOS usually settles on 185; audio needs >= 172

  b.server = NimBLEDevice::createServer();
  b.server->setCallbacks(&serverCallbacks);
  b.server->advertiseOnDisconnect(true);

  NimBLEService* svc = b.server->createService(SOUNDBOX_SERVICE_UUID);
  b.level = svc->createCharacteristic(LEVEL_CHAR_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  b.audio = svc->createCharacteristic(AUDIO_CHAR_UUID, NIMBLE_PROPERTY::NOTIFY, AUDIO_LEN);
  b.control = svc->createCharacteristic(CONTROL_CHAR_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  b.level->setCallbacks(&charCallbacks);
  b.audio->setCallbacks(&charCallbacks);
  b.control->setCallbacks(&charCallbacks);

  uint8_t initLevel[LEVEL_LEN];
  packLevel(initLevel, 0, PEAK_DB_X10_FLOOR, 0);
  b.level->setValue(initLevel, LEVEL_LEN);
  uint8_t zeros[AUDIO_LEN] = {0};
  b.audio->setValue(zeros, AUDIO_LEN);
  uint8_t stop = CONTROL_STOP_AUDIO;
  b.control->setValue(&stop, 1);
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
  return adv->start();
}

inline void soundBoxNotifyLevel(uint16_t seq, int16_t peakDbX10, uint8_t flags, uint8_t pkt[LEVEL_LEN]) {
  SoundBoxBle& b = soundBoxBle();
  packLevel(pkt, seq, peakDbX10, flags);
  b.level->setValue(pkt, LEVEL_LEN);
  b.level->notify();   // no-op when nobody is subscribed
}

// Send one 169-byte audio packet. Returns false if it was not sent: nobody subscribed, the
// MTU is too small for 169 bytes (it would be cut short), or the BLE stack's buffers are full.
inline bool soundBoxNotifyAudio(const uint8_t pkt[AUDIO_LEN]) {
  SoundBoxBle& b = soundBoxBle();
  if (!b.audioSubscribed || b.mtu < AUDIO_LEN + 3) return false;
  return b.audio->notify(pkt, AUDIO_LEN);
}

inline void soundBoxPrintUuids() {
  Serial.printf("  BLE address  %s\n", NimBLEDevice::getAddress().toString().c_str());
  Serial.printf("  service      %s\n", SOUNDBOX_SERVICE_UUID);
  Serial.printf("  level        %s  (notify, 10 Hz, 5 B)\n", LEVEL_CHAR_UUID);
  Serial.printf("  audio        %s  (notify, 50 Hz, 169 B, after control = 01)\n", AUDIO_CHAR_UUID);
  Serial.printf("  control      %s  (write 01 = start, 00 = stop)\n", CONTROL_CHAR_UUID);
}
