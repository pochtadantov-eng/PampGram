import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit

/// PampGram: why a bot-token login failed.
public enum AuthorizeWithBotTokenError {
    case generic
    case invalidToken
    case limitExceeded
}

/// PampGram: signs the unauthorized account in as a bot with its Bot API token
/// (`auth.importBotAuthorization`), then finishes exactly like a normal login does — same
/// authorized state, same account switch — so the app treats it as any other added account.
public func authorizeWithBotToken(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount, token: String) -> Signal<Void, AuthorizeWithBotTokenError> {
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    return account.network.request(Api.functions.auth.importBotAuthorization(flags: 0, apiId: account.networkArguments.apiId, apiHash: account.networkArguments.apiHash, botAuthToken: trimmedToken), automaticFloodWait: false)
    |> mapError { error -> AuthorizeWithBotTokenError in
        if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else if error.errorDescription.hasPrefix("ACCESS_TOKEN") {
            return .invalidToken
        } else {
            return .generic
        }
    }
    |> mapToSignal { result -> Signal<Void, AuthorizeWithBotTokenError> in
        return account.postbox.transaction { transaction -> Signal<Void, NoError> in
            switch result {
            case let .authorization(authorizationData):
                let user = TelegramUser(user: authorizationData.user)
                let state = AuthorizedAccountState(isTestingEnvironment: account.testingEnvironment, masterDatacenterId: account.masterDatacenterId, peerId: user.id, state: nil, invalidatedChannels: [])
                initializedAppSettingsAfterLogin(transaction: transaction, appVersion: account.networkArguments.appVersion, syncContacts: false)
                transaction.setState(state)
                return accountManager.transaction { transaction -> Void in
                    switchToAuthorizedAccount(transaction: transaction, account: account, isSupportUser: false)
                }
            case .authorizationSignUpRequired:
                return .complete()
            }
        }
        |> switchToLatest
        |> mapError { _ -> AuthorizeWithBotTokenError in
        }
    }
}
