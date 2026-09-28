#pragma once

#include <cstdint>
#include <string>
#include <vector>

class IHIDevice;
class Match;

namespace siu {

bool ConfigureGameLan(const std::string &role, const std::string &host_address, uint16_t port);
IHIDevice *CreateRemoteHID();
void PollGameLan();
void SendLocalInput(const std::vector<IHIDevice*> &controllers, Match *match);
void SyncMatch(Match *match);

} // namespace siu
