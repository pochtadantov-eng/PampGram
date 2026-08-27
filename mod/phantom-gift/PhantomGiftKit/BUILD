load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "PhantomGiftKit",
    module_name = "PhantomGiftKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/UndoUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
