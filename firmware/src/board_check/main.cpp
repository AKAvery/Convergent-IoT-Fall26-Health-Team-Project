// board_check: confirm a bare XIAO ESP32-C3 or -S3 works. No mic or battery needed.
// Blinks the onboard user LED at 1 Hz and prints chip info over USB serial once a second.
#include <Arduino.h>
#include <esp_mac.h>
#include <esp_flash.h>
#include "box_config.h"
#include "led.h"

#if defined(CONFIG_IDF_TARGET_ESP32C3)
constexpr bool HAS_PSRAM = false;   // the C3 has none
#else
constexpr bool HAS_PSRAM = true;
#endif

static void printMac(const char* label, esp_mac_type_t type) {
  uint8_t m[6] = {0};
  esp_read_mac(m, type);
  Serial.printf("  %-14s %02X:%02X:%02X:%02X:%02X:%02X\n", label, m[0], m[1], m[2], m[3], m[4], m[5]);
}

void setup() {
  ledInit();
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);   // give the serial monitor a moment
}

void loop() {
  static uint32_t n = 0;

  ledSet(true);
  delay(500);
  ledSet(false);

  Serial.printf("\n[board_check #%lu] uptime %lu s, configured as %s\n",
                (unsigned long)n++, (unsigned long)(millis() / 1000), BOX_BLE_NAME);
  Serial.printf("  chip           %s rev %d, %d cores @ %lu MHz\n", ESP.getChipModel(),
                ESP.getChipRevision(), ESP.getChipCores(), (unsigned long)ESP.getCpuFreqMHz());
  printMac("MAC (Wi-Fi)", ESP_MAC_WIFI_STA);
  printMac("MAC (BLE)", ESP_MAC_BT);
  uint32_t physFlash = 0;
  esp_flash_get_physical_size(NULL, &physFlash);   // read from the chip's JEDEC ID
  Serial.printf("  flash          %lu MB on chip, %lu MB in image header (%lu MHz)\n",
                (unsigned long)(physFlash >> 20), (unsigned long)(ESP.getFlashChipSize() >> 20),
                (unsigned long)(ESP.getFlashChipSpeed() / 1000000));
  Serial.printf("  PSRAM          %lu KB total, %lu KB free%s\n", (unsigned long)(ESP.getPsramSize() >> 10),
                (unsigned long)(ESP.getFreePsram() >> 10), ESP.getPsramSize() || !HAS_PSRAM ? "" : "  <-- PSRAM NOT FOUND");
  Serial.printf("  heap           %lu KB free\n", (unsigned long)(ESP.getFreeHeap() >> 10));
  Serial.printf("  sdk            %s\n", ESP.getSdkVersion());

  delay(500);
}
