// ui_manager: LVGL-based UI for hiboss terminal on 360x360 circular display.
// Exports: ui_init(), ui_show_splash(), ui_show_idle(), ui_show_messages().
// Deps: lvgl, esp_lvgl_port, hiboss_client (for message types).

#pragma once

#include "hiboss_client.h"

// Initialize LVGL display and input drivers.
void ui_init(void);

// Show splash screen with title and subtitle.
void ui_show_splash(const char *title, const char *subtitle);

// Show idle screen (clock + "0 unread").
void ui_show_idle(void);

// Show message list with touch-to-reply buttons.
void ui_show_messages(const hiboss_message_t *msgs, int count);
