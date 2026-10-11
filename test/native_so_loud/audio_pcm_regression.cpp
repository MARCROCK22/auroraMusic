#define NOMINMAX
#include "soloud.h"
#include "soloud_eqfilter.h"
#include "soloud_wav.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {
constexpr unsigned int kRate = 48000;
constexpr unsigned int kChannels = 1;
constexpr unsigned int kFrames = 8192;
constexpr unsigned int kWarmupFrames = 1024;
constexpr float kPi = 3.14159265358979323846f;
constexpr float kEqHeadroom = 0.9f;

struct Result {
  std::vector<float> samples;
  float peak = 0;
  unsigned int clipped = 0;
  bool finite = true;
};

std::vector<float> makeSignal(bool multitone, float amplitudeScale = 1) {
  std::vector<float> samples(kFrames);
  for (unsigned int frame = 0; frame < kFrames; ++frame) {
    const float t = static_cast<float>(frame) / kRate;
    float sample = multitone
        ? 0.48f * std::sin(2 * kPi * 1500 * t) +
              0.46f * std::sin(2 * kPi * 2200 * t)
        : 0.98f * std::sin(2 * kPi * 440 * t);
    samples[frame] = amplitudeScale * sample;
  }
  return samples;
}

Result render(const std::vector<float>& input, unsigned int flags,
              const std::vector<float>& eqGains = {}, float volume = 1) {
  SoLoud::Soloud engine;
  if (engine.init(flags, SoLoud::Soloud::NULLDRIVER, kRate, 1024,
                  kChannels) != SoLoud::SO_NO_ERROR) {
    std::fprintf(stderr, "SoLoud NULLDRIVER initialization failed\n");
    std::exit(2);
  }

  SoLoud::Wav source;
  if (source.loadRawWave(const_cast<float*>(input.data()), input.size(), kRate,
                         kChannels, true) != SoLoud::SO_NO_ERROR) {
    std::fprintf(stderr, "SoLoud PCM source load failed\n");
    std::exit(2);
  }
  SoLoud::EqFilter eq;
  if (!eqGains.empty()) {
    source.setFilter(0, &eq);
    for (unsigned int band = 0; band < eqGains.size(); ++band) {
      if (eq.setParam(band + 1, eqGains[band]) != SoLoud::SO_NO_ERROR) {
        std::fprintf(stderr, "SoLoud EQ parameter rejected\n");
        std::exit(2);
      }
    }
  }
  engine.play(source, volume);
  Result result;
  result.samples.resize(input.size());
  engine.mix(result.samples.data(), kFrames);
  engine.deinit();

  for (std::size_t i = 0; i < result.samples.size(); ++i) {
    const float actual = result.samples[i];
    result.finite = result.finite && std::isfinite(actual);
    result.peak = std::max(result.peak, std::abs(actual));
    result.clipped += std::abs(actual) >= 0.9499f;
  }
  return result;
}

float scaledRmsError(const std::vector<float>& actual,
                     const std::vector<float>& reference,
                     float referenceScale) {
  double error = 0;
  unsigned int count = 0;
  for (unsigned int i = kWarmupFrames; i < actual.size(); ++i) {
    const double delta = actual[i] - reference[i] * referenceScale;
    error += delta * delta;
    ++count;
  }
  return static_cast<float>(std::sqrt(error / count));
}

Result renderEqTransition(const std::vector<float>& input, bool lowerFirst) {
  SoLoud::Soloud engine;
  if (engine.init(0, SoLoud::Soloud::NULLDRIVER, kRate, 1024, kChannels) !=
      SoLoud::SO_NO_ERROR) {
    std::fprintf(stderr, "SoLoud NULLDRIVER initialization failed\n");
    std::exit(2);
  }
  SoLoud::Wav source;
  source.loadRawWave(const_cast<float*>(input.data()), input.size(), kRate,
                     kChannels, true);
  SoLoud::EqFilter eq;
  source.setFilter(0, &eq);
  const auto handle = engine.play(source, 1);
  Result result;
  result.samples.resize(input.size());
  unsigned int rendered = 0;
  if (lowerFirst) engine.setVolume(handle, kEqHeadroom / 4);
  for (unsigned int band = 1; band <= 8; ++band) {
    engine.setFilterParameter(handle, 0, band, 4.0f);
    engine.mix(result.samples.data() + rendered, 256);
    rendered += 256;
  }
  engine.setVolume(handle, kEqHeadroom / 4);
  engine.mix(result.samples.data() + rendered, kFrames - rendered);
  engine.deinit();

  for (float sample : result.samples) {
    result.finite = result.finite && std::isfinite(sample);
    result.peak = std::max(result.peak, std::abs(sample));
    result.clipped += std::abs(sample) >= 0.9499f;
  }
  return result;
}

void require(bool condition, const char* message) {
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}
}  // namespace

int main() {
  const auto sine = makeSignal(false);
  const auto quietSine = makeSignal(false, 0.1f);
  const auto oldClipper = render(sine, SoLoud::Soloud::CLIP_ROUNDOFF);
  const auto linearOutput = render(sine, 0);
  const auto quietReference = render(quietSine, 0);
  const float oldClipperError = scaledRmsError(
      oldClipper.samples, quietReference.samples, 10.0f);
  const float linearError = scaledRmsError(
      linearOutput.samples, quietReference.samples, 10.0f);
  std::printf("440 Hz sine: old roundoff RMS error %.6f; flag-free RMS error %.6f vs 10x quiet render, peak %.6f\n",
              oldClipperError, linearError, linearOutput.peak);
  require(oldClipperError > 0.05f,
          "legacy roundoff clipper should measurably alter a loud sine");
  require(linearError < 0.005f,
          "flag-free mixer should preserve in-range flat PCM");
  require(linearOutput.finite && linearOutput.peak < 1,
          "flat PCM output must remain finite and unclipped");

  const auto multitone = makeSignal(true);
  const std::vector<float> boosted = {1, 4, 4, 1, 1, 1, 1, 1};
  const auto boostedOutput = render(multitone, 0, boosted, kEqHeadroom / 4);
  std::printf("+12 dB adjacent EQ bands with max-band preamp: peak %.6f, clipped %u, finite %s\n",
              boostedOutput.peak, boostedOutput.clipped,
              boostedOutput.finite ? "yes" : "no");
  require(boostedOutput.finite, "EQ output must not contain non-finite samples");
  require(boostedOutput.clipped == 0,
          "max-band EQ preamp should leave this representative multitone below clipping");

  const auto unsafeTransition = renderEqTransition(sine, false);
  const auto safeTransition = renderEqTransition(sine, true);
  std::printf("EQ gain transition: volume-after-bands peak %.6f/clipped %u; volume-before-bands peak %.6f/clipped %u\n",
              unsafeTransition.peak, unsafeTransition.clipped,
              safeTransition.peak, safeTransition.clipped);
  require(unsafeTransition.clipped > 0,
          "loud positive EQ transition should expose late preamp application");
  require(safeTransition.clipped == 0,
          "lowering volume before EQ updates should prevent transition clipping");
  return 0;
}
