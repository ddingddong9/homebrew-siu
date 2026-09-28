#include "lan_protocol.hpp"

#include <cassert>
#include <cmath>
#include <vector>

int main() {
  using namespace siu;
  std::vector<uint8_t> wire;
  InputFrame input;
  input.sequence = 42;
  input.target_tick = 100;
  input.button_mask = (1u << 3) | (1u << 7);
  input.acknowledged_snapshot = 31;
  assert(EncodeInput(input, wire) && wire.size() == 24);
  InputFrame decoded_input;
  assert(DecodeInput(wire.data(), wire.size(), decoded_input));
  assert(decoded_input.sequence == 42 && decoded_input.target_tick == 100);
  assert(decoded_input.button_mask == input.button_mask);
  assert(!DecodeInput(wire.data(), wire.size() - 1, decoded_input));
  wire[0] ^= 1;
  assert(!DecodeInput(wire.data(), wire.size(), decoded_input));

  Snapshot snapshot;
  snapshot.sequence = 10;
  snapshot.server_tick = 550;
  snapshot.acknowledged_input = 42;
  snapshot.match_time_ms = 123456;
  snapshot.score_home = 2;
  snapshot.score_away = 1;
  snapshot.play_flags = 1;
  snapshot.ball_position = {1.5f, -2.0f, 0.3f};
  snapshot.ball_movement = {0.1f, 0.2f, 0.3f};
  for (size_t i = 0; i < kPlayerCount; ++i) {
    snapshot.players[i].id = uint16_t(i + 1);
    snapshot.players[i].team = uint8_t(i / 11);
    snapshot.players[i].active = true;
    snapshot.players[i].position = {float(i), float(i * 2), 0};
    snapshot.players[i].animation_id = uint16_t(i + 10);
    snapshot.players[i].animation_frame = uint16_t(i + 20);
    snapshot.players[i].render_position = {float(i) + 0.5f, float(i * 2), 0};
    snapshot.players[i].render_orientation = 0.25f;
    snapshot.players[i].render_no_pos = true;
  }
  assert(EncodeSnapshot(snapshot, wire) && wire.size() == 1132);
  Snapshot decoded_snapshot;
  assert(DecodeSnapshot(wire.data(), wire.size(), decoded_snapshot));
  assert(decoded_snapshot.server_tick == 550 && decoded_snapshot.score_home == 2);
  assert(decoded_snapshot.play_flags == 1);
  assert(decoded_snapshot.players[21].team == 1);
  assert(decoded_snapshot.players[21].animation_frame == 41);
  assert(decoded_snapshot.players[21].render_position.x == 21.5f);
  assert(decoded_snapshot.players[21].render_orientation == 0.25f);
  assert(decoded_snapshot.players[21].render_no_pos);
  assert(decoded_snapshot.ball_position.x == 1.5f);
  assert(!DecodeSnapshot(wire.data(), wire.size() - 1, decoded_snapshot));
  wire[26] = 6; // invalid match phase
  assert(!DecodeSnapshot(wire.data(), wire.size(), decoded_snapshot));
  wire[26] = 0;
  wire[27] = 8; // unknown play flag
  assert(!DecodeSnapshot(wire.data(), wire.size(), decoded_snapshot));
  wire[27] = 1;
  const uint8_t old_ball_x[4] = {wire[30], wire[31], wire[32], wire[33]};
  wire[30] = 0x7f;
  wire[31] = 0x80;
  wire[32] = 0;
  wire[33] = 0; // +infinity is not a valid position
  assert(!DecodeSnapshot(wire.data(), wire.size(), decoded_snapshot));
  for (int i = 0; i < 4; ++i) wire[30 + i] = old_ball_x[i];
  wire[5] = 4; // unsupported protocol version
  assert(!DecodeSnapshot(wire.data(), wire.size(), decoded_snapshot));
  return 0;
}
