import Foundation
import Network

struct LocalRoom: Hashable {
    let name: String
    let endpoint: NWEndpoint
}

@MainActor
final class LocalRoomBrowser {
    private let browser = NWBrowser(for: .bonjourWithTXTRecord(type: MatchTransport.roomServiceType,
                                                               domain: nil),
                                    using: .udp)
    private var active = false

    func start(onChange: @escaping ([LocalRoom]) -> Void,
               onFailure: @escaping () -> Void) {
        guard !active else { return }
        active = true
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self, self.active else { return }
                let rooms = results.compactMap { result -> LocalRoom? in
                    guard case .service(let name, _, _, _) = result.endpoint,
                          case .bonjour(let record) = result.metadata,
                          record["version"] == String(MatchMessage.protocolVersion) else { return nil }
                    return LocalRoom(name: name, endpoint: result.endpoint)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                onChange(rooms)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                DispatchQueue.main.async {
                    guard let self, self.active, self.browser.browseResults.isEmpty else { return }
                    onChange([])
                }
            } else if case .failed = state {
                DispatchQueue.main.async {
                    guard let self, self.active else { return }
                    self.cancel()
                    onFailure()
                }
            }
        }
        browser.start(queue: .main)
    }

    func cancel() {
        guard active else { return }
        active = false
        browser.cancel()
    }
}
