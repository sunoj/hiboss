// board_init: Hardware initialization for Waveshare ESP32-S3-Touch-LCD-1.85C.
// Exports: board_init() — sets up LCD (ST77916), touch (CST816), I2C, SPI.
// Deps: ESP-IDF driver, esp_lcd, esp_lcd_touch.

#pragma once

#include "esp_err.h"

// Initialize all board hardware (LCD, touch, I2C bus, SPI bus).
void board_init(void);
