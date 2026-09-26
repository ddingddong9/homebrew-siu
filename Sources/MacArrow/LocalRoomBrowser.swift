import Foundation
import Network

@MainActor
final class LocalRoomBrowser {
    private let browser: NWBrowser
    private let transport: MatchTransport
    private var attempted = Set<NWEndpoint>()
    private var finished = false
    private var completion: ((NWEndpoint, UUID) -> Void)?
    private var onFailure: (() -> Void)?

    init(transport: MatchTransport) {
        self.transport = transport
        browser = NWBrowser(for: .bonjour(type: MatchTransport.roomServiceType, domain: nil),
                            using: .udp)
    }

    func start(onFound: @escaping (NWEndpoint, UUID) -> Void,
               onFailure: @escaping () -> Void) {
        completion = onFound
        self.onFailure = onFailure
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                for result in results where self.attempted.insert(result.endpoint).inserted {
                    self.transport.ping(endpoint: result.endpoint) { [weak self] peerID in
                        guard let self, let peerID, !self.finished else { return }
                        self.finished = true
                        self.browser.cancel()
                        self.completion?(result.endpoint, peerID)
                    }
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { DispatchQueue.main.async { self?.fail() } }
        }
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.fail() }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        browser.cancel()
    }

    private func fail() {
        guard !finished else { return }
        finished = true
        browser.cancel()
        onFailure?()
    }
}
