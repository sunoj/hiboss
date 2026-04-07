// hiboss-terminal: ESP32-S3 boss terminal for hiboss messaging system.
// Initializes hardware, WiFi, and starts polling + UI tasks.
// Deps: board_init, wifi_manager, hiboss_client, ui_manager, audio_manager.

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_psram.h"

#include "board_init.h"
#include "wifi_manager.h"
#include "hiboss_client.h"
#include "ui_manager.h"
#include "audio_manager.h"

static const char *TAG = "main";

void app_main(void)
{
    // Initialize NVS (required for WiFi)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // Suppress noisy I2C NACK errors from touch polling (CST816S sleeps when idle)
    esp_log_level_set("i2c.master", ESP_LOG_WARN);
    esp_log_level_set("lcd_panel.io.i2c", ESP_LOG_NONE);
    esp_log_level_set("CST816S", ESP_LOG_WARN);

    ESP_LOGI(TAG, "hiboss-terminal starting...");

    // Initialize hardware: LCD, touch, audio codecs
    board_init();

    // Initialize LVGL and create UI
    ui_init();
    ui_show_splash("hiboss terminal", "Connecting...");

    // Connect to WiFi
    wifi_init();
    wifi_connect();

    // Initialize audio (notification sounds)
    audio_init();

    // Initialize hiboss HTTP client
    hiboss_client_init();

    // Start polling task
    xTaskCreatePinnedToCore(
        hiboss_poll_task, "poll", 8192, NULL, 3, NULL, 1
    );

    ESP_LOGI(TAG, "hiboss-terminal ready");
}
