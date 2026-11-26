/*
 * Copyright (C) 2026 AERA Recovery Project contributors
 * SPDX-License-Identifier: Apache-2.0
 *
 * Narrow plugin-to-tinyalsa PCM bridge for Motorola bangkk (holi/SM6375)
 * recovery. Untrusted plugins never receive access to ALSA, the installed
 * ROM, or this process. Only the dedicated browser, media and doom UIDs may
 * connect and send fixed-format PCM over one abstract local socket.
 *
 * The installed ROM supplies libtinyalsa and the aw87xxx codec driver. The
 * recovery bind-mounts libtinyalsa.so into /vendor/lib64 and loads the ROM's
 * matching kernel modules before this bridge starts.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cstddef>

namespace {
constexpr uid_t kBrowserUid = 99090;
constexpr uid_t kMediaUid = 99092;
constexpr uid_t kDoomUid = 99094;
constexpr uint32_t kMagic = 0x41525041U;
constexpr uint32_t kRate = 48000U;
constexpr uint32_t kChannels = 2U;
constexpr uint32_t kBits = 16U;
constexpr int kDefaultVolumePercent = 100;
constexpr char kSocketName[] = "aera-browser-audio-v1";
constexpr char kVolumePath[] = "/tmp/aera-audio-volume";
constexpr int kPcmFormatS16Le = 0;
constexpr unsigned int kPeriodSize = 1024;
constexpr unsigned int kPeriodCount = 8;
constexpr int kSocketBufferBytes = 4 * 1024 * 1024;
constexpr size_t kJitterBytes = 1U << 20;
constexpr size_t kStartupBufferedBytes = 16U * 1024U;
constexpr size_t kMaxBufferedBytes = 64U * 1024U;
constexpr size_t kWriteBytes = kPeriodSize * kChannels * kBits / 8U;
constexpr size_t kPrefillBytes = kWriteBytes * 2U;
constexpr size_t kCatchUpBytes = kWriteBytes * 3U;
constexpr long kPeriodNanos = 1000000000L * kPeriodSize / kRate;
volatile sig_atomic_t g_stop = 0;

void Stop(int) { g_stop = 1; }

bool ReadAll(int fd, void* data, size_t size) {
  auto* bytes = static_cast<uint8_t*>(data);
  size_t done = 0;
  while (done < size && !g_stop) {
    const ssize_t count = read(fd, bytes + done, size - done);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    done += static_cast<size_t>(count);
  }
  return done == size;
}

int ReadVolumePercent() {
  const int fd = open(kVolumePath, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return kDefaultVolumePercent;
  char value[8] = {};
  const ssize_t count = read(fd, value, sizeof(value) - 1);
  close(fd);
  if (count <= 0) return kDefaultVolumePercent;
  return std::clamp(atoi(value), 0, 100);
}

void ScaleS16(uint8_t* data, size_t size, int from_volume, int to_volume) {
  const size_t frames = size / (kChannels * sizeof(int16_t));
  size_t offset = 0;
  for (size_t frame = 0; frame < frames && offset + 1 < size;
       ++frame, offset += kChannels * sizeof(int16_t)) {
    const int volume = frames ? from_volume +
        ((to_volume - from_volume) * static_cast<int>(frame)) /
            static_cast<int>(frames)
        : to_volume;
    const int32_t gain = static_cast<int32_t>(volume) * volume;
    for (unsigned int channel = 0; channel < kChannels; ++channel) {
      const size_t at = offset + channel * sizeof(int16_t);
      const int16_t sample = static_cast<int16_t>(
          static_cast<uint16_t>(data[at]) |
          (static_cast<uint16_t>(data[at + 1]) << 8));
      const int32_t scaled =
          (static_cast<int32_t>(sample) * gain) / 10000;
      const int16_t clamped =
          static_cast<int16_t>(std::clamp<int32_t>(scaled, -32768, 32767));
      data[at] = static_cast<uint8_t>(clamped);
      data[at + 1] = static_cast<uint8_t>(
          static_cast<uint16_t>(clamped) >> 8);
    }
  }
}

struct Mixer;
struct MixerCtl;
struct Pcm;

struct PcmConfig {
  unsigned int channels;
  unsigned int rate;
  unsigned int period_size;
  unsigned int period_count;
  int format;
  unsigned int start_threshold;
  unsigned int stop_threshold;
  unsigned int silence_threshold;
  unsigned int silence_size;
  int avail_min;
};

struct AudioApi {
  using MixerOpen = Mixer* (*)(unsigned int);
  using MixerClose = void (*)(Mixer*);
  using MixerGetCtlByName = MixerCtl* (*)(Mixer*, const char*);
  using MixerCtlGetNumValues = unsigned int (*)(MixerCtl*);
  using MixerCtlSetValue = int (*)(MixerCtl*, unsigned int, int);
  using MixerCtlSetEnumByString = int (*)(MixerCtl*, const char*);
  using PcmOpen = Pcm* (*)(unsigned int, unsigned int, unsigned int,
                           PcmConfig*);
  using PcmClose = void (*)(Pcm*);
  using PcmIsReady = int (*)(Pcm*);
  using PcmGetError = const char* (*)(Pcm*);
  using PcmPrepare = int (*)(Pcm*);
  using PcmWrite = int (*)(Pcm*, const void*, unsigned int);

  void* library = nullptr;
  MixerOpen mixer_open = nullptr;
  MixerClose mixer_close = nullptr;
  MixerGetCtlByName mixer_get_ctl_by_name = nullptr;
  MixerCtlGetNumValues mixer_ctl_get_num_values = nullptr;
  MixerCtlSetValue mixer_ctl_set_value = nullptr;
  MixerCtlSetEnumByString mixer_ctl_set_enum_by_string = nullptr;
  PcmOpen pcm_open = nullptr;
  PcmClose pcm_close = nullptr;
  PcmIsReady pcm_is_ready = nullptr;
  PcmGetError pcm_get_error = nullptr;
  PcmPrepare pcm_prepare = nullptr;
  PcmWrite pcm_write = nullptr;

  ~AudioApi() {
    if (library) dlclose(library);
  }

  template <typename T>
  bool LoadSymbol(const char* name, T* target) {
    *target = reinterpret_cast<T>(dlsym(library, name));
    if (*target) return true;
    fprintf(stderr, "AERA audio: missing libtinyalsa symbol %s: %s\n", name,
            dlerror());
    return false;
  }

  bool Load() {
    for (int attempt = 0; attempt < 100 && !g_stop; ++attempt) {
      library = dlopen("libtinyalsa.so", RTLD_NOW | RTLD_LOCAL);
      if (library) break;
      if (attempt == 0) {
        fprintf(stderr, "AERA audio: waiting for stock libtinyalsa: %s\n",
                dlerror());
      }
      usleep(100000);
    }
    if (!library) {
      fprintf(stderr,
              "AERA audio: stock libtinyalsa unavailable; serving silence\n");
      return false;
    }

    const bool loaded =
        LoadSymbol("mixer_open", &mixer_open) &&
        LoadSymbol("mixer_close", &mixer_close) &&
        LoadSymbol("mixer_get_ctl_by_name", &mixer_get_ctl_by_name) &&
        LoadSymbol("mixer_ctl_get_num_values", &mixer_ctl_get_num_values) &&
        LoadSymbol("mixer_ctl_set_value", &mixer_ctl_set_value) &&
        LoadSymbol("mixer_ctl_set_enum_by_string",
                   &mixer_ctl_set_enum_by_string) &&
        LoadSymbol("pcm_open", &pcm_open) &&
        LoadSymbol("pcm_close", &pcm_close) &&
        LoadSymbol("pcm_is_ready", &pcm_is_ready) &&
        LoadSymbol("pcm_get_error", &pcm_get_error) &&
        LoadSymbol("pcm_prepare", &pcm_prepare) &&
        LoadSymbol("pcm_write", &pcm_write);
    if (!loaded) {
      dlclose(library);
      library = nullptr;
      return false;
    }
    return true;
  }
};

struct MixerCtlSpec {
  const char* name;
  const char* enum_value;
  int int_value;
  bool is_enum;
};

constexpr MixerCtlSpec kPlaybackPath[] = {
    {"RX_CDC_DMA_RX_0 Audio Mixer MultiMedia1", nullptr, 1, false},
};

constexpr MixerCtlSpec kSpeakerPath[] = {
    {"RX_CDC_DMA_RX_0 Channels", "Two", 0, true},
    {"RX_MACRO RX0 MUX", "AIF1_PB", 0, true},
    {"RX_MACRO RX1 MUX", "AIF1_PB", 0, true},
    {"RX INT0_1 MIX1 INP0", "RX0", 0, true},
    {"EAR_RDAC Switch", nullptr, 1, false},
    {"RDAC3_MUX", "RX1", 0, true},
    {"RX INT0 DEM MUX", "CLSH_DSM_OUT", 0, true},
    {"RX_EAR Mode", "ON", 0, true},
    {"aw87xxx_profile_switch_0", "Music", 0, true},
    {"RX INT2_1 MIX1 INP0", "RX1", 0, true},
    {"AUX_RDAC Switch", nullptr, 1, false},
    {"RX HPH Mode", "CLS_AB", 0, true},
    {"aw87xxx_profile_switch_1", "Music", 0, true},
    {"RX_RX2 Digital Volume", nullptr, 80, false},
    {"RX_RX0 Digital Volume", nullptr, 79, false},
    {"RX_COMP1 Switch", nullptr, 1, false},
    {"HPHL_COMP Switch", nullptr, 1, false},
    {"AUX PATH Mode", "HP_MODE", 0, true},
};

constexpr MixerCtlSpec kDisablePath[] = {
    {"aw87xxx_profile_switch_0", "Off", 0, true},
    {"aw87xxx_profile_switch_1", "Off", 0, true},
    {"RX_EAR Mode", "OFF", 0, true},
    {"EAR_RDAC Switch", nullptr, 0, false},
    {"AUX_RDAC Switch", nullptr, 0, false},
    {"RX INT0_1 MIX1 INP0", "ZERO", 0, true},
    {"RX INT2_1 MIX1 INP0", "ZERO", 0, true},
    {"RX INT0 DEM MUX", "NORMAL_DSM_OUT", 0, true},
    {"RDAC3_MUX", "ZERO", 0, true},
    {"RX_COMP1 Switch", nullptr, 0, false},
    {"HPHL_COMP Switch", nullptr, 0, false},
    {"RX_CDC_DMA_RX_0 Audio Mixer MultiMedia1", nullptr, 0, false},
};

bool SetMixerValue(AudioApi& api, Mixer* mixer, const char* name, int value,
                   bool log_failure) {
  MixerCtl* control = api.mixer_get_ctl_by_name(mixer, name);
  if (!control) {
    if (log_failure) {
      fprintf(stderr, "AERA audio: missing mixer control %s\n", name);
    }
    return false;
  }
  const unsigned int count = api.mixer_ctl_get_num_values(control);
  for (unsigned int index = 0; index < (count ? count : 1); ++index) {
    if (api.mixer_ctl_set_value(control, index, value) != 0) {
      if (log_failure) {
        fprintf(stderr, "AERA audio: could not set mixer control %s=%d\n",
                name, value);
      }
      return false;
    }
  }
  return true;
}

bool SetMixerEnum(AudioApi& api, Mixer* mixer, const char* name,
                  const char* value, bool log_failure) {
  MixerCtl* control = api.mixer_get_ctl_by_name(mixer, name);
  if (control && api.mixer_ctl_set_enum_by_string(control, value) == 0) {
    return true;
  }
  if (log_failure) {
    fprintf(stderr, "AERA audio: could not set mixer control %s=%s\n", name,
            value);
  }
  return false;
}

bool ApplyPath(AudioApi& api, Mixer* mixer, const MixerCtlSpec* specs,
               size_t count, bool log_failure) {
  bool ok = true;
  for (size_t index = 0; index < count; ++index) {
    const MixerCtlSpec& spec = specs[index];
    if (spec.is_enum) {
      if (!SetMixerEnum(api, mixer, spec.name, spec.enum_value,
                        log_failure)) {
        ok = false;
      }
    } else {
      if (!SetMixerValue(api, mixer, spec.name, spec.int_value,
                         log_failure)) {
        ok = false;
      }
    }
  }
  return ok;
}

int FindCard() {
  FILE* file = fopen("/proc/asound/cards", "r");
  if (!file) return -1;
  char line[256];
  int card = -1;
  while (fgets(line, sizeof(line), file)) {
    if (!strstr(line, "aw87xxx") && !strstr(line, "holi")) continue;
    if (sscanf(line, " %d", &card) == 1) break;
  }
  fclose(file);
  return card;
}

int FindPlaybackDevice(int card) {
  char path[64];
  for (int device = 0; device < 64; ++device) {
    snprintf(path, sizeof(path), "/dev/snd/pcmC%dD%dp", card, device);
    if (access(path, R_OK | W_OK) == 0) return device;
  }
  return 0;
}

int WaitForCard() {
  for (int attempt = 0; attempt < 100 && !g_stop; ++attempt) {
    const int card = FindCard();
    if (card >= 0) return card;
    usleep(100000);
  }
  return -1;
}

Mixer* OpenMixer(AudioApi& api, int card) {
  for (int attempt = 0; attempt < 50 && !g_stop; ++attempt) {
    Mixer* mixer = api.mixer_open(static_cast<unsigned int>(card));
    if (mixer) return mixer;
    usleep(100000);
  }
  return nullptr;
}

void DisableSpeaker(AudioApi& api) {
  const int card = FindCard();
  if (card < 0) return;
  Mixer* mixer = api.mixer_open(static_cast<unsigned int>(card));
  if (!mixer) return;
  ApplyPath(api, mixer, kDisablePath,
            sizeof(kDisablePath) / sizeof(kDisablePath[0]), false);
  api.mixer_close(mixer);
}

void PlayPipe(AudioApi& api, int input) {
  const int card = WaitForCard();
  if (card < 0) {
    fprintf(stderr, "AERA audio: sound card did not appear\n");
    return;
  }

  Mixer* mixer = OpenMixer(api, card);
  if (!mixer) {
    fprintf(stderr, "AERA audio: cannot open mixer for card %d\n", card);
    return;
  }
  const bool playback_ok =
      ApplyPath(api, mixer, kPlaybackPath,
                sizeof(kPlaybackPath) / sizeof(kPlaybackPath[0]), true);
  const bool speaker_ok =
      ApplyPath(api, mixer, kSpeakerPath,
                sizeof(kSpeakerPath) / sizeof(kSpeakerPath[0]), true);
  if (!playback_ok || !speaker_ok) {
    fprintf(stderr, "AERA audio: mixer path incomplete\n");
  }

  const int device = FindPlaybackDevice(card);
  PcmConfig config = {kChannels, kRate, kPeriodSize, kPeriodCount,
                      kPcmFormatS16Le, kPeriodSize * 2,
                      kPeriodSize * kPeriodCount, 0, 0,
                      static_cast<int>(kPeriodSize)};
  Pcm* pcm = nullptr;
  for (int attempt = 0; attempt < 50 && !g_stop; ++attempt) {
    pcm = api.pcm_open(static_cast<unsigned int>(card),
                       static_cast<unsigned int>(device), 0, &config);
    if (pcm && api.pcm_is_ready(pcm)) break;
    if (pcm) {
      fprintf(stderr, "AERA audio: PCM card %d device %d not ready: %s\n",
              card, device, api.pcm_get_error(pcm));
      api.pcm_close(pcm);
      pcm = nullptr;
    }
    usleep(100000);
  }
  if (!pcm) {
    fprintf(stderr, "AERA audio: cannot open PCM card %d device %d\n", card,
            device);
    ApplyPath(api, mixer, kDisablePath,
              sizeof(kDisablePath) / sizeof(kDisablePath[0]), false);
    api.mixer_close(mixer);
    return;
  }

  fprintf(stderr, "AERA audio: playing on card %d device %d\n", card, device);
  const int flags = fcntl(input, F_GETFL);
  if (flags >= 0) fcntl(input, F_SETFL, flags | O_NONBLOCK);
  std::array<uint8_t, kJitterBytes> buffer = {};
  size_t used = 0;
  size_t dropped_bytes = 0;
  unsigned int volume_counter = 0;
  int volume = ReadVolumePercent();
  int target_volume = volume;
  bool started = false;
  timespec next = {};
  timespec connected_at = {};
  clock_gettime(CLOCK_MONOTONIC, &connected_at);
  while (!g_stop) {
    if (used >= kWriteBytes) {
      timespec now = {};
      clock_gettime(CLOCK_MONOTONIC, &now);
      if (!started && used >= kPrefillBytes) {
        started = true;
        next = now;
      }
      if (started) {
        const bool due = now.tv_sec > next.tv_sec ||
                         (now.tv_sec == next.tv_sec &&
                          now.tv_nsec >= next.tv_nsec);
        if (due || used >= kCatchUpBytes) {
          if ((volume_counter++ % 4U) == 0) target_volume = ReadVolumePercent();
          ScaleS16(buffer.data(), kWriteBytes, volume, target_volume);
          volume = target_volume;
          const int result =
              api.pcm_write(pcm, buffer.data(),
                            static_cast<unsigned int>(kWriteBytes));
          if (result != 0) {
            if (result == -EPIPE || result == -ESTRPIPE) {
              if (api.pcm_prepare(pcm) != 0) {
                fprintf(stderr, "AERA audio: PCM prepare failed: %s\n",
                        api.pcm_get_error(pcm));
                break;
              }
              started = false;
              next = now;
              continue;
            }
            fprintf(stderr, "AERA audio: PCM write failed: %s\n",
                    api.pcm_get_error(pcm));
            break;
          }
          memmove(buffer.data(), buffer.data() + kWriteBytes,
                  used - kWriteBytes);
          used -= kWriteBytes;
          next.tv_nsec += kPeriodNanos;
          while (next.tv_nsec >= 1000000000L) {
            ++next.tv_sec;
            next.tv_nsec -= 1000000000L;
          }
          const long long ahead =
              static_cast<long long>(next.tv_sec - now.tv_sec) *
                  1000000000LL +
              static_cast<long long>(next.tv_nsec) -
                  static_cast<long long>(now.tv_nsec);
          if (ahead > kPeriodNanos) {
            next = now;
            next.tv_nsec += kPeriodNanos;
            while (next.tv_nsec >= 1000000000L) {
              ++next.tv_sec;
              next.tv_nsec -= 1000000000L;
            }
          } else if (ahead < -kPeriodNanos) {
            next = now;
          }
          continue;
        }
      }
    }
    if (used == buffer.size()) {
      poll(nullptr, 0, 5);
      continue;
    }
    pollfd event = {};
    event.fd = input;
    event.events = POLLIN;
    int timeout_ms = 10;
    if (started && used >= kWriteBytes) {
      timespec now = {};
      clock_gettime(CLOCK_MONOTONIC, &now);
      long wait_ms = (next.tv_sec - now.tv_sec) * 1000L +
                     (next.tv_nsec - now.tv_nsec) / 1000000L;
      if (wait_ms < 0) wait_ms = 0;
      if (wait_ms < timeout_ms) timeout_ms = static_cast<int>(wait_ms);
    }
    const int ready = poll(&event, 1, timeout_ms);
    if (ready < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (ready == 0) continue;
    if (event.revents & (POLLIN | POLLHUP | POLLERR)) {
      const ssize_t count =
          read(input, buffer.data() + used, buffer.size() - used);
      if (count > 0) {
        used += static_cast<size_t>(count);
        timespec now = {};
        clock_gettime(CLOCK_MONOTONIC, &now);
        const long elapsed = now.tv_sec - connected_at.tv_sec;
        const size_t cap = elapsed >= 4
            ? kMaxBufferedBytes
            : kStartupBufferedBytes +
                  (kMaxBufferedBytes - kStartupBufferedBytes) *
                      static_cast<size_t>(elapsed) / 4U;
        if (used > cap) {
          const size_t excess = used - cap;
          memmove(buffer.data(), buffer.data() + excess, used - excess);
          used -= excess;
          dropped_bytes += excess;
          next = now;
        }
        continue;
      }
      if (count == 0) break;
      if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
      break;
    }
  }

  if (dropped_bytes) {
    fprintf(stderr, "AERA audio: discarded %zu bytes of stale audio\n",
            dropped_bytes);
  }
  api.pcm_close(pcm);
  api.mixer_close(mixer);
}

void DrainClient(int client) {
  std::array<uint8_t, 8192> buffer = {};
  while (!g_stop) {
    const ssize_t count = read(client, buffer.data(), buffer.size());
    if (count > 0) continue;
    if (count < 0 && errno == EINTR) continue;
    break;
  }
}

void ServeClient(AudioApi& api, int client, bool& audio_ready) {
  setsockopt(client, SOL_SOCKET, SO_RCVBUF, &kSocketBufferBytes,
             sizeof(kSocketBufferBytes));
  struct ucred credentials = {};
  socklen_t credentials_size = sizeof(credentials);
  if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &credentials,
                 &credentials_size) != 0 ||
      credentials_size != sizeof(credentials) ||
      (credentials.uid != kBrowserUid && credentials.uid != kMediaUid &&
       credentials.uid != kDoomUid)) {
    fprintf(stderr, "AERA audio: rejected local UID %u\n", credentials.uid);
    return;
  }

  std::array<uint32_t, 4> hello = {};
  if (!ReadAll(client, hello.data(), sizeof(hello)) || hello[0] != kMagic ||
      hello[1] != kRate || hello[2] != kChannels || hello[3] != kBits) {
    fprintf(stderr, "AERA audio: rejected invalid PCM handshake\n");
    return;
  }

  if (!audio_ready) {
    audio_ready = api.Load();
    if (audio_ready) {
      fprintf(stderr, "AERA audio: browser PCM bridge ready (late)\n");
    }
  }
  if (!audio_ready) {
    DrainClient(client);
    return;
  }

  PlayPipe(api, client);
}
}  // namespace

int main(int argc, char** argv) {
  if (argc != 2 || strcmp(argv[1], "--browser-audio") != 0 ||
      getuid() != 0) {
    fprintf(stderr,
            "Usage (root recovery only): aera-audio-bridge --browser-audio\n");
    return 64;
  }

  signal(SIGPIPE, SIG_IGN);
  signal(SIGTERM, Stop);
  signal(SIGINT, Stop);
  prctl(PR_SET_PDEATHSIG, SIGTERM, 0, 0, 0);

  const int server = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (server < 0) return 70;
  setsockopt(server, SOL_SOCKET, SO_RCVBUF, &kSocketBufferBytes,
             sizeof(kSocketBufferBytes));
  sockaddr_un address = {};
  address.sun_family = AF_UNIX;
  memcpy(address.sun_path + 1, kSocketName, sizeof(kSocketName) - 1);
  const socklen_t address_size = static_cast<socklen_t>(
      offsetof(sockaddr_un, sun_path) + 1 + sizeof(kSocketName) - 1);
  if (bind(server, reinterpret_cast<const sockaddr*>(&address),
           address_size) != 0 ||
      listen(server, 4) != 0) {
    close(server);
    return 70;
  }

  AudioApi api;
  bool audio_ready = api.Load();
  if (audio_ready) {
    fprintf(stderr, "AERA audio: browser PCM bridge ready\n");
  } else {
    fprintf(stderr, "AERA audio: no tinyalsa backend; serving silence\n");
  }

  while (!g_stop) {
    const int client = accept4(server, nullptr, nullptr, SOCK_CLOEXEC);
    if (client < 0) {
      if (errno == EINTR) continue;
      break;
    }
    ServeClient(api, client, audio_ready);
    close(client);
    if (audio_ready && !g_stop) {
      pollfd pending = {};
      pending.fd = server;
      pending.events = POLLIN;
      const int ready = poll(&pending, 1, 250);
      if (ready <= 0 || !(pending.revents & POLLIN)) {
        DisableSpeaker(api);
      }
    }
  }
  if (audio_ready) DisableSpeaker(api);
  close(server);
  return 0;
}
