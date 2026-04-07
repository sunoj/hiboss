// audio_manager: Notification sounds for hiboss terminal.
// Exports: audio_init(), audio_play_notification().
// Deps: ESP-IDF driver (I2S), ES8311 codec.

#pragma once

// Initialize audio codec (ES8311) and I2S.
void audio_init(void);

// Play a short notification beep when new message arrives.
void audio_play_notification(void);
