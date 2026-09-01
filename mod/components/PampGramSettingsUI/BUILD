load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

objc_library(
    name = "PampGramAppleFrameworks",
    sdk_frameworks = [
        "MapKit",
    ],
)

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
        ":PampGramAppleFrameworks",
        "//submodules/Display",
        "//submodules/AsyncDisplayKit",
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
        "//submodules/OverlayStatusController",
        "//submodules/TelegramUI/Components/PampGram/PampGramCore",
        "//submodules/TelegramUI/Components/PampGram/PhantomGiftKit",
        "//submodules/AppBundle",
    ],
    visibility = [
        "//visibility:public",
    ],
)
