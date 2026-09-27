from html import escape

from aiogram.types import BusinessBotRights, OwnedGiftRegular, OwnedGiftUnique

OwnedGift = OwnedGiftRegular | OwnedGiftUnique

HOW_TO_CONNECT = (
    "<b>Как подключить аккаунт</b>\n"
    "1. В @BotFather: <i>Bot Settings → Business Mode → Turn on</i>.\n"
    "2. В Telegram на своём аккаунте: <i>Настройки → Telegram Business → Чат-боты</i> "
    "(нужен Telegram Premium).\n"
    "3. Введите юзернейм этого бота и включите нужные права — для подарков: "
    "«Просмотр подарков и звёзд», «Передача и улучшение подарков», "
    "«Конвертация подарков в звёзды», «Передача звёзд».\n\n"
    "После этого бот пришлёт подтверждение, и управлять аккаунтом можно "
    "из этого чата с любого устройства."
)

RIGHT_NAMES = {
    "can_reply": "Ответ на сообщения",
    "can_read_messages": "Отметка сообщений прочитанными",
    "can_delete_sent_messages": "Удаление сообщений бота",
    "can_delete_all_messages": "Удаление всех сообщений",
    "can_edit_name": "Изменение имени",
    "can_edit_bio": "Изменение био",
    "can_edit_profile_photo": "Изменение фото профиля",
    "can_edit_username": "Изменение юзернейма",
    "can_change_gift_settings": "Настройки подарков",
    "can_view_gifts_and_stars": "Просмотр подарков и звёзд",
    "can_convert_gifts_to_stars": "Конвертация подарков в звёзды",
    "can_transfer_and_upgrade_gifts": "Передача и улучшение подарков",
    "can_transfer_stars": "Передача звёзд",
    "can_manage_stories": "Управление историями",
    "can_delete_outgoing_messages": "Удаление исходящих сообщений",
}


def rights_text(rights: BusinessBotRights | None) -> str:
    lines = []
    for field, name in RIGHT_NAMES.items():
        granted = bool(rights and getattr(rights, field, False))
        lines.append(f"{'✅' if granted else '▫️'} {name}")
    return "\n".join(lines)


def gift_title(owned: OwnedGift) -> str:
    if isinstance(owned, OwnedGiftUnique):
        g = owned.gift
        return f"{g.base_name} #{g.number}"
    emoji = owned.gift.sticker.emoji or "🎁"
    return f"{emoji} Подарок за {owned.gift.star_count}⭐"


def gift_details(owned: OwnedGift) -> str:
    lines = [f"<b>{escape(gift_title(owned))}</b>"]
    if owned.sender_user:
        sender = owned.sender_user
        name = escape(sender.full_name)
        lines.append(f"От: {name}" + (f" (@{sender.username})" if sender.username else ""))
    lines.append(f"На профиле: {'да' if owned.is_saved else 'скрыт'}")

    if isinstance(owned, OwnedGiftUnique):
        g = owned.gift
        lines.append(f"Модель: {escape(g.model.name)}")
        lines.append(f"Узор: {escape(g.symbol.name)}")
        lines.append(f"Фон: {escape(g.backdrop.name)}")
        if owned.can_be_transferred:
            cost = owned.transfer_star_count
            lines.append(f"Передача: {'бесплатно' if not cost else f'{cost}⭐'}")
        else:
            lines.append("Передача: недоступна")
        if owned.next_transfer_date:
            lines.append(f"Следующая передача после: {owned.next_transfer_date:%d.%m.%Y %H:%M} UTC")
    else:
        if owned.text:
            lines.append(f"Подпись: {escape(owned.text)}")
        if owned.convert_star_count:
            lines.append(f"Можно продать за: {owned.convert_star_count}⭐")
        if owned.can_be_upgraded:
            if owned.prepaid_upgrade_star_count:
                lines.append("Улучшение: уже оплачено")
            elif owned.gift.upgrade_star_count:
                lines.append(f"Улучшение: {owned.gift.upgrade_star_count}⭐")
    return "\n".join(lines)


def upgrade_cost(owned: OwnedGiftRegular) -> int | None:
    """Сколько звёзд нужно доплатить за улучшение (None — уже оплачено)."""
    if owned.prepaid_upgrade_star_count:
        return None
    return owned.gift.upgrade_star_count
