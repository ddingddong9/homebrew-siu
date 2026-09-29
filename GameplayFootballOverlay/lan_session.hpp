#pragma once

#include "lan_protocol.hpp"

#include <chrono>
#include <cstdint>
#include <string>

#include <netinet/in.h>

namespace siu {

enum class LanMode { offline, host, client };

class LanSession {
 public:
  LanSession() = default;
  ~LanSession();
  LanSession(const LanSession &) = delete;
  LanSession &operator=(const LanSession &) = delete;

  bool Configure(LanMode mode, const std::string &host_address, uint16_t port);
  void Poll();
  bool SendInput(const InputFrame &input);
  bool SendSnapshot(const Snapshot &snapshot);
  bool LatestInput(InputFrame &out) const;
  bool TakeSnapshot(Snapshot &out);
  LanMode mode() const { return mode_; }
  bool peer_seen() const { return peer_seen_; }
  uint64_t input_packets() const { return input_packets_; }
  uint64_t snapshot_packets() const { return snapshot_packets_; }
  const std::string &error() const { return error_; }

 private:
  bool Send(const std::vector<uint8_t> &packet);
  void Close();

  int socket_ = -1;
  LanMode mode_ = LanMode::offline;
  sockaddr_in peer_{};
  uint32_t allowed_host_address_ = 0;
  bool peer_seen_ = false;
  std::string error_;
  InputFrame latest_input_;
  Snapshot latest_snapshot_;
  bool has_input_ = false;
  bool has_snapshot_ = false;
  uint64_t input_packets_ = 0;
  uint64_t snapshot_packets_ = 0;
  std::chrono::steady_clock::time_point last_input_;
};

LanSession &Session();

} // namespace siu
