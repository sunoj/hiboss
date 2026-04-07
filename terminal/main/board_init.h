// board_init: Hardware initialization for Waveshare ESP32-S3-Touch-LCD-1.85C.
// Exports: board_init(), panel/touch handles for UI.
// Deps: esp_lcd, esp_lcd_touch, esp_lvgl_port.

#pragma once

#include "esp_err.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_touch.h"
#include "driver/i2c_master.h"

// Hardware handles (set by board_init)
extern esp_lcd_panel_handle_t g_panel_handle;
extern esp_lcd_touch_handle_t g_touch_handle;
extern i2c_master_bus_handle_t g_i2c_bus;

// Display dimensions
#define LCD_H_RES 360
#define LCD_V_RES 360

// Initialize all board hardware: I2C, IO expander, LCD, touch, LVGL port.
void board_init(void);
