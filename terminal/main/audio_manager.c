// audio_manager: Simple notification beep via ES8311 DAC.
// Generates a sine wave tone for new message alerts.
// Deps: ESP-IDF I2S driver, math.

#include "audio_manager.h"
#include "esp_log.h"

static const char *TAG = "audio";

void audio_init(void)
{
    // TODO: Initialize ES8311 codec and I2S output channel
    // Reference: Waveshare demo ES8311 init code
    ESP_LOGI(TAG, "Audio initialized (stub)");
}

void audio_play_notification(void)
{
    // TODO: Generate and play a short 800Hz beep (~200ms)
    // For MVP, just log — audio will be added in V2
    ESP_LOGI(TAG, "BEEP! New message notification");
}
