idf_component_register(
    SRCS
        "main.c"
        "board_init.c"
        "wifi_manager.c"
        "hiboss_client.c"
        "ui_manager.c"
        "audio_manager.c"
    INCLUDE_DIRS "."
    REQUIRES
        esp_wifi
        esp_http_client
        esp_event
        nvs_flash
        json
        esp_psram
        driver
)
