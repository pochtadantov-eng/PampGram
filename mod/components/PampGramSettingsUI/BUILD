load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "PampGramSettingsUI",
    module_name = "PampGramSettingsUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/MergeLists",
        "//submodules/Postbox",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramUIPreferences",
        "//submodules/ItemListUI",
        "//submodules/PresentationDataUtils",
        "//submodules/AccountContext",
        "//submodules/PromptUI",
        "//submodules/UndoUI",
        "//submodules/TelegramUI/Components/PampGram/PampGramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
