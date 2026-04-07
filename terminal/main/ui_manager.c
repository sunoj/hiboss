// ui_manager: LVGL UI for hiboss terminal — splash, idle clock, message cards.
// Renders on 360x360 circular LCD. Thread-safe via lvgl_port_lock().
// Deps: lvgl, esp_lvgl_port, hiboss_client.

#include "ui_manager.h"
#include "hiboss_client.h"
#include "esp_log.h"
#include "esp_lvgl_port.h"
#include "lvgl.h"

#include <string.h>
#include <time.h>

static const char *TAG = "ui";

// Screen references
static lv_obj_t *scr_splash = NULL;
static lv_obj_t *scr_idle = NULL;
static lv_obj_t *scr_messages = NULL;

// Currently displayed message (for reply callbacks)
static hiboss_message_t s_current_msg;

// Forward declarations
static void create_splash_screen(const char *title, const char *subtitle);
static void create_idle_screen(void);
static void create_messages_screen(const hiboss_message_t *msgs, int count);
static void option_btn_event_cb(lv_event_t *e);

void ui_init(void)
{
    // LVGL initialization is handled by esp_lvgl_port in board_init
    // We just set up default styles here
    ESP_LOGI(TAG, "UI initialized");
}

void ui_show_splash(const char *title, const char *subtitle)
{
    if (lvgl_port_lock(0)) {
        create_splash_screen(title, subtitle);
        lv_scr_load(scr_splash);
        lvgl_port_unlock();
    }
}

void ui_show_idle(void)
{
    if (lvgl_port_lock(0)) {
        create_idle_screen();
        lv_scr_load(scr_idle);
        lvgl_port_unlock();
    }
}

void ui_show_messages(const hiboss_message_t *msgs, int count)
{
    if (lvgl_port_lock(0)) {
        create_messages_screen(msgs, count);
        lv_scr_load(scr_messages);
        lvgl_port_unlock();
    }
}

// --- Screen builders ---

static void create_splash_screen(const char *title, const char *subtitle)
{
    if (scr_splash) lv_obj_del(scr_splash);
    scr_splash = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(scr_splash, lv_color_hex(0x1a1a2e), 0);

    // Title
    lv_obj_t *lbl_title = lv_label_create(scr_splash);
    lv_label_set_text(lbl_title, title);
    lv_obj_set_style_text_color(lbl_title, lv_color_hex(0x00d4ff), 0);
    lv_obj_set_style_text_font(lbl_title, &lv_font_montserrat_24, 0);
    lv_obj_align(lbl_title, LV_ALIGN_CENTER, 0, -20);

    // Subtitle
    lv_obj_t *lbl_sub = lv_label_create(scr_splash);
    lv_label_set_text(lbl_sub, subtitle);
    lv_obj_set_style_text_color(lbl_sub, lv_color_hex(0x888888), 0);
    lv_obj_align(lbl_sub, LV_ALIGN_CENTER, 0, 20);
}

static void create_idle_screen(void)
{
    if (scr_idle) lv_obj_del(scr_idle);
    scr_idle = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(scr_idle, lv_color_hex(0x0a0a1a), 0);

    // Clock (static for now — could add timer to update)
    time_t now;
    time(&now);
    struct tm *t = localtime(&now);
    char time_str[8];
    snprintf(time_str, sizeof(time_str), "%02d:%02d", t->tm_hour, t->tm_min);

    lv_obj_t *lbl_time = lv_label_create(scr_idle);
    lv_label_set_text(lbl_time, time_str);
    lv_obj_set_style_text_color(lbl_time, lv_color_hex(0xffffff), 0);
    lv_obj_set_style_text_font(lbl_time, &lv_font_montserrat_48, 0);
    lv_obj_align(lbl_time, LV_ALIGN_CENTER, 0, -40);

    // Status
    lv_obj_t *lbl_status = lv_label_create(scr_idle);
    lv_label_set_text(lbl_status, "0 unread");
    lv_obj_set_style_text_color(lbl_status, lv_color_hex(0x44ff44), 0);
    lv_obj_align(lbl_status, LV_ALIGN_CENTER, 0, 20);

    // Brand
    lv_obj_t *lbl_brand = lv_label_create(scr_idle);
    lv_label_set_text(lbl_brand, "hiboss");
    lv_obj_set_style_text_color(lbl_brand, lv_color_hex(0x333344), 0);
    lv_obj_align(lbl_brand, LV_ALIGN_CENTER, 0, 60);
}

static void create_messages_screen(const hiboss_message_t *msgs, int count)
{
    if (scr_messages) lv_obj_del(scr_messages);
    scr_messages = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(scr_messages, lv_color_hex(0x0a0a1a), 0);

    if (count == 0) return;

    // Show the most recent message prominently
    const hiboss_message_t *msg = &msgs[0];
    memcpy(&s_current_msg, msg, sizeof(s_current_msg));

    // Agent name header
    lv_obj_t *lbl_agent = lv_label_create(scr_messages);
    lv_label_set_text(lbl_agent, msg->agent_name);
    lv_obj_set_style_text_color(lbl_agent, lv_color_hex(0x00d4ff), 0);
    lv_obj_set_style_text_font(lbl_agent, &lv_font_montserrat_18, 0);
    lv_obj_align(lbl_agent, LV_ALIGN_TOP_MID, 0, 30);

    // Unread count badge
    if (count > 1) {
        char badge[16];
        snprintf(badge, sizeof(badge), "+%d more", count - 1);
        lv_obj_t *lbl_badge = lv_label_create(scr_messages);
        lv_label_set_text(lbl_badge, badge);
        lv_obj_set_style_text_color(lbl_badge, lv_color_hex(0xff8800), 0);
        lv_obj_align(lbl_badge, LV_ALIGN_TOP_MID, 0, 55);
    }

    // Message body (truncated for small screen)
    lv_obj_t *lbl_body = lv_label_create(scr_messages);
    lv_label_set_long_mode(lbl_body, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(lbl_body, 280);
    lv_label_set_text(lbl_body, msg->body);
    lv_obj_set_style_text_color(lbl_body, lv_color_hex(0xcccccc), 0);
    lv_obj_set_style_text_font(lbl_body, &lv_font_montserrat_14, 0);
    lv_obj_align(lbl_body, LV_ALIGN_TOP_MID, 0, 75);

    // Option buttons (if message has options)
    if (msg->has_options) {
        // Parse comma-separated options
        char opts_copy[256];
        strncpy(opts_copy, msg->options, sizeof(opts_copy) - 1);
        opts_copy[sizeof(opts_copy) - 1] = '\0';

        int btn_y = 200;
        char *token = strtok(opts_copy, ",");
        int opt_idx = 0;
        while (token && opt_idx < 4) {
            // Trim whitespace
            while (*token == ' ') token++;

            lv_obj_t *btn = lv_btn_create(scr_messages);
            lv_obj_set_size(btn, 200, 36);
            lv_obj_align(btn, LV_ALIGN_TOP_MID, 0, btn_y);
            lv_obj_set_style_bg_color(btn, lv_color_hex(0x1a3a5c), 0);
            lv_obj_set_style_radius(btn, 18, 0);

            lv_obj_t *lbl = lv_label_create(btn);
            lv_label_set_text(lbl, token);
            lv_obj_set_style_text_color(lbl, lv_color_hex(0x00d4ff), 0);
            lv_obj_center(lbl);

            // Store option text as user data for callback
            char *opt_text = lv_malloc(strlen(token) + 1);
            strcpy(opt_text, token);
            lv_obj_add_event_cb(btn, option_btn_event_cb, LV_EVENT_CLICKED, opt_text);

            btn_y += 42;
            opt_idx++;
            token = strtok(NULL, ",");
        }
    }
}

static void option_btn_event_cb(lv_event_t *e)
{
    char *option_text = (char *)lv_event_get_user_data(e);
    if (!option_text) return;

    ESP_LOGI(TAG, "Option selected: %s", option_text);

    // Send reply in a separate task to avoid blocking LVGL
    // For MVP, we do it inline (brief block is acceptable)
    hiboss_reply(s_current_msg.id, option_text);

    // Show confirmation
    ui_show_splash("Sent!", option_text);
}
