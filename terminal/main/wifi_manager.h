// wifi_manager: WiFi STA connection with auto-reconnect.
// Exports: wifi_init(), wifi_connect(), wifi_is_connected().
// Deps: esp_wifi, esp_event, nvs_flash.

#pragma once

#include <stdbool.h>

// Initialize WiFi subsystem (event loop, netif).
void wifi_init(void);

// Connect to configured AP. Blocks until connected or timeout.
void wifi_connect(void);

// Check if WiFi is currently connected.
bool wifi_is_connected(void);
