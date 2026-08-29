load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "PampGramMessagesKit",
    module_name = "PampGramMessagesKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/TelegramUI/Components/PampGram/PampGramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
