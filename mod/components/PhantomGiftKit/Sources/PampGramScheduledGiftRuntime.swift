import Foundation
import SwiftSignalKit
import AccountContext

/// Periodically materializes any "Подарок мне" gift scheduled for later delivery
/// (`PampGramPhantomGiftManager.scheduleReceiveGift`) once its time has come — the local,
/// no-server replacement for the old P2P relay (a shared Cloudflare Worker, removed as
/// unreliable). Checking every 30s is plenty against the picker's own coarsest granularity (5
/// minutes); only runs while the app is actually open, same as every other PampGram runtime —
/// a gift scheduled for "завтра" materializes the next time the app is opened on or after that
/// moment, not necessarily to the second.
///
/// Started once per account from `AccountContextImpl.init` (see the patch to
/// AccountContext.swift), same call site the old P2P poller used to start from.
public final class PampGramScheduledGiftRuntime {
    public static let shared = PampGramScheduledGiftRuntime()

    private let lock = NSLock()
    private var startedAccounts: Set<Int64> = []
    private var timers: [Int64: SwiftSignalKit.Timer] = [:]

    private init() {
    }

    public func start(accountKey: Int64, context: AccountContext) {
        self.lock.lock()
        if self.startedAccounts.contains(accountKey) {
            self.lock.unlock()
            return
        }
        self.startedAccounts.insert(accountKey)
        self.lock.unlock()

        PampGramPhantomGiftManager.materializeDueScheduledGifts(context: context)

        let timer = SwiftSignalKit.Timer(timeout: 30.0, repeat: true, completion: { [weak context] in
            guard let context else {
                return
            }
            PampGramPhantomGiftManager.materializeDueScheduledGifts(context: context)
        }, queue: Queue.mainQueue())
        timer.start()

        self.lock.lock()
        self.timers[accountKey] = timer
        self.lock.unlock()
    }
}
