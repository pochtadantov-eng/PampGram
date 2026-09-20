load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "PampGramMediaKit",
    module_name = "PampGramMediaKit",
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
        "//submodules/SaveToCameraRoll",
        "//submodules/TelegramUI/Components/PampGram/PampGramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
