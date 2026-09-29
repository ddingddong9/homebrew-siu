#include "lan_session.hpp"

#include <cassert>
#include <chrono>
#include <thread>

#include <unistd.h>

int main() {
  using namespace siu;
  const uint16_t port = uint16_t(30000 + getpid() % 20000);
  LanSession host, client, stranger;
  assert(host.Configure(LanMode::host, "127.0.0.2", port));
  assert(client.Configure(LanMode::client, "127.0.0.1", port));
  assert(stranger.Configure(LanMode::client, "127.0.0.1", port));

  InputFrame input;
  input.sequence = 1;
  input.button_mask = 1u << 7;
  assert(client.SendInput(input));
  for (int i = 0; i < 10; ++i) {
    host.Poll();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(!host.peer_seen()); // a client outside the approved address cannot claim the match
  assert(host.Configure(LanMode::host, "127.0.0.1", port));
  assert(client.SendInput(input));
  InputFrame received;
  for (int i = 0; i < 100 && !host.LatestInput(received); ++i) {
    host.Poll();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(host.peer_seen() && host.LatestInput(received));
  assert(received.sequence == 1 && received.button_mask == (1u << 7));
  std::this_thread::sleep_for(std::chrono::milliseconds(260));
  assert(!host.LatestInput(received)); // stale held keys must go neutral

  input.sequence = 2;
  assert(client.SendInput(input));
  for (int i = 0; i < 100 && !host.LatestInput(received); ++i) {
    host.Poll();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(host.LatestInput(received) && received.sequence == 2);

  input.sequence = 3;
  input.button_mask = 1u << 4;
  assert(stranger.SendInput(input));
  host.Poll();
  assert(host.LatestInput(received) && received.sequence == 2);

  Snapshot snapshot;
  snapshot.sequence = 6;
  snapshot.server_tick = 900;
  snapshot.ball_position = {1.0f, 2.0f, 3.0f};
  assert(host.SendSnapshot(snapshot));
  Snapshot received_snapshot;
  bool got_snapshot = false;
  for (int i = 0; i < 100 && !got_snapshot; ++i) {
    client.Poll();
    got_snapshot = client.TakeSnapshot(received_snapshot);
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(got_snapshot && received_snapshot.server_tick == 900);
  assert(received_snapshot.ball_position.z == 3.0f);
  return 0;
}
