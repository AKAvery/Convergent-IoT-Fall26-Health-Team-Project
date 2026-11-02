// wifi_check: confirm a XIAO ESP32-S3's Wi-Fi radio and antenna work. No mic needed.
// Wi-Fi is not part of the box contract (the boxes talk BLE). This is a bring-up test only.
//
// - Scans once and lists every network it can hear (SSID, RSSI, channel, security).
// - Joins WIFI_SSID from include/wifi_secrets.h and prints the reason when it can't.
// - Once connected: prints IP, gateway, DNS and signal, then fetches
//   captive.apple.com to check for real internet access (vs. no route or a login page).
// - Then prints RSSI every 5 s and retries on its own if the network drops.
// - The user LED blinks fast while connecting and stays on while connected.
#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include "box_config.h"
#include "led.h"

#if __has_include("wifi_secrets.h")
#include "wifi_secrets.h"
#else
#error "Copy include/wifi_secrets.example.h to include/wifi_secrets.h and fill in your network"
#endif

constexpr uint32_t CONNECT_TIMEOUT_MS = 20000;   // give up on one attempt and start a new one
constexpr uint32_t STATUS_PERIOD_MS   = 5000;

static volatile uint8_t lastReason = 0;   // last disconnect reason, set from the Wi-Fi event task
static volatile bool    gotIp      = false;

static const char* authName(wifi_auth_mode_t a) {
  switch (a) {
    case WIFI_AUTH_OPEN:            return "open";
    case WIFI_AUTH_WEP:             return "WEP";
    case WIFI_AUTH_WPA_PSK:         return "WPA";
    case WIFI_AUTH_WPA2_PSK:        return "WPA2";
    case WIFI_AUTH_WPA_WPA2_PSK:    return "WPA/WPA2";
    case WIFI_AUTH_WPA2_ENTERPRISE: return "WPA2-Enterprise";
    case WIFI_AUTH_WPA3_PSK:        return "WPA3";
    case WIFI_AUTH_WPA2_WPA3_PSK:   return "WPA2/WPA3";
    default:                        return "other";
  }
}

// What a disconnect reason usually means in practice.
static const char* reasonHint(uint8_t r) {
  switch (r) {
    case WIFI_REASON_NO_AP_FOUND:
      return "network not heard: check the SSID spelling, that it's 2.4 GHz, and the antenna";
    case WIFI_REASON_AUTH_FAIL:
    case WIFI_REASON_AUTH_EXPIRE:
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_HANDSHAKE_TIMEOUT:
      return "usually a wrong password (or an enterprise / WPA3-only network)";
    case WIFI_REASON_ASSOC_FAIL:
    case WIFI_REASON_CONNECTION_FAIL:
      return "router refused us: MAC filtering, device registration or a full network";
    case WIFI_REASON_BEACON_TIMEOUT:
      return "lost the signal: move closer or check the antenna";
    default:
      return "";
  }
}

static void onWiFiEvent(arduino_event_id_t event, arduino_event_info_t info) {
  switch (event) {
    case ARDUINO_EVENT_WIFI_STA_CONNECTED:
      Serial.printf("[wifi] associated with \"%.*s\" on channel %u\n", info.wifi_sta_connected.ssid_len,
                    (const char*)info.wifi_sta_connected.ssid, info.wifi_sta_connected.channel);
      break;
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      gotIp = true;
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED: {
      uint8_t r = info.wifi_sta_disconnected.reason;
      gotIp = false;
      if (r == WIFI_REASON_ASSOC_LEAVE) break;   // our own WiFi.disconnect() before a retry
      if (r != lastReason) {   // the same failure repeats on every retry, print it once
        Serial.printf("[wifi] disconnected, reason %u %s. %s\n", r,
                      WiFi.disconnectReasonName((wifi_err_reason_t)r), reasonHint(r));
      }
      lastReason = r;
      break;
    }
    default:
      break;
  }
}

static void scan() {
  Serial.println("[scan] scanning...");
  int n = WiFi.scanNetworks();
  if (n <= 0) {
    Serial.println("[scan] no networks found. Is the antenna plugged in?");
    return;
  }
  bool found = false;
  Serial.printf("[scan] %d network(s), strongest first:\n", n);
  Serial.println("       RSSI  ch  security         SSID");
  for (int i = 0; i < n; i++) {
    String ssid = WiFi.SSID(i);
    bool target = ssid == WIFI_SSID;
    found |= target;
    Serial.printf("  %s  %4ld  %2ld  %-16s %s\n", target ? "->" : "  ", (long)WiFi.RSSI(i),
                  (long)WiFi.channel(i), authName(WiFi.encryptionType(i)),
                  ssid.length() ? ssid.c_str() : "(hidden)");
  }
  if (!found) {
    Serial.printf("[scan] \"%s\" not in the list. The ESP32-S3 only sees 2.4 GHz. "
                  "An iPhone hotspot needs Maximize Compatibility on and its settings screen open.\n",
                  WIFI_SSID);
  }
  WiFi.scanDelete();
}

static void startConnect() {
  Serial.printf("[wifi] connecting to \"%s\"...\n", WIFI_SSID);
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

static void printConnected() {
  Serial.printf("[wifi] %s CONNECTED to \"%s\"\n", BOX_BLE_NAME, WiFi.SSID().c_str());
  Serial.printf("  ip             %s\n", WiFi.localIP().toString().c_str());
  Serial.printf("  gateway        %s\n", WiFi.gatewayIP().toString().c_str());
  Serial.printf("  dns            %s\n", WiFi.dnsIP().toString().c_str());
  Serial.printf("  rssi           %d dBm, channel %ld\n", WiFi.RSSI(), (long)WiFi.channel());
  Serial.printf("  MAC            %s\n", WiFi.macAddress().c_str());
}

// captive.apple.com answers plain HTTP with a page containing "Success". Anything else means
// a login page sits in the way. No answer at all means no internet (or no DNS).
static void checkInternet() {
  IPAddress ip;
  uint32_t t0 = millis();
  if (!WiFi.hostByName("captive.apple.com", ip)) {
    Serial.println("[net] DNS lookup failed: connected to the router, but no internet");
    return;
  }
  Serial.printf("[net] DNS ok: captive.apple.com = %s (%lu ms)\n", ip.toString().c_str(),
                (unsigned long)(millis() - t0));

  HTTPClient http;
  http.setTimeout(5000);
  http.begin("http://captive.apple.com/hotspot-detect.html");
  t0 = millis();
  int code = http.GET();
  uint32_t ms = millis() - t0;
  if (code <= 0) {
    Serial.printf("[net] HTTP failed: %s\n", http.errorToString(code).c_str());
  } else if (code == 200 && http.getString().indexOf("Success") >= 0) {
    Serial.printf("[net] INTERNET OK (HTTP 200 in %lu ms)\n", (unsigned long)ms);
  } else {
    Serial.printf("[net] HTTP %d but not Apple's page: a captive portal (login page) is in the way. "
                  "The ESP32 can't sign in to those, so use a home network or a phone hotspot.\n", code);
  }
  http.end();
}

void setup() {
  ledInit();
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);   // give the serial monitor a moment

  Serial.printf("\n[wifi_check] %s, Wi-Fi MAC %s\n", BOX_BLE_NAME, WiFi.macAddress().c_str());
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(false);   // loop() does the retrying so failures stay visible
  WiFi.onEvent(onWiFiEvent);
  scan();
  startConnect();
}

void loop() {
  static uint32_t attemptStart = millis();
  static uint32_t lastStatus = 0;
  static bool reported = false;   // printed the connected block for this connection yet?

  if (gotIp) {
    ledSet(true);
    if (!reported) {
      reported = true;
      lastReason = 0;
      printConnected();
      checkInternet();
      lastStatus = millis();
    }
    if (millis() - lastStatus >= STATUS_PERIOD_MS) {
      lastStatus = millis();
      Serial.printf("[wifi] up %lu s, rssi %d dBm\n", (unsigned long)(millis() / 1000), WiFi.RSSI());
    }
  } else {
    ledSet((millis() / 100) % 2);   // 5 Hz blink
    if (reported) {
      reported = false;
      attemptStart = millis();
      startConnect();
    } else if (millis() - attemptStart >= CONNECT_TIMEOUT_MS) {
      Serial.printf("[wifi] no connection after %lu s, retrying\n", (unsigned long)(CONNECT_TIMEOUT_MS / 1000));
      attemptStart = millis();
      startConnect();
    }
  }
  delay(10);
}
