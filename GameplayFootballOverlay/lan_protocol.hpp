#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace siu {

constexpr uint32_t kMagic = 0x53495546; // SIUF
constexpr uint16_t kProtocolVersion = 3;
constexpr size_t kPlayerCount = 22;
constexpr size_t kMaxPacketSize = 1200;

enum class PacketKind : uint16_t { input = 1, snapshot = 2 };

struct Vec3 {
  float x = 0;
  float y = 0;
  float z = 0;
};

struct InputFrame {
  uint32_t sequence = 0;
  uint32_t target_tick = 0;
  uint32_t button_mask = 0;
  uint32_t acknowledged_snapshot = 0;
};

struct PlayerState {
  uint16_t id = 0;
  uint8_t team = 0;
  bool active = false;
  Vec3 position;
  Vec3 movement;
  uint16_t animation_id = 0;
  uint16_t animation_frame = 0;
  Vec3 render_position;
  float render_orientation = 0;
  bool render_no_pos = false;
};

struct Snapshot {
  uint32_t sequence = 0;
  uint32_t server_tick = 0;
  uint32_t acknowledged_input = 0;
  uint32_t match_time_ms = 0;
  uint8_t score_home = 0;
  uint8_t score_away = 0;
  uint8_t phase = 0;
  uint8_t play_flags = 0; // bit 0: in play; bit 1: set piece; bit 2: goal scored
  uint8_t selected_home = 0xff;
  uint8_t selected_away = 0xff;
  Vec3 ball_position;
  Vec3 ball_movement;
  std::array<PlayerState, kPlayerCount> players;
};

bool EncodeInput(const InputFrame &frame, std::vector<uint8_t> &out);
bool DecodeInput(const uint8_t *bytes, size_t size, InputFrame &out);
bool EncodeSnapshot(const Snapshot &frame, std::vector<uint8_t> &out);
bool DecodeSnapshot(const uint8_t *bytes, size_t size, Snapshot &out);

} // namespace siu
