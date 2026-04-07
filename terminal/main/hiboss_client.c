// hiboss_client: Polls hiboss server for unread boss messages and sends replies.
// Uses esp_http_client for HTTPS, cJSON for parsing.
// Deps: esp_http_client, cJSON, freertos, wifi_manager, ui_manager, audio_manager.

#include "hiboss_client.h"
#include "wifi_manager.h"
#include "ui_manager.h"
#include "audio_manager.h"

#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_crt_bundle.h"
#include "cJSON.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include <string.h>
#include <stdio.h>

static const char *TAG = "hiboss";

// Configuration — set via menuconfig or NVS
static char s_server_url[128] = CONFIG_HIBOSS_SERVER_URL;
static char s_boss_api_key[128] = CONFIG_HIBOSS_BOSS_API_KEY;

// Message buffer
static hiboss_message_t s_messages[HIBOSS_MAX_MESSAGES];
static int s_message_count = 0;
static SemaphoreHandle_t s_msg_mutex;

// HTTP response buffer
#define HTTP_BUF_SIZE 4096
static char s_http_buf[HTTP_BUF_SIZE];
static int s_http_buf_len = 0;

static esp_err_t http_event_handler(esp_http_client_event_t *evt)
{
    switch (evt->event_id) {
    case HTTP_EVENT_ON_DATA:
        if (s_http_buf_len + evt->data_len < HTTP_BUF_SIZE - 1) {
            memcpy(s_http_buf + s_http_buf_len, evt->data, evt->data_len);
            s_http_buf_len += evt->data_len;
            s_http_buf[s_http_buf_len] = '\0';
        }
        break;
    default:
        break;
    }
    return ESP_OK;
}

void hiboss_client_init(void)
{
    s_msg_mutex = xSemaphoreCreateMutex();
    ESP_LOGI(TAG, "Client initialized, server: %s", s_server_url);
}

static void parse_messages(const char *json_str)
{
    cJSON *root = cJSON_Parse(json_str);
    if (!root) {
        ESP_LOGE(TAG, "JSON parse failed");
        return;
    }

    cJSON *messages = cJSON_GetObjectItem(root, "messages");
    if (!cJSON_IsArray(messages)) {
        cJSON_Delete(root);
        return;
    }

    int new_count = 0;
    hiboss_message_t new_msgs[HIBOSS_MAX_MESSAGES];

    cJSON *msg;
    cJSON_ArrayForEach(msg, messages) {
        if (new_count >= HIBOSS_MAX_MESSAGES) break;
        hiboss_message_t *m = &new_msgs[new_count];
        memset(m, 0, sizeof(*m));

        cJSON *id = cJSON_GetObjectItem(msg, "id");
        cJSON *body = cJSON_GetObjectItem(msg, "body");
        cJSON *agent_name = cJSON_GetObjectItem(msg, "agent_name");
        cJSON *priority = cJSON_GetObjectItem(msg, "priority");
        cJSON *created_at = cJSON_GetObjectItem(msg, "created_at");
        cJSON *metadata = cJSON_GetObjectItem(msg, "metadata");

        if (cJSON_IsString(id)) snprintf(m->id, sizeof(m->id), "%s", id->valuestring);
        if (cJSON_IsString(body)) snprintf(m->body, sizeof(m->body), "%s", body->valuestring);
        if (cJSON_IsString(agent_name)) snprintf(m->agent_name, sizeof(m->agent_name), "%s", agent_name->valuestring);
        if (cJSON_IsString(priority)) snprintf(m->priority, sizeof(m->priority), "%s", priority->valuestring);
        if (cJSON_IsString(created_at)) snprintf(m->created_at, sizeof(m->created_at), "%s", created_at->valuestring);

        // Extract options from metadata
        if (cJSON_IsObject(metadata)) {
            cJSON *options = cJSON_GetObjectItem(metadata, "options");
            if (cJSON_IsArray(options)) {
                m->has_options = 1;
                m->options[0] = '\0';
                cJSON *opt;
                cJSON_ArrayForEach(opt, options) {
                    if (cJSON_IsString(opt)) {
                        if (m->options[0] != '\0') strncat(m->options, ",", sizeof(m->options) - strlen(m->options) - 1);
                        strncat(m->options, opt->valuestring, sizeof(m->options) - strlen(m->options) - 1);
                    }
                }
            }
        }

        new_count++;
    }

    cJSON_Delete(root);

    // Update shared buffer
    if (xSemaphoreTake(s_msg_mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        int had_messages = s_message_count;
        memcpy(s_messages, new_msgs, sizeof(new_msgs));
        s_message_count = new_count;
        xSemaphoreGive(s_msg_mutex);

        // Notify UI of new messages
        if (new_count > 0) {
            ui_show_messages(new_msgs, new_count);
            if (new_count > had_messages) {
                audio_play_notification();
            }
            // Mark displayed messages as read on server
            for (int i = 0; i < new_count; i++) {
                hiboss_mark_read(new_msgs[i].id);
            }
        } else {
            ui_show_idle();
        }
    }
}

static void poll_messages(void)
{
    s_http_buf_len = 0;
    s_http_buf[0] = '\0';

    char url[256];
    snprintf(url, sizeof(url), "%s/api/boss/messages?unread=true&limit=10", s_server_url);

    char auth_header[160];
    snprintf(auth_header, sizeof(auth_header), "Bearer %s", s_boss_api_key);

    esp_http_client_config_t config = {
        .url = url,
        .event_handler = http_event_handler,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 10000,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    esp_http_client_set_header(client, "Authorization", auth_header);

    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) {
        int status = esp_http_client_get_status_code(client);
        if (status == 200) {
            parse_messages(s_http_buf);
        } else {
            ESP_LOGW(TAG, "Poll returned HTTP %d", status);
        }
    } else {
        ESP_LOGE(TAG, "Poll failed: %s", esp_err_to_name(err));
    }

    esp_http_client_cleanup(client);
}

void hiboss_poll_task(void *arg)
{
    // Wait for WiFi
    while (!wifi_is_connected()) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    ESP_LOGI(TAG, "Starting message polling");

    while (1) {
        poll_messages();
        vTaskDelay(pdMS_TO_TICKS(HIBOSS_POLL_INTERVAL_MS));
    }
}

esp_err_t hiboss_reply(const char *message_id, const char *body)
{
    char url[256];
    snprintf(url, sizeof(url), "%s/api/boss/messages/%s/reply", s_server_url, message_id);

    char auth_header[160];
    snprintf(auth_header, sizeof(auth_header), "Bearer %s", s_boss_api_key);

    // Build JSON body
    cJSON *payload = cJSON_CreateObject();
    cJSON_AddStringToObject(payload, "body", body);
    char *json_str = cJSON_PrintUnformatted(payload);
    cJSON_Delete(payload);

    s_http_buf_len = 0;
    esp_http_client_config_t config = {
        .url = url,
        .event_handler = http_event_handler,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 10000,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    esp_http_client_set_method(client, HTTP_METHOD_POST);
    esp_http_client_set_header(client, "Authorization", auth_header);
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_post_field(client, json_str, strlen(json_str));

    esp_err_t err = esp_http_client_perform(client);
    int status = esp_http_client_get_status_code(client);

    esp_http_client_cleanup(client);
    free(json_str);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Reply failed: %s", esp_err_to_name(err));
        return err;
    }
    if (status != 201) {
        ESP_LOGW(TAG, "Reply returned HTTP %d", status);
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Reply sent to %s", message_id);
    return ESP_OK;
}

esp_err_t hiboss_mark_read(const char *message_id)
{
    char url[256];
    snprintf(url, sizeof(url), "%s/api/boss/messages/%s", s_server_url, message_id);

    char auth_header[160];
    snprintf(auth_header, sizeof(auth_header), "Bearer %s", s_boss_api_key);

    const char *json_str = "{\"status\":\"read\"}";

    s_http_buf_len = 0;
    esp_http_client_config_t config = {
        .url = url,
        .event_handler = http_event_handler,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 5000,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    esp_http_client_set_method(client, HTTP_METHOD_PATCH);
    esp_http_client_set_header(client, "Authorization", auth_header);
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_post_field(client, json_str, strlen(json_str));

    esp_err_t err = esp_http_client_perform(client);
    int status = esp_http_client_get_status_code(client);
    esp_http_client_cleanup(client);

    if (err != ESP_OK || status != 200) {
        ESP_LOGW(TAG, "Mark-read failed for %s (HTTP %d)", message_id, status);
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t hiboss_react(const char *message_id, const char *emoji)
{
    char url[256];
    snprintf(url, sizeof(url), "%s/api/boss/messages/%s/react", s_server_url, message_id);

    char auth_header[160];
    snprintf(auth_header, sizeof(auth_header), "Bearer %s", s_boss_api_key);

    cJSON *payload = cJSON_CreateObject();
    cJSON_AddStringToObject(payload, "emoji", emoji);
    char *json_str = cJSON_PrintUnformatted(payload);
    cJSON_Delete(payload);

    s_http_buf_len = 0;
    esp_http_client_config_t config = {
        .url = url,
        .event_handler = http_event_handler,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 5000,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    esp_http_client_set_method(client, HTTP_METHOD_POST);
    esp_http_client_set_header(client, "Authorization", auth_header);
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_post_field(client, json_str, strlen(json_str));

    esp_err_t err = esp_http_client_perform(client);
    int status = esp_http_client_get_status_code(client);
    esp_http_client_cleanup(client);
    free(json_str);

    if (err != ESP_OK || status != 200) {
        ESP_LOGW(TAG, "React failed for %s (HTTP %d)", message_id, status);
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "Reacted %s to %s", emoji, message_id);
    return ESP_OK;
}

int hiboss_get_messages(hiboss_message_t *out, int max_count)
{
    int count = 0;
    if (xSemaphoreTake(s_msg_mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        count = s_message_count < max_count ? s_message_count : max_count;
        memcpy(out, s_messages, count * sizeof(hiboss_message_t));
        xSemaphoreGive(s_msg_mutex);
    }
    return count;
}
