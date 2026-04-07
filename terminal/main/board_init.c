// board_init: Hardware initialization for Waveshare ESP32-S3-Touch-LCD-1.85C.
// Sets up I2C, SPI, LCD (ST77916 360x360), and touch (CST816).
// Deps: ESP-IDF driver, esp_lcd, esp_lcd_touch components.

#include "board_init.h"
#include "esp_log.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"

static const char *TAG = "board";

// Pin definitions for Waveshare ESP32-S3-Touch-LCD-1.85C
// LCD (SPI)
#define LCD_SPI_HOST    SPI2_HOST
#define LCD_PIN_MOSI    GPIO_NUM_13
#define LCD_PIN_CLK     GPIO_NUM_14
#define LCD_PIN_CS      GPIO_NUM_10
#define LCD_PIN_DC      GPIO_NUM_11
#define LCD_PIN_RST     GPIO_NUM_12
#define LCD_PIN_BL      GPIO_NUM_15

// Touch (I2C)
#define TOUCH_I2C_PORT  I2C_NUM_0
#define TOUCH_PIN_SDA   GPIO_NUM_7
#define TOUCH_PIN_SCL   GPIO_NUM_8
#define TOUCH_PIN_INT   GPIO_NUM_9
#define TOUCH_PIN_RST   GPIO_NUM_6

// Display dimensions
#define LCD_H_RES       360
#define LCD_V_RES       360

void board_init(void)
{
    ESP_LOGI(TAG, "Initializing board hardware...");

    // I2C bus for touch controller
    i2c_master_bus_config_t i2c_bus_config = {
        .i2c_port = TOUCH_I2C_PORT,
        .sda_io_num = TOUCH_PIN_SDA,
        .scl_io_num = TOUCH_PIN_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    i2c_master_bus_handle_t i2c_bus = NULL;
    ESP_ERROR_CHECK(i2c_new_master_bus(&i2c_bus_config, &i2c_bus));
    ESP_LOGI(TAG, "I2C bus initialized");

    // Backlight GPIO
    gpio_config_t bl_config = {
        .pin_bit_mask = (1ULL << LCD_PIN_BL),
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&bl_config);
    gpio_set_level(LCD_PIN_BL, 1);
    ESP_LOGI(TAG, "Backlight ON");

    // TODO: Initialize LCD panel (ST77916) via esp_lcd component
    // TODO: Initialize touch panel (CST816) via esp_lcd_touch component
    // These require managed components — added in idf_component.yml

    ESP_LOGI(TAG, "Board initialized (LCD + Touch TBD via components)");
}
