// hiboss_client: HTTP client for hiboss server API (boss-authenticated).
// Exports: hiboss_client_init(), hiboss_poll_task(), hiboss_reply(), hiboss_mark_read(), hiboss_react().
// Deps: esp_http_client, cJSON, wifi_manager.

#pragma once

#include "esp_err.h"

// Maximum messages to display
#define HIBOSS_MAX_MESSAGES 10
// Poll interval in milliseconds
#define HIBOSS_POLL_INTERVAL_MS 5000

// A parsed hiboss message
typedef struct {
    char id[40];
    char agent_name[32];
    char body[512];
    char priority[16];
    char options[256];    // comma-separated options from metadata
    char created_at[32];
    int has_options;
} hiboss_message_t;

// Initialize the HTTP client (reads config from NVS).
void hiboss_client_init(void);

// FreeRTOS task: polls /api/boss/messages?unread=true every POLL_INTERVAL.
void hiboss_poll_task(void *arg);

// Send a reply to a message. Body is the reply text.
esp_err_t hiboss_reply(const char *message_id, const char *body);

// Mark a message as read on the server.
esp_err_t hiboss_mark_read(const char *message_id);

// React to a message with an emoji.
esp_err_t hiboss_react(const char *message_id, const char *emoji);

// Get the latest unread messages (filled by poll task).
int hiboss_get_messages(hiboss_message_t *out, int max_count);
