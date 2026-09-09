import Foundation
import Postbox
import SwiftSignalKit

public final class PampGramAdBlockManager {
    public static let shared = PampGramAdBlockManager()

    private var settingsDisposable: Disposable?
    public var enabled = false

    private init() {}

    public func start(postbox: Postbox) {
        guard settingsDisposable == nil else { return }

        settingsDisposable = (PampGramCore.settingsSignal(postbox: postbox)
        |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
            self?.enabled = settings.blockAds
        })
    }
}
