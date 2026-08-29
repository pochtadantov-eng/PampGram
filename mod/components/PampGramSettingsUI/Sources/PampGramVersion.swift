import Foundation

/// Single source of truth for the version string and changelog shown in the hub's hero row
/// and the "About PampGram" screen (tap the hero row to see it).
///
/// UPDATE THIS FILE ON EVERY RELEASE: bump `pampGramVersionString` and rewrite
/// `pampGramChangelogText` to describe what's actually in that build. This is the one place
/// both screens read from, so a single edit here keeps them in sync.
public let pampGramVersionString = "v1.0.0 (Stable)"

public let pampGramChangelogText = """
Вкладка «Подарок» при отправке подарка — тот же настоящий маркет Telegram (обычные и коллекционные подарки, реальные предложения других пользователей), но покупка из неё проходит визуально, без списания настоящих Stars/TON и без изменения владельца лота.

Локальные балансы: показывает свои собственные Stars и TON/GRAM вместо настоящих — в отправке подарка, в настройках Telegram, на экранах «Мои звёзды»/«Мои GRAM».

Восстановление удалённых сообщений: если собеседник удаляет отправленное вам сообщение, оно остаётся в чате затемнённым, с пометкой корзины, — пока вы не удалите его сами.

Ghost: «Нечиталка» скрывает от собеседников прочтение, статус «в сети», набор текста и запись/отправку файлов; «Маскировка онлайна» держит статус «в сети» максимально постоянно.
"""
