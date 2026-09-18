import Foundation
import SwiftSignalKit

public final class PampGramBanCache {
    public static let shared = PampGramBanCache()

    private let _status = Atomic<PampGramBanStatus>(value: .none)
    private let statusPromise = ValuePromise<PampGramBanStatus>(.none, ignoreRepeated: true)
    private var disposable: Disposable?

    private init() {}

    public var status: PampGramBanStatus {
        return _status.with { $0 }
    }

    public var isFullyBanned: Bool {
        return status.full != nil
    }

    public func signal() -> Signal<PampGramBanStatus, NoError> {
        return statusPromise.get()
    }

    public func start(userId: Int64) {
        disposable?.dispose()
        disposable = (PampGramSubscriptionAPI.fetchBanStatus(userId: userId)
        |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let self else { return }
            let _ = self._status.modify { _ in status }
            self.statusPromise.set(status)
        })
    }

    deinit {
        disposable?.dispose()
    }
}
