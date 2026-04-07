// hiboss-terminal: ESP32-S3 boss terminal for hiboss messaging system.
// Initializes hardware, WiFi, SNTP, and starts polling + UI tasks.
// Deps: board_init, wifi_manager, hiboss_client, ui_manager, audio_manager.

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_psram.h"
#include "esp_sntp.h"
#include "esp_system.h"
#include "soc/rtc_cntl_reg.h"
#include "driver/usb_serial_jtag.h"

#include "board_init.h"
#include "wifi_manager.h"
#include "hiboss_client.h"
#include "ui_manager.h"
#include "audio_manager.h"

static const char *TAG = "main";

static void init_sntp(void)
{
    setenv("TZ", "ICT-7", 1);  // Bangkok UTC+7
    tzset();
    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, "pool.ntp.org");
    esp_sntp_init();
    ESP_LOGI(TAG, "SNTP initialized (TZ=ICT-7)");
}

// Listen for "boot" command on USB serial → reboot to download mode
static void bootloader_listen_task(void *arg)
{
    usb_serial_jtag_driver_config_t cfg = { .rx_buffer_size = 256, .tx_buffer_size = 256 };
    usb_serial_jtag_driver_install(&cfg);
    char buf[16];
    int pos = 0;
    while (1) {
        int len = usb_serial_jtag_read_bytes(buf + pos, 1, pdMS_TO_TICKS(500));
        if (len > 0) {
            if (buf[pos] == '\n' || buf[pos] == '\r') {
                buf[pos] = '\0';
                if (strcmp(buf, "boot") == 0) {
                    ESP_LOGW(TAG, "Rebooting to bootloader...");
                    vTaskDelay(pdMS_TO_TICKS(100));
                    REG_WRITE(RTC_CNTL_OPTION1_REG, RTC_CNTL_FORCE_DOWNLOAD_BOOT);
                    esp_restart();
                }
                pos = 0;
            } else {
                pos = (pos < 14) ? pos + 1 : 0;
            }
        }
    }
}

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

    // Connect to WiFi (non-blocking, 15s timeout)
    wifi_init();
    wifi_connect();

    // Sync time via SNTP after WiFi
    if (wifi_is_connected()) {
        init_sntp();
        ui_show_splash("hiboss terminal", "WiFi OK");
    } else {
        ui_show_splash("hiboss terminal", "WiFi FAILED");
    }

    // Initialize audio (notification sounds)
    audio_init();

    // Initialize hiboss HTTP client
    hiboss_client_init();

    // Start polling task
    xTaskCreatePinnedToCore(
        hiboss_poll_task, "poll", 16384, NULL, 3, NULL, 1
    );

    // Listen for "boot" command on USB serial to enter bootloader without pressing buttons
    xTaskCreate(bootloader_listen_task, "bootl", 4096, NULL, 1, NULL);

    ESP_LOGI(TAG, "hiboss-terminal ready");
}
