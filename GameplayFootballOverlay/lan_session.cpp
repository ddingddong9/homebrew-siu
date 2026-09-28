#include "lan_session.hpp"

#include <cerrno>
#include <cstring>
#include <vector>

#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

namespace siu {

LanSession::~LanSession() { Close(); }

void LanSession::Close() {
  if (socket_ >= 0) close(socket_);
  socket_ = -1;
  mode_ = LanMode::offline;
  peer_seen_ = false;
  has_input_ = false;
  has_snapshot_ = false;
  input_packets_ = 0;
  snapshot_packets_ = 0;
}

bool LanSession::Configure(LanMode mode, const std::string &host_address, uint16_t port) {
  Close();
  error_.clear();
  if (mode == LanMode::offline) return true;
  if (!port) { error_ = "port must be nonzero"; return false; }

  socket_ = socket(AF_INET, SOCK_DGRAM, 0);
  if (socket_ < 0) { error_ = std::strerror(errno); return false; }
  if (fcntl(socket_, F_SETFL, fcntl(socket_, F_GETFL, 0) | O_NONBLOCK) < 0) {
    error_ = std::strerror(errno);
    Close();
    return false;
  }

  mode_ = mode;
  if (mode == LanMode::host) {
    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(port);
    if (bind(socket_, reinterpret_cast<sockaddr *>(&local), sizeof(local)) < 0) {
      error_ = std::strerror(errno);
      Close();
      return false;
    }
  } else {
    peer_.sin_family = AF_INET;
    peer_.sin_port = htons(port);
    if (inet_pton(AF_INET, host_address.c_str(), &peer_.sin_addr) != 1) {
      error_ = "client host must be an IPv4 address";
      Close();
      return false;
    }
    peer_seen_ = true;
  }
  return true;
}

void LanSession::Poll() {
  if (socket_ < 0) return;
  uint8_t bytes[kMaxPacketSize + 1];
  for (int i = 0; i < 32; ++i) {
    sockaddr_in sender{};
    socklen_t sender_size = sizeof(sender);
    ssize_t n = recvfrom(socket_, bytes, sizeof(bytes), 0,
                         reinterpret_cast<sockaddr *>(&sender), &sender_size);
    if (n < 0) {
      if (errno != EAGAIN && errno != EWOULDBLOCK) error_ = std::strerror(errno);
      break;
    }
    if (n > static_cast<ssize_t>(kMaxPacketSize) || sender_size != sizeof(sender)) continue;
    if (mode_ == LanMode::host) {
      InputFrame incoming;
      if (!DecodeInput(bytes, size_t(n), incoming)) continue;
      if (peer_seen_ && (sender.sin_addr.s_addr != peer_.sin_addr.s_addr || sender.sin_port != peer_.sin_port)) continue;
      if (has_input_ && int32_t(incoming.sequence - latest_input_.sequence) <= 0) continue;
      peer_ = sender;
      peer_seen_ = true;
      latest_input_ = incoming;
      has_input_ = true;
      ++input_packets_;
      last_input_ = std::chrono::steady_clock::now();
    } else if (mode_ == LanMode::client) {
      if (sender.sin_addr.s_addr != peer_.sin_addr.s_addr || sender.sin_port != peer_.sin_port) continue;
      Snapshot incoming;
      if (!DecodeSnapshot(bytes, size_t(n), incoming)) continue;
      if (has_snapshot_ && int32_t(incoming.sequence - latest_snapshot_.sequence) <= 0) continue;
      latest_snapshot_ = incoming;
      has_snapshot_ = true;
      ++snapshot_packets_;
    }
  }
}

bool LanSession::Send(const std::vector<uint8_t> &packet) {
  if (socket_ < 0 || !peer_seen_) return false;
  ssize_t sent = sendto(socket_, packet.data(), packet.size(), 0,
                        reinterpret_cast<sockaddr *>(&peer_), sizeof(peer_));
  if (sent != static_cast<ssize_t>(packet.size())) {
    error_ = std::strerror(errno);
    return false;
  }
  return true;
}

bool LanSession::SendInput(const InputFrame &input) {
  if (mode_ != LanMode::client) return false;
  std::vector<uint8_t> packet;
  return EncodeInput(input, packet) && Send(packet);
}

bool LanSession::SendSnapshot(const Snapshot &snapshot) {
  if (mode_ != LanMode::host) return false;
  std::vector<uint8_t> packet;
  return EncodeSnapshot(snapshot, packet) && Send(packet);
}

bool LanSession::LatestInput(InputFrame &out) const {
  if (!has_input_) return false;
  auto age = std::chrono::steady_clock::now() - last_input_;
  if (age > std::chrono::milliseconds(250)) return false;
  out = latest_input_;
  return true;
}

bool LanSession::TakeSnapshot(Snapshot &out) {
  if (!has_snapshot_) return false;
  out = latest_snapshot_;
  has_snapshot_ = false;
  return true;
}

LanSession &Session() {
  static LanSession session;
  return session;
}

} // namespace siu
