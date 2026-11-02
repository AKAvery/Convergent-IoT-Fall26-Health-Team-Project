// wifi_secrets.example.h — template for the wifi_check environment.
// Copy to wifi_secrets.h (gitignored) and fill in a 2.4 GHz WPA2 or open network:
//
//   cp include/wifi_secrets.example.h include/wifi_secrets.h
//
// Enterprise networks with a username + password login won't work here. Use a home
// network or a phone hotspot (iPhone: turn on Maximize Compatibility for 2.4 GHz).
#pragma once

#define WIFI_SSID     "your-network-name"
#define WIFI_PASSWORD "your-password"   // "" for an open network
