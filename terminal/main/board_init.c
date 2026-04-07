// board_init: Hardware initialization for Waveshare ESP32-S3-Touch-LCD-1.85C.
// Sets up I2C, QSPI LCD (ST77916 360x360), touch (CST816S), and backlight.
// Deps: esp_lcd, esp_lcd_st77916, esp_lcd_touch_cst816s, esp_lvgl_port.

#include "board_init.h"
#include "esp_log.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_st77916.h"
#include "esp_lcd_touch_cst816s.h"
#include "esp_lvgl_port.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "driver/ledc.h"

static const char *TAG = "board";

// --- Pin definitions (from Waveshare schematic) ---
// LCD QSPI
#define LCD_SPI_HOST    SPI2_HOST
#define LCD_PIN_SCK     GPIO_NUM_40
#define LCD_PIN_D0      GPIO_NUM_46
#define LCD_PIN_D1      GPIO_NUM_45
#define LCD_PIN_D2      GPIO_NUM_42
#define LCD_PIN_D3      GPIO_NUM_41
#define LCD_PIN_CS      GPIO_NUM_21
#define LCD_PIN_TE      GPIO_NUM_18
#define LCD_PIN_BL      GPIO_NUM_5

// I2C bus (shared: touch + IO expander)
#define I2C_PORT        I2C_NUM_0
#define I2C_PIN_SDA     GPIO_NUM_11
#define I2C_PIN_SCL     GPIO_NUM_10

// IO expander (TCA9554PWR) — controls LCD reset via EXIO0
#define TCA9554_ADDR    0x20
#define EXIO_LCD_RST    0  // EXIO pin 0 = LCD reset

// Display
#define LCD_H_RES       360
#define LCD_V_RES       360
#define LCD_CLK_HZ      (80 * 1000 * 1000)
#define LCD_CMD_BITS    32
#define LCD_PARAM_BITS  8

// Exported handles for ui_manager
esp_lcd_panel_handle_t g_panel_handle = NULL;
esp_lcd_touch_handle_t g_touch_handle = NULL;
i2c_master_bus_handle_t g_i2c_bus = NULL;

// --- IO expander (TCA9554) helpers ---
static void tca9554_write_reg(uint8_t reg, uint8_t val)
{
    i2c_master_dev_handle_t dev;
    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = TCA9554_ADDR,
        .scl_speed_hz = 400000,
    };
    ESP_ERROR_CHECK(i2c_master_bus_add_device(g_i2c_bus, &dev_cfg, &dev));
    uint8_t buf[2] = { reg, val };
    ESP_ERROR_CHECK(i2c_master_transmit(dev, buf, 2, 100));
    i2c_master_bus_rm_device(dev);
}

static void exio_init(void)
{
    // Register 3 = configuration: 0x00 = all outputs
    tca9554_write_reg(0x03, 0x00);
    // Register 1 = output: set all high initially
    tca9554_write_reg(0x01, 0xFF);
    ESP_LOGI(TAG, "IO expander (TCA9554) initialized");
}

static void exio_set_pin(uint8_t pin, bool level)
{
    static uint8_t output_state = 0xFF;
    if (level) {
        output_state |= (1 << pin);
    } else {
        output_state &= ~(1 << pin);
    }
    tca9554_write_reg(0x01, output_state);
}

static void lcd_reset_via_exio(void)
{
    exio_set_pin(EXIO_LCD_RST, false);
    vTaskDelay(pdMS_TO_TICKS(20));
    exio_set_pin(EXIO_LCD_RST, true);
    vTaskDelay(pdMS_TO_TICKS(120));
    ESP_LOGI(TAG, "LCD reset via EXIO complete");
}

// --- Backlight (LEDC PWM) ---
static void backlight_init(void)
{
    ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = LEDC_TIMER_13_BIT,
        .timer_num = LEDC_TIMER_0,
        .freq_hz = 5000,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ledc_timer_config(&timer);

    ledc_channel_config_t channel = {
        .gpio_num = LCD_PIN_BL,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = LEDC_CHANNEL_0,
        .timer_sel = LEDC_TIMER_0,
        .duty = 8191,  // 100% brightness
        .hpoint = 0,
    };
    ledc_channel_config(&channel);
    ESP_LOGI(TAG, "Backlight initialized (100%%)");
}

// --- LCD (ST77916 via QSPI) ---
static void lcd_init(void)
{
    // SPI bus (quad mode)
    spi_bus_config_t bus_cfg = {
        .data0_io_num = LCD_PIN_D0,
        .data1_io_num = LCD_PIN_D1,
        .data2_io_num = LCD_PIN_D2,
        .data3_io_num = LCD_PIN_D3,
        .sclk_io_num = LCD_PIN_SCK,
        .max_transfer_sz = LCD_H_RES * LCD_V_RES * 2,
        .flags = SPICOMMON_BUSFLAG_MASTER,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(LCD_SPI_HOST, &bus_cfg, SPI_DMA_CH_AUTO));

    // Panel IO (QSPI)
    esp_lcd_panel_io_handle_t io_handle = NULL;
    esp_lcd_panel_io_spi_config_t io_cfg = {
        .cs_gpio_num = LCD_PIN_CS,
        .dc_gpio_num = -1,  // not used in QSPI mode
        .spi_mode = 0,
        .pclk_hz = LCD_CLK_HZ,
        .trans_queue_depth = 10,
        .lcd_cmd_bits = LCD_CMD_BITS,
        .lcd_param_bits = LCD_PARAM_BITS,
        .flags = {
            .quad_mode = 1,
        },
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi(LCD_SPI_HOST, &io_cfg, &io_handle));

    // ST77916 panel
    esp_lcd_panel_dev_config_t panel_cfg = {
        .reset_gpio_num = -1,  // reset via IO expander, not GPIO
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = 16,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_st77916(io_handle, &panel_cfg, &g_panel_handle));

    // Reset via IO expander, then init
    lcd_reset_via_exio();
    ESP_ERROR_CHECK(esp_lcd_panel_init(g_panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(g_panel_handle, true));

    ESP_LOGI(TAG, "LCD (ST77916 360x360 QSPI) initialized");
}

// --- Touch (CST816S via I2C) ---
static void touch_init(void)
{
    esp_lcd_panel_io_handle_t tp_io = NULL;
    esp_lcd_panel_io_i2c_config_t tp_io_cfg =
        ESP_LCD_TOUCH_IO_I2C_CST816S_CONFIG();

    ESP_ERROR_CHECK(esp_lcd_new_panel_io_i2c(g_i2c_bus, &tp_io_cfg, &tp_io));

    esp_lcd_touch_config_t tp_cfg = {
        .x_max = LCD_H_RES,
        .y_max = LCD_V_RES,
        .rst_gpio_num = -1,  // reset via IO expander if needed
        .int_gpio_num = -1,  // no interrupt pin connected directly
    };
    ESP_ERROR_CHECK(esp_lcd_touch_new_i2c_cst816s(tp_io, &tp_cfg, &g_touch_handle));

    ESP_LOGI(TAG, "Touch (CST816S) initialized");
}

// --- LVGL port setup ---
static void board_lvgl_port_init(void)
{
    const lvgl_port_cfg_t port_cfg = ESP_LVGL_PORT_INIT_CONFIG();
    ESP_ERROR_CHECK(lvgl_port_init(&port_cfg));

    // Add display
    const lvgl_port_display_cfg_t disp_cfg = {
        .io_handle = NULL,  // already initialized
        .panel_handle = g_panel_handle,
        .buffer_size = LCD_H_RES * 40,
        .double_buffer = true,
        .hres = LCD_H_RES,
        .vres = LCD_V_RES,
        .rotation = {
            .swap_xy = false,
            .mirror_x = false,
            .mirror_y = false,
        },
        .flags = {
            .buff_spiram = true,
        },
    };
    lvgl_port_add_disp(&disp_cfg);

    // Add touch input
    const lvgl_port_touch_cfg_t touch_cfg = {
        .disp = lv_display_get_default(),
        .handle = g_touch_handle,
    };
    lvgl_port_add_touch(&touch_cfg);

    ESP_LOGI(TAG, "LVGL port initialized (display + touch)");
}

// --- Public API ---
void board_init(void)
{
    ESP_LOGI(TAG, "Initializing Waveshare ESP32-S3-Touch-LCD-1.85C...");

    // 1. I2C bus (shared: touch + IO expander)
    i2c_master_bus_config_t i2c_cfg = {
        .i2c_port = I2C_PORT,
        .sda_io_num = I2C_PIN_SDA,
        .scl_io_num = I2C_PIN_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    ESP_ERROR_CHECK(i2c_new_master_bus(&i2c_cfg, &g_i2c_bus));
    ESP_LOGI(TAG, "I2C bus initialized (SDA=%d, SCL=%d)", I2C_PIN_SDA, I2C_PIN_SCL);

    // 2. IO expander (needed for LCD reset)
    exio_init();

    // 3. Backlight
    backlight_init();

    // 4. LCD (ST77916 via QSPI)
    lcd_init();

    // 5. Touch (CST816S via I2C)
    touch_init();

    // 6. LVGL port (display + touch input)
    board_lvgl_port_init();

    ESP_LOGI(TAG, "Board initialization complete");
}
