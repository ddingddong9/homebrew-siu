#include "lan_bridge.hpp"

#include "lan_session.hpp"

#include "hid/ihidevice.hpp"
#include "onthepitch/match.hpp"
#include "base/log.hpp"

#include <algorithm>
#include <array>
#include <cmath>

namespace siu {
namespace {

uint32_t next_input_sequence = 0;
uint32_t next_snapshot_sequence = 0;
uint32_t last_snapshot_sequence = 0;
double accumulated_position_error = 0;
double accumulated_ball_error = 0;
uint64_t compared_players = 0;
uint64_t compared_snapshots = 0;
uint64_t animation_mismatches = 0;
uint64_t accepted_remote_poses = 0;

Vec3 ToWire(const blunted::Vector3 &v) {
  return {v.coords[0], v.coords[1], v.coords[2]};
}

blunted::Vector3 FromWire(Vec3 v) {
  return blunted::Vector3(v.x, v.y, v.z);
}

class RemoteHID : public IHIDevice {
 public:
  RemoteHID() {
    deviceType = e_HIDeviceType_Keyboard;
    identifier = "LAN remote keyboard";
    LoadConfig();
  }
  void LoadConfig() override {
    boost::mutex::scoped_lock lock(mutex);
    states_.fill(false);
    previous_.fill(false);
  }
  void SaveConfig() override {}
  void Process() override {
    InputFrame input;
    const uint32_t mask = Session().LatestInput(input) ? input.button_mask : 0;
    boost::mutex::scoped_lock lock(mutex);
    previous_ = states_;
    for (size_t i = 0; i < states_.size(); ++i) states_[i] = (mask & (1u << i)) != 0;
  }
  bool GetButton(e_ButtonFunction function) override {
    boost::mutex::scoped_lock lock(mutex);
    return states_[function];
  }
  float GetButtonValue(e_ButtonFunction function) override { return GetButton(function) ? 1.0f : 0.0f; }
  void SetButton(e_ButtonFunction function, bool state) override {
    boost::mutex::scoped_lock lock(mutex);
    states_[function] = state;
  }
  bool GetPreviousButtonState(e_ButtonFunction function) override {
    boost::mutex::scoped_lock lock(mutex);
    return previous_[function];
  }
  blunted::Vector3 GetDirection() override {
    blunted::Vector3 direction;
    if (GetButton(e_ButtonFunction_Left)) direction.coords[0] -= 1;
    if (GetButton(e_ButtonFunction_Right)) direction.coords[0] += 1;
    if (GetButton(e_ButtonFunction_Up)) direction.coords[1] += 1;
    if (GetButton(e_ButtonFunction_Down)) direction.coords[1] -= 1;
    direction.Normalize(0);
    return direction;
  }
 private:
  std::array<bool, e_ButtonFunction_Size> states_;
  std::array<bool, e_ButtonFunction_Size> previous_;
};

Snapshot Capture(Match *match) {
  Snapshot snapshot;
  snapshot.sequence = ++next_snapshot_sequence;
  snapshot.server_tick = uint32_t(match->GetIterations());
  InputFrame last_input;
  if (Session().LatestInput(last_input)) snapshot.acknowledged_input = last_input.sequence;
  snapshot.match_time_ms = uint32_t(match->GetMatchTime_ms());
  snapshot.score_home = uint8_t(std::min(match->GetScore(0), 255));
  snapshot.score_away = uint8_t(std::min(match->GetScore(1), 255));
  snapshot.phase = uint8_t(match->GetMatchPhase());
  snapshot.play_flags = uint8_t((match->IsInPlay() ? 1 : 0) |
                                (match->IsInSetPiece() ? 2 : 0) |
                                (match->IsGoalScored() ? 4 : 0));
  snapshot.ball_position = ToWire(match->GetBall()->Predict(0));
  snapshot.ball_movement = ToWire(match->GetBall()->GetMovement());

  size_t index = 0;
  for (int team = 0; team < 2; ++team) {
    std::vector<Player*> players;
    match->GetActiveTeamPlayers(team, players);
    for (Player *player : players) {
      if (index >= snapshot.players.size()) break;
      PlayerState &state = snapshot.players[index++];
      state.id = uint16_t(player->GetID());
      state.team = uint8_t(team);
      state.active = true;
      state.position = ToWire(player->GetPosition());
      state.movement = ToWire(player->GetMovement());
      state.animation_id = uint16_t(player->GetCurrentAnim()->id);
      state.animation_frame = uint16_t(player->GetFrameNum());
      blunted::Vector3 render_position;
      radian render_orientation;
      bool render_no_pos;
      player->CastHumanoid()->GetLanRenderPose(render_position, render_orientation, render_no_pos);
      state.render_position = ToWire(render_position);
      state.render_orientation = render_orientation;
      state.render_no_pos = render_no_pos;
    }
  }
  return snapshot;
}

void ApplyVisualCorrection(Match *match, const Snapshot &snapshot) {
  match->ApplyLanAuthority(snapshot.score_home, snapshot.score_away,
      e_MatchPhase(snapshot.phase), snapshot.match_time_ms,
      (snapshot.play_flags & 1) != 0, (snapshot.play_flags & 2) != 0,
      (snapshot.play_flags & 4) != 0);
  accumulated_ball_error += (FromWire(snapshot.ball_position) - match->GetBall()->Predict(0)).GetLength();
  ++compared_snapshots;
  for (const PlayerState &state : snapshot.players) {
    if (!state.active) continue;
    const auto &players = match->GetTeam(state.team)->GetAllPlayers();
    auto found = std::find_if(players.begin(), players.end(), [&](Player *p) {
      return p->GetID() == state.id && p->IsActive();
    });
    if (found == players.end()) continue;
    Player *player = *found;
    blunted::Vector3 difference = FromWire(state.position) - player->GetPosition();
    accumulated_position_error += difference.GetLength();
    ++compared_players;
    if (player->GetCurrentAnim()->id != state.animation_id ||
        std::abs(player->GetFrameNum() - int(state.animation_frame)) > 2) ++animation_mismatches;
    difference.coords[2] = 0; // OffsetPosition only supports ground-plane motion.
    if (difference.GetLength() > 0.01f) player->OffsetPosition(difference);
    if (player->CastHumanoid()->SetLanRenderPose(state.animation_id, state.animation_frame,
        FromWire(state.render_position), state.render_orientation, state.render_no_pos,
        FromWire(state.movement))) ++accepted_remote_poses;
  }
  match->GetBall()->SetPosition(FromWire(snapshot.ball_position));
  match->GetBall()->SetMomentum(FromWire(snapshot.ball_movement));
}

} // namespace

bool ConfigureGameLan(const std::string &role, const std::string &host_address, uint16_t port) {
  LanMode mode = LanMode::offline;
  if (role == "host") mode = LanMode::host;
  else if (role == "client") mode = LanMode::client;
  else if (!role.empty()) return false;
  return Session().Configure(mode, host_address, port);
}

IHIDevice *CreateRemoteHID() { return new RemoteHID(); }

void PollGameLan() { Session().Poll(); }

void SendLocalInput(const std::vector<IHIDevice*> &controllers, Match *match) {
  if (Session().mode() != LanMode::client || controllers.empty()) return;
  InputFrame input;
  input.sequence = ++next_input_sequence;
  input.target_tick = match ? uint32_t(match->GetIterations() + 2) : 0;
  input.acknowledged_snapshot = last_snapshot_sequence;
  for (int i = 0; i < e_ButtonFunction_Size; ++i) {
    if (controllers[0]->GetButton(e_ButtonFunction(i))) input.button_mask |= 1u << i;
  }
  Session().SendInput(input);
}

void SyncMatch(Match *match) {
  if (!match) return;
  if (match->GetIterations() % 1000 == 0) {
    const bool host = Session().mode() == LanMode::host;
    if (host || Session().mode() == LanMode::client) {
      blunted::Log(blunted::e_Notice, "SIU LAN", "SyncMatch",
                   std::string(host ? "input packets " : "snapshot packets ") +
                   std::to_string(host ? Session().input_packets() : Session().snapshot_packets()));
      if (!host && compared_snapshots) {
        blunted::Log(blunted::e_Notice, "SIU LAN", "Divergence",
                     "mean player error " + std::to_string(accumulated_position_error / std::max<uint64_t>(compared_players, 1)) +
                     "m; mean ball error " + std::to_string(accumulated_ball_error / compared_snapshots) +
                     "m; animation mismatches " + std::to_string(animation_mismatches) +
                     "/" + std::to_string(compared_players) +
                     "; accepted render poses " + std::to_string(accepted_remote_poses));
        accumulated_position_error = accumulated_ball_error = 0;
        compared_players = compared_snapshots = animation_mismatches = accepted_remote_poses = 0;
      }
    }
  }
  if (Session().mode() == LanMode::host) {
    if (match->GetIterations() % 4 == 0) Session().SendSnapshot(Capture(match));
  } else if (Session().mode() == LanMode::client) {
    Snapshot snapshot;
    if (Session().TakeSnapshot(snapshot)) {
      last_snapshot_sequence = snapshot.sequence;
      ApplyVisualCorrection(match, snapshot);
    }
  }
}

} // namespace siu
