// led.h: the user LED, or nothing on boards without one (XIAO ESP32-C3, PIN_LED = -1).
#pragma once

#include <Arduino.h>
#include "box_config.h"

inline void ledInit() {
  if (PIN_LED < 0) return;
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LED_OFF);
}

inline void ledSet(bool on) {
  if (PIN_LED >= 0) digitalWrite(PIN_LED, on ? LED_ON : LED_OFF);
}
