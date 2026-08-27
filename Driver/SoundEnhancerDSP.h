/*
     File: SoundEnhancerDSP.h

     Copyright (C) 2026 SoundEnhancer.

     DSP primitives ported from the Swift reference implementation so the audio
     processing can run inside the HAL driver (coreaudiod) instead of the app.
     This avoids the macOS "microphone in use" indicator, which is triggered
     whenever a user-space process opens a CoreAudio input stream.
*/

#ifndef SoundEnhancerDSP_h
#define SoundEnhancerDSP_h

#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Biquad (RBJ audio EQ cookbook formulas)
// ---------------------------------------------------------------------------

typedef struct {
    float b0, b1, b2, a1, a2;
    float x1, x2, y1, y2;
} SE_Biquad;

void se_biquad_reset(SE_Biquad* b);
void se_biquad_lowShelf(SE_Biquad* b, double sampleRate, double frequency, double gainDb, double q);
void se_biquad_highShelf(SE_Biquad* b, double sampleRate, double frequency, double gainDb, double q);
void se_biquad_peaking(SE_Biquad* b, double sampleRate, double frequency, double gainDb, double q);
void se_biquad_highPass(SE_Biquad* b, double sampleRate, double frequency, double q);
void se_biquad_lowPass(SE_Biquad* b, double sampleRate, double frequency, double q);

static inline float se_biquad_process(SE_Biquad* b, float x)
{
    float y = b->b0 * x + b->b1 * b->x1 + b->b2 * b->x2 - b->a1 * b->y1 - b->a2 * b->y2;
    b->x2 = b->x1; b->x1 = x;
    b->y2 = b->y1; b->y1 = y;
    return y;
}

static inline float se_soft_clip(float x)
{
    const float threshold = 0.891f;
    float ax = x < 0.0f ? -x : x;
    if (ax <= threshold) return x;
    float sign = x < 0.0f ? -1.0f : 1.0f;
    float over = (ax - threshold) / (1.0f - threshold);
    float y = sign * (threshold + (1.0f - threshold) * tanhf(over));
    if (y > 1.0f) y = 1.0f;
    if (y < -1.0f) y = -1.0f;
    return y;
}

// ---------------------------------------------------------------------------
// Enhancer DSP (stereo width + Haas + shelves + mid dip)
// ---------------------------------------------------------------------------

typedef struct {
    double sampleRate;

    SE_Biquad lowShelfL, lowShelfR;
    SE_Biquad highShelfL, highShelfR;
    SE_Biquad midDipL, midDipR;
    SE_Biquad haasLPF;

    float* delayBuffer;
    int    delayLength;
    int    delayWrite;

    float widthGain;
    float bassGainDb;
    float trebleGainDb;
    float haasMix;
    float haasDelaySamples;
} SE_EnhancerDSP;

void se_enhancer_init(SE_EnhancerDSP* d, double sampleRate);
void se_enhancer_deinit(SE_EnhancerDSP* d);
void se_enhancer_setSampleRate(SE_EnhancerDSP* d, double sampleRate);
void se_enhancer_setParams(SE_EnhancerDSP* d, float width, float bassDb, float trebleDb, float spatialMix);
void se_enhancer_reset(SE_EnhancerDSP* d);
void se_enhancer_process(SE_EnhancerDSP* d, float* left, float* right, int frameCount);

// ---------------------------------------------------------------------------
// Crosstalk cancellation (XTC)
// ---------------------------------------------------------------------------

typedef struct {
    SE_Biquad bass;    // high-pass 200 Hz
    SE_Biquad shadow;  // low-shelf 2500 Hz, -6 dB
    SE_Biquad treble;  // high-shelf 10000 Hz, -18 dB
} SE_XTCChain;

typedef struct {
    double sampleRate;

    float  intensity;
    bool   enabled;
    double speakerSeparation;
    double listenerDistance;

    float  delaySamples;
    float  gain;

    SE_XTCChain leftChain;
    SE_XTCChain rightChain;

    float* leftDelay;
    float* rightDelay;
    int    delayLength;
    int    writeIndex;
} SE_XTCDSP;

void se_xtc_init(SE_XTCDSP* d, double sampleRate);
void se_xtc_deinit(SE_XTCDSP* d);
void se_xtc_setSampleRate(SE_XTCDSP* d, double sampleRate);
void se_xtc_setEnabled(SE_XTCDSP* d, bool enabled);
void se_xtc_setIntensity(SE_XTCDSP* d, float intensity);
void se_xtc_setGeometry(SE_XTCDSP* d, double separation, double distance);
void se_xtc_reset(SE_XTCDSP* d);
void se_xtc_process(SE_XTCDSP* d, float* left, float* right, int frameCount);

#ifdef __cplusplus
}
#endif

#endif // SoundEnhancerDSP_h
