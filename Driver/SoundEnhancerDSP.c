/*
     File: SoundEnhancerDSP.c

     Copyright (C) 2026 SoundEnhancer.

     C port of the Swift DSP reference implementation. See SoundEnhancerDSP.h.
*/

#include "SoundEnhancerDSP.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define SE_CLAMP(x, lo, hi) ((x) < (lo) ? (lo) : ((x) > (hi) ? (hi) : (x)))

// ---------------------------------------------------------------------------
// Biquad
// ---------------------------------------------------------------------------

void se_biquad_reset(SE_Biquad* b)
{
    b->x1 = 0.0f; b->x2 = 0.0f;
    b->y1 = 0.0f; b->y2 = 0.0f;
}

void se_biquad_lowShelf(SE_Biquad* b, double sampleRate, double frequency, double gainDb, double q)
{
    double A = pow(10.0, gainDb / 40.0);
    double w0 = 2.0 * M_PI * frequency / sampleRate;
    double cosw = cos(w0);
    double alpha = sin(w0) / (2.0 * q);
    double sqrtA = sqrt(A);
    double a0 = (A + 1) + (A - 1) * cosw + 2 * sqrtA * alpha;

    b->b0 = (float)(A * ((A + 1) - (A - 1) * cosw + 2 * sqrtA * alpha) / a0);
    b->b1 = (float)(2 * A * ((A - 1) - (A + 1) * cosw) / a0);
    b->b2 = (float)(A * ((A + 1) - (A - 1) * cosw - 2 * sqrtA * alpha) / a0);
    b->a1 = (float)(-2 * ((A - 1) + (A + 1) * cosw) / a0);
    b->a2 = (float)(((A + 1) + (A - 1) * cosw - 2 * sqrtA * alpha) / a0);
}

void se_biquad_highShelf(SE_Biquad* b, double sampleRate, double frequency, double gainDb, double q)
{
    double A = pow(10.0, gainDb / 40.0);
    double w0 = 2.0 * M_PI * frequency / sampleRate;
    double cosw = cos(w0);
    double alpha = sin(w0) / (2.0 * q);
    double sqrtA = sqrt(A);
    double a0 = (A + 1) - (A - 1) * cosw + 2 * sqrtA * alpha;

    b->b0 = (float)(A * ((A + 1) + (A - 1) * cosw + 2 * sqrtA * alpha) / a0);
    b->b1 = (float)(-2 * A * ((A - 1) + (A + 1) * cosw) / a0);
    b->b2 = (float)(A * ((A + 1) + (A - 1) * cosw - 2 * sqrtA * alpha) / a0);
    b->a1 = (float)(2 * ((A - 1) - (A + 1) * cosw) / a0);
    b->a2 = (float)(((A + 1) - (A - 1) * cosw - 2 * sqrtA * alpha) / a0);
}

void se_biquad_peaking(SE_Biquad* b, double sampleRate, double frequency, double gainDb, double q)
{
    double A = pow(10.0, gainDb / 40.0);
    double w0 = 2.0 * M_PI * frequency / sampleRate;
    double cosw = cos(w0);
    double alpha = sin(w0) / (2.0 * q);
    double a0 = 1 + alpha / A;

    b->b0 = (float)((1 + alpha * A) / a0);
    b->b1 = (float)((-2 * cosw) / a0);
    b->b2 = (float)((1 - alpha * A) / a0);
    b->a1 = (float)((-2 * cosw) / a0);
    b->a2 = (float)((1 - alpha / A) / a0);
}

void se_biquad_highPass(SE_Biquad* b, double sampleRate, double frequency, double q)
{
    double w0 = 2.0 * M_PI * frequency / sampleRate;
    double cosw = cos(w0);
    double alpha = sin(w0) / (2.0 * q);
    double a0 = 1 + alpha;
    double k = (1 + cosw) / 2;

    b->b0 = (float)(k / a0);
    b->b1 = (float)(-2 * k / a0);
    b->b2 = (float)(k / a0);
    b->a1 = (float)(-2 * cosw / a0);
    b->a2 = (float)((1 - alpha) / a0);
}

void se_biquad_lowPass(SE_Biquad* b, double sampleRate, double frequency, double q)
{
    double w0 = 2.0 * M_PI * frequency / sampleRate;
    double cosw = cos(w0);
    double alpha = sin(w0) / (2.0 * q);
    double a0 = 1 + alpha;
    double k = (1 - cosw) / 2;

    b->b0 = (float)(k / a0);
    b->b1 = (float)(2 * k / a0);
    b->b2 = (float)(k / a0);
    b->a1 = (float)(-2 * cosw / a0);
    b->a2 = (float)((1 - alpha) / a0);
}

// ---------------------------------------------------------------------------
// Enhancer DSP
// ---------------------------------------------------------------------------

#define SE_MIN_DELAY_SECONDS 0.003
#define SE_MAX_DELAY_SECONDS 0.012
#define SE_HAAS_LOWPASS_HZ   4000.0

static void enhancer_allocate_delay(SE_EnhancerDSP* d)
{
    int maxSamples = (int)ceil(SE_MAX_DELAY_SECONDS * d->sampleRate) + 4;
    if (d->delayBuffer != NULL) { free(d->delayBuffer); d->delayBuffer = NULL; }
    d->delayLength = maxSamples;
    d->delayBuffer = (float*)calloc((size_t)d->delayLength, sizeof(float));
    d->delayWrite = 0;
}

static void enhancer_recompute_filters(SE_EnhancerDSP* d)
{
    double bass = (double)d->bassGainDb;
    double treble = (double)d->trebleGainDb;
    double enhance = SE_CLAMP((bass / 10.0 + treble / 10.0 + d->haasMix / 0.35) / 3.0, 0.0, 1.0);
    double midGain = -2.0 * enhance;

    se_biquad_lowShelf(&d->lowShelfL, d->sampleRate, 80.0, bass, 0.707);
    d->lowShelfR = d->lowShelfL;
    se_biquad_highShelf(&d->highShelfL, d->sampleRate, 9000.0, treble, 0.707);
    d->highShelfR = d->highShelfL;
    se_biquad_peaking(&d->midDipL, d->sampleRate, 1000.0, midGain, 0.9);
    d->midDipR = d->midDipL;

    se_biquad_lowPass(&d->haasLPF, d->sampleRate, SE_HAAS_LOWPASS_HZ, 0.707);
}

void se_enhancer_init(SE_EnhancerDSP* d, double sampleRate)
{
    memset(d, 0, sizeof(*d));
    d->sampleRate = sampleRate;
    enhancer_allocate_delay(d);
    se_enhancer_setParams(d, 1.0f, 0.0f, 0.0f, 0.0f);
}

void se_enhancer_deinit(SE_EnhancerDSP* d)
{
    if (d->delayBuffer != NULL) { free(d->delayBuffer); d->delayBuffer = NULL; }
    d->delayLength = 0;
    d->delayWrite = 0;
}

void se_enhancer_setSampleRate(SE_EnhancerDSP* d, double sampleRate)
{
    if (sampleRate <= 0.0 || sampleRate == d->sampleRate) return;
    d->sampleRate = sampleRate;
    enhancer_allocate_delay(d);
    enhancer_recompute_filters(d);
}

void se_enhancer_setParams(SE_EnhancerDSP* d, float width, float bassDb, float trebleDb, float spatialMix)
{
    d->widthGain = SE_CLAMP(width, 1.0f, 3.0f);
    d->bassGainDb = SE_CLAMP(bassDb, 0.0f, 10.0f);
    d->trebleGainDb = SE_CLAMP(trebleDb, 0.0f, 10.0f);
    d->haasMix = SE_CLAMP(spatialMix, 0.0f, 0.35f);

    double normalized = (double)d->haasMix / 0.35;
    double delaySeconds = SE_MIN_DELAY_SECONDS + (SE_MAX_DELAY_SECONDS - SE_MIN_DELAY_SECONDS) * normalized;
    d->haasDelaySamples = (float)(delaySeconds * d->sampleRate);

    enhancer_recompute_filters(d);
}

void se_enhancer_reset(SE_EnhancerDSP* d)
{
    se_biquad_reset(&d->lowShelfL);  se_biquad_reset(&d->lowShelfR);
    se_biquad_reset(&d->highShelfL); se_biquad_reset(&d->highShelfR);
    se_biquad_reset(&d->midDipL);    se_biquad_reset(&d->midDipR);
    se_biquad_reset(&d->haasLPF);
    if (d->delayBuffer != NULL) memset(d->delayBuffer, 0, (size_t)d->delayLength * sizeof(float));
    d->delayWrite = 0;
}

void se_enhancer_process(SE_EnhancerDSP* d, float* left, float* right, int frameCount)
{
    if (frameCount <= 0) return;

    for (int i = 0; i < frameCount; i++)
    {
        float l = left[i];
        float r = right[i];

        float mid = 0.5f * (l + r);
        float side = 0.5f * (l - r) * d->widthGain;

        float delayed = 0.0f;
        if (d->haasMix > 0.0f)
        {
            float readPos = (float)d->delayWrite - d->haasDelaySamples;
            int base = (int)floorf(readPos);
            float frac = readPos - (float)base;
            int i0 = ((base % d->delayLength) + d->delayLength) % d->delayLength;
            int i1 = (i0 + 1) % d->delayLength;
            delayed = d->delayBuffer[i0] * (1.0f - frac) + d->delayBuffer[i1] * frac;
            delayed = se_biquad_process(&d->haasLPF, delayed);
        }

        d->delayBuffer[d->delayWrite] = side;
        d->delayWrite += 1;
        if (d->delayWrite >= d->delayLength) d->delayWrite = 0;

        side += d->haasMix * delayed;

        float outL = mid + side;
        float outR = mid - side;

        outL = se_biquad_process(&d->lowShelfL, outL);
        outL = se_biquad_process(&d->highShelfL, outL);
        outL = se_biquad_process(&d->midDipL, outL);

        outR = se_biquad_process(&d->lowShelfR, outR);
        outR = se_biquad_process(&d->highShelfR, outR);
        outR = se_biquad_process(&d->midDipR, outR);

        left[i] = se_soft_clip(outL);
        right[i] = se_soft_clip(outR);
    }
}

// ---------------------------------------------------------------------------
// Crosstalk cancellation (XTC)
// ---------------------------------------------------------------------------

#define SE_XTC_SPEED_OF_SOUND 343.0
#define SE_XTC_EAR_SEPARATION 0.175
#define SE_XTC_MIN_DELAY      4
#define SE_XTC_MAX_DELAY      2048

static void xtc_chain_configure(SE_XTCChain* c, double sampleRate)
{
    se_biquad_highPass(&c->bass, sampleRate, 200.0, 0.707);
    se_biquad_lowShelf(&c->shadow, sampleRate, 2500.0, -6.0, 0.707);
    se_biquad_highShelf(&c->treble, sampleRate, 10000.0, -18.0, 0.707);
}

static void xtc_chain_reset(SE_XTCChain* c)
{
    se_biquad_reset(&c->bass);
    se_biquad_reset(&c->shadow);
    se_biquad_reset(&c->treble);
}

static float xtc_chain_process(SE_XTCChain* c, float x)
{
    float y = se_biquad_process(&c->bass, x);
    y = se_biquad_process(&c->shadow, y);
    y = se_biquad_process(&c->treble, y);
    return y;
}

static void xtc_allocate_delay(SE_XTCDSP* d)
{
    d->delayLength = SE_XTC_MAX_DELAY + 8;
    if (d->leftDelay != NULL)  { free(d->leftDelay);  d->leftDelay  = NULL; }
    if (d->rightDelay != NULL) { free(d->rightDelay); d->rightDelay = NULL; }
    d->leftDelay  = (float*)calloc((size_t)d->delayLength, sizeof(float));
    d->rightDelay = (float*)calloc((size_t)d->delayLength, sizeof(float));
    d->writeIndex = 0;
}

static void xtc_recompute_geometry(SE_XTCDSP* d)
{
    double s = d->speakerSeparation;
    double dist = d->listenerDistance;
    double a = SE_XTC_EAR_SEPARATION;

    double ri = sqrt(dist * dist + pow((s - a) * 0.5, 2));
    double rc = sqrt(dist * dist + pow((s + a) * 0.5, 2));

    double deltaT = (rc - ri) / SE_XTC_SPEED_OF_SOUND;
    float dn = (float)(deltaT * d->sampleRate);
    if (dn < SE_XTC_MIN_DELAY) dn = SE_XTC_MIN_DELAY;
    if (dn > SE_XTC_MAX_DELAY) dn = SE_XTC_MAX_DELAY;
    d->delaySamples = dn;

    d->gain = (float)(ri / rc) * d->intensity;
}

static float xtc_read_delay(const float* buffer, int delayLength, int writeIndex, float delay)
{
    float pos = (float)writeIndex - delay;
    int ipRaw = (int)floorf(pos);
    float frac = pos - (float)ipRaw;
    int ip = ((ipRaw % delayLength) + delayLength) % delayLength;

    int i0 = (ip - 1 + delayLength) % delayLength;
    int i1 = ip;
    int i2 = (ip + 1) % delayLength;
    int i3 = (ip + 2) % delayLength;

    float x0 = buffer[i0];
    float x1 = buffer[i1];
    float x2 = buffer[i2];
    float x3 = buffer[i3];

    float c3 = 0.5f * (-x0 + 3 * x1 - 3 * x2 + x3);
    float c2 = 0.5f * (2 * x0 - 5 * x1 + 4 * x2 - x3);
    float c1 = 0.5f * (x2 - x0);
    return ((c3 * frac + c2) * frac + c1) * frac + x1;
}

void se_xtc_init(SE_XTCDSP* d, double sampleRate)
{
    memset(d, 0, sizeof(*d));
    d->sampleRate = sampleRate;
    d->speakerSeparation = 0.24;
    d->listenerDistance = 0.50;
    xtc_allocate_delay(d);
    xtc_chain_configure(&d->leftChain, sampleRate);
    xtc_chain_configure(&d->rightChain, sampleRate);
    xtc_recompute_geometry(d);
}

void se_xtc_deinit(SE_XTCDSP* d)
{
    if (d->leftDelay != NULL)  { free(d->leftDelay);  d->leftDelay  = NULL; }
    if (d->rightDelay != NULL) { free(d->rightDelay); d->rightDelay = NULL; }
    d->delayLength = 0;
    d->writeIndex = 0;
}

void se_xtc_setSampleRate(SE_XTCDSP* d, double sampleRate)
{
    if (sampleRate <= 0.0 || sampleRate == d->sampleRate) return;
    d->sampleRate = sampleRate;
    xtc_allocate_delay(d);
    xtc_chain_configure(&d->leftChain, sampleRate);
    xtc_chain_configure(&d->rightChain, sampleRate);
    xtc_recompute_geometry(d);
}

void se_xtc_setEnabled(SE_XTCDSP* d, bool enabled)
{
    if (d->enabled == enabled) return;
    d->enabled = enabled;
    se_xtc_reset(d);
}

void se_xtc_setIntensity(SE_XTCDSP* d, float intensity)
{
    d->intensity = SE_CLAMP(intensity, 0.0f, 1.0f);
    xtc_recompute_geometry(d);
}

void se_xtc_setGeometry(SE_XTCDSP* d, double separation, double distance)
{
    d->speakerSeparation = SE_CLAMP(separation, 0.05, 5.0);
    d->listenerDistance = SE_CLAMP(distance, 0.05, 5.0);
    xtc_recompute_geometry(d);
}

void se_xtc_reset(SE_XTCDSP* d)
{
    xtc_chain_reset(&d->leftChain);
    xtc_chain_reset(&d->rightChain);
    if (d->leftDelay != NULL)  memset(d->leftDelay,  0, (size_t)d->delayLength * sizeof(float));
    if (d->rightDelay != NULL) memset(d->rightDelay, 0, (size_t)d->delayLength * sizeof(float));
    d->writeIndex = 0;
}

void se_xtc_process(SE_XTCDSP* d, float* left, float* right, int frameCount)
{
    if (frameCount <= 0) return;

    if (!d->enabled || d->intensity <= 0.0f)
    {
        for (int i = 0; i < frameCount; i++)
        {
            d->leftDelay[d->writeIndex] = left[i];
            d->rightDelay[d->writeIndex] = right[i];
            d->writeIndex += 1;
            if (d->writeIndex >= d->delayLength) d->writeIndex = 0;
        }
        return;
    }

    for (int i = 0; i < frameCount; i++)
    {
        float l = left[i];
        float r = right[i];

        float rPast = xtc_read_delay(d->rightDelay, d->delayLength, d->writeIndex, d->delaySamples);
        float lPast = xtc_read_delay(d->leftDelay, d->delayLength, d->writeIndex, d->delaySamples);

        float lCancel = d->gain * xtc_chain_process(&d->leftChain, rPast);
        float rCancel = d->gain * xtc_chain_process(&d->rightChain, lPast);

        float outL = se_soft_clip(l - lCancel);
        float outR = se_soft_clip(r - rCancel);

        d->leftDelay[d->writeIndex] = outL;
        d->rightDelay[d->writeIndex] = outR;
        d->writeIndex += 1;
        if (d->writeIndex >= d->delayLength) d->writeIndex = 0;

        left[i] = outL;
        right[i] = outR;
    }
}
