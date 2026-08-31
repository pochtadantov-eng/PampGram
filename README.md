# PampGram

PampGram — мод для Telegram-iOS. GitHub Actions скачивает актуальный Telegram-iOS, применяет патчи PampGram, копирует Swift/Bazel-компоненты и собирает device IPA.

## Разделы

- **Подарки** — визуальные подарки, Stars/TON/рубли, покупка Stars, история/статистика, рейтинг, анонимный номер, коллекция/маркет.
- **Чаты** — функции копирования/пересылки/автоудаления, удалённые и изменённые сообщения, локальные сообщения, перевод.
- **Ghost** — privacy, скриншоты, screen capture/background и блокировка чатов.
- **Геолокация** — выбор подменённой точки на карте.
- **Голос / Медиа** — voice changer голосовых и передача файлов.
- **Внешний вид** — пресеты и визуальные параметры интерфейса.
- **Дополнительно** — блокировка рекламы и профильные настройки.
- **Админ-панель / Статус** — подписки PampGram.

Подробный список: `FEATURE-MAP-RU.md`.

## Файлы сборки
- `mod/telegram-ios.patch` — основной патч.
- `mod/telegram-ios-features.patch` — дополнительные интеграции.
- `mod/components/` — PampGramCore, PampGramSettingsUI и PhantomGiftKit.
- `mod/overrides/PampGramVoiceChanger.swift` — актуальный DSP voice changer.

Визуальные/локальные функции не создают реальные Telegram/Fragment/TON операции или права.

## v8.2 build fix
MapKit is now linked through a small `objc_library` dependency instead of the unsupported `sdk_frameworks` attribute on `swift_library`.
