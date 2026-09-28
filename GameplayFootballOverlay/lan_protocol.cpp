#include "lan_protocol.hpp"

#include <cmath>
#include <cstring>

namespace siu {
namespace {

class Writer {
 public:
  explicit Writer(std::vector<uint8_t> &bytes) : bytes_(bytes) { bytes_.clear(); }
  void U8(uint8_t v) { bytes_.push_back(v); }
  void U16(uint16_t v) { U8(uint8_t(v >> 8)); U8(uint8_t(v)); }
  void U32(uint32_t v) { U16(uint16_t(v >> 16)); U16(uint16_t(v)); }
  void Float(float v) {
    uint32_t bits;
    std::memcpy(&bits, &v, sizeof(bits));
    U32(bits);
  }
  void Vector(Vec3 v) { Float(v.x); Float(v.y); Float(v.z); }
 private:
  std::vector<uint8_t> &bytes_;
};

class Reader {
 public:
  Reader(const uint8_t *bytes, size_t size) : bytes_(bytes), size_(size) {}
  bool U8(uint8_t &v) {
    if (left() < 1) return false;
    v = bytes_[pos_++];
    return true;
  }
  bool U16(uint16_t &v) {
    uint8_t a, b;
    if (!U8(a) || !U8(b)) return false;
    v = (uint16_t(a) << 8) | b;
    return true;
  }
  bool U32(uint32_t &v) {
    uint16_t a, b;
    if (!U16(a) || !U16(b)) return false;
    v = (uint32_t(a) << 16) | b;
    return true;
  }
  bool Float(float &v) {
    uint32_t bits;
    if (!U32(bits)) return false;
    std::memcpy(&v, &bits, sizeof(v));
    return std::isfinite(v);
  }
  bool Vector(Vec3 &v) { return Float(v.x) && Float(v.y) && Float(v.z); }
  size_t left() const { return size_ - pos_; }
 private:
  const uint8_t *bytes_;
  size_t size_;
  size_t pos_ = 0;
};

void Header(Writer &w, PacketKind kind) {
  w.U32(kMagic);
  w.U16(kProtocolVersion);
  w.U16(uint16_t(kind));
}

bool Header(Reader &r, PacketKind kind) {
  uint32_t magic;
  uint16_t version, actual_kind;
  return r.U32(magic) && r.U16(version) && r.U16(actual_kind) &&
         magic == kMagic && version == kProtocolVersion && actual_kind == uint16_t(kind);
}

} // namespace

bool EncodeInput(const InputFrame &frame, std::vector<uint8_t> &out) {
  Writer w(out);
  Header(w, PacketKind::input);
  w.U32(frame.sequence);
  w.U32(frame.target_tick);
  w.U32(frame.button_mask);
  w.U32(frame.acknowledged_snapshot);
  return out.size() <= kMaxPacketSize;
}

bool DecodeInput(const uint8_t *bytes, size_t size, InputFrame &out) {
  if (!bytes || size != 24) return false;
  Reader r(bytes, size);
  InputFrame temp;
  if (!Header(r, PacketKind::input) || !r.U32(temp.sequence) ||
      !r.U32(temp.target_tick) || !r.U32(temp.button_mask) ||
      !r.U32(temp.acknowledged_snapshot) || r.left()) return false;
  if (temp.button_mask & 0xfffc0000u) return false; // 18 HID functions
  out = temp;
  return true;
}

bool EncodeSnapshot(const Snapshot &frame, std::vector<uint8_t> &out) {
  Writer w(out);
  Header(w, PacketKind::snapshot);
  w.U32(frame.sequence);
  w.U32(frame.server_tick);
  w.U32(frame.acknowledged_input);
  w.U32(frame.match_time_ms);
  w.U8(frame.score_home);
  w.U8(frame.score_away);
  w.U8(frame.phase);
  w.U8(frame.play_flags);
  w.U8(frame.selected_home);
  w.U8(frame.selected_away);
  w.Vector(frame.ball_position);
  w.Vector(frame.ball_movement);
  for (const PlayerState &p : frame.players) {
    w.U16(p.id);
    w.U8(p.team);
    w.U8(p.active ? 1 : 0);
    w.Vector(p.position);
    w.Vector(p.movement);
    w.U16(p.animation_id);
    w.U16(p.animation_frame);
    w.Vector(p.render_position);
    w.Float(p.render_orientation);
    w.U8(p.render_no_pos ? 1 : 0);
  }
  return out.size() <= kMaxPacketSize;
}

bool DecodeSnapshot(const uint8_t *bytes, size_t size, Snapshot &out) {
  if (!bytes || size != 8 + 16 + 6 + 24 + kPlayerCount * 49 || size > kMaxPacketSize) return false;
  Reader r(bytes, size);
  Snapshot temp;
  if (!Header(r, PacketKind::snapshot) || !r.U32(temp.sequence) ||
      !r.U32(temp.server_tick) || !r.U32(temp.acknowledged_input) ||
      !r.U32(temp.match_time_ms) || !r.U8(temp.score_home) ||
      !r.U8(temp.score_away) || !r.U8(temp.phase) || !r.U8(temp.play_flags) ||
      !r.U8(temp.selected_home) || !r.U8(temp.selected_away) ||
      !r.Vector(temp.ball_position) || !r.Vector(temp.ball_movement)) return false;
  if (temp.phase > 5 || (temp.play_flags & ~uint8_t(7))) return false;
  for (PlayerState &p : temp.players) {
    uint8_t active, render_no_pos;
    if (!r.U16(p.id) || !r.U8(p.team) || !r.U8(active) ||
        !r.Vector(p.position) || !r.Vector(p.movement) ||
        !r.U16(p.animation_id) || !r.U16(p.animation_frame) ||
        !r.Vector(p.render_position) || !r.Float(p.render_orientation) ||
        !r.U8(render_no_pos)) return false;
    if (p.team > 1 || active > 1 || render_no_pos > 1) return false;
    p.active = active != 0;
    p.render_no_pos = render_no_pos != 0;
  }
  if (r.left()) return false;
  out = temp;
  return true;
}

} // namespace siu
