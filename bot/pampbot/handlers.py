import logging
from dataclasses import dataclass, field
from html import escape

from aiogram import Bot, F, Router
from aiogram.exceptions import TelegramAPIError
from aiogram.filters import Command, CommandStart
from aiogram.filters.callback_data import CallbackData
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import (
    BusinessConnection,
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    KeyboardButton,
    KeyboardButtonRequestUsers,
    Message,
    MessageOriginUser,
    OwnedGiftRegular,
    OwnedGiftUnique,
    ReplyKeyboardMarkup,
    ReplyKeyboardRemove,
)

from .config import Config
from .storage import ConnectionStore
from .texts import HOW_TO_CONNECT, OwnedGift, gift_details, gift_title, rights_text, upgrade_cost

log = logging.getLogger(__name__)

PAGE_SIZE = 8
PICK_USER_REQUEST_ID = 1


class Menu(CallbackData, prefix="m"):
    action: str


class GiftsPage(CallbackData, prefix="gp"):
    page: int


class GiftAction(CallbackData, prefix="ga"):
    action: str  # open | transfer | convert | upgrade | confirm_convert | confirm_upgrade | confirm_transfer
    index: int


class ReplyTo(CallbackData, prefix="rt"):
    chat_id: int


class Flow(StatesGroup):
    transfer_recipient = State()
    message_recipient = State()
    message_text = State()
    new_name = State()
    new_bio = State()


@dataclass
class GiftsCache:
    """Последняя загруженная страница подарков — кнопки ссылаются на индекс в ней."""

    offsets: list[str] = field(default_factory=lambda: [""])
    page: int = 0
    gifts: list[OwnedGift] = field(default_factory=list)
    has_next: bool = False
    total: int = 0


def main_menu() -> InlineKeyboardMarkup:
    rows = [
        [("🎁 Подарки", "gifts"), ("⭐ Баланс", "balance")],
        [("✉️ Написать", "write"), ("👤 Профиль", "profile")],
        [("🔐 Права", "rights")],
    ]
    return InlineKeyboardMarkup(
        inline_keyboard=[
            [InlineKeyboardButton(text=t, callback_data=Menu(action=a).pack()) for t, a in row]
            for row in rows
        ]
    )


def back_button(action: str = "home", text: str = "« Назад") -> list[InlineKeyboardButton]:
    return [InlineKeyboardButton(text=text, callback_data=Menu(action=action).pack())]


def pick_user_keyboard() -> ReplyKeyboardMarkup:
    return ReplyKeyboardMarkup(
        keyboard=[
            [
                KeyboardButton(
                    text="👤 Выбрать пользователя",
                    request_users=KeyboardButtonRequestUsers(
                        request_id=PICK_USER_REQUEST_ID, user_is_bot=False, max_quantity=1
                    ),
                )
            ],
            [KeyboardButton(text="Отмена")],
        ],
        resize_keyboard=True,
        one_time_keyboard=True,
    )


def extract_user_id(message: Message) -> int | None:
    """Получатель: выбран кнопкой, переслано его сообщение или введён числовой ID."""
    if message.users_shared and message.users_shared.users:
        return message.users_shared.users[0].user_id
    if isinstance(message.forward_origin, MessageOriginUser):
        return message.forward_origin.sender_user.id
    if message.text and message.text.strip().lstrip("-").isdigit():
        return int(message.text.strip())
    return None


def api_error_text(err: TelegramAPIError) -> str:
    msg = err.message
    hints = {
        "BUSINESS_CONNECTION_INVALID": "подключение недействительно — подключите бота заново",
        "BOT_ACCESS_FORBIDDEN": "у бота нет нужного права — включите его в настройках Telegram Business",
        "BALANCE_TOO_LOW": "на аккаунте не хватает звёзд",
        "STARGIFT_TRANSFER_TOO_EARLY": "этот подарок пока нельзя передать",
        "PEER_ID_INVALID": "получатель недоступен — он должен писать этому аккаунту за последние 24 часа",
    }
    for code, hint in hints.items():
        if code in msg:
            return f"❌ Ошибка: {hint}"
    return f"❌ Ошибка Telegram: {escape(msg)}"


def build_router(config: Config, store: ConnectionStore) -> Router:
    router = Router(name="pampbot")
    owner_only = F.from_user.id.in_(config.owner_ids)
    caches: dict[int, GiftsCache] = {}

    async def connection_or_warn(bot: Bot, user_id: int) -> str | None:
        conn_id = store.get(user_id)
        if conn_id is None:
            await bot.send_message(user_id, "Аккаунт ещё не подключён.\n\n" + HOW_TO_CONNECT)
        return conn_id

    # ---------- подключение ----------

    @router.business_connection()
    async def on_business_connection(conn: BusinessConnection, bot: Bot) -> None:
        user = conn.user
        if user.id not in config.owner_ids:
            # Чужие аккаунты не принимаем: бот управляет только аккаунтами владельцев.
            log.warning("Отклонено подключение от %s (%s)", user.id, user.username)
            return
        if conn.is_enabled:
            store.set(user.id, conn.id)
            await bot.send_message(
                user.id,
                "✅ Аккаунт подключён. Текущие права бота:\n\n" + rights_text(conn.rights),
                reply_markup=main_menu(),
            )
        else:
            store.remove(user.id)
            await bot.send_message(user.id, "⛔️ Аккаунт отключён от бота.")

    # ---------- меню ----------

    @router.message(CommandStart(), owner_only)
    @router.message(Command("menu"), owner_only)
    async def start(message: Message, state: FSMContext) -> None:
        await state.clear()
        if store.get(message.from_user.id) is None:
            await message.answer("Привет! Аккаунт ещё не подключён.\n\n" + HOW_TO_CONNECT)
            return
        await message.answer("Управление аккаунтом:", reply_markup=main_menu())

    @router.message(CommandStart())
    async def start_stranger(message: Message) -> None:
        await message.answer("Этот бот приватный.")

    @router.message(F.text.lower() == "отмена", owner_only)
    @router.message(Command("cancel"), owner_only)
    async def cancel(message: Message, state: FSMContext) -> None:
        await state.clear()
        await message.answer("Отменено.", reply_markup=ReplyKeyboardRemove())
        await message.answer("Управление аккаунтом:", reply_markup=main_menu())

    @router.callback_query(Menu.filter(F.action == "home"), owner_only)
    async def home(cb: CallbackQuery, state: FSMContext) -> None:
        await state.clear()
        await cb.message.edit_text("Управление аккаунтом:", reply_markup=main_menu())
        await cb.answer()

    @router.callback_query(Menu.filter(F.action == "rights"), owner_only)
    async def show_rights(cb: CallbackQuery, bot: Bot) -> None:
        conn_id = await connection_or_warn(bot, cb.from_user.id)
        await cb.answer()
        if conn_id is None:
            return
        try:
            conn = await bot.get_business_connection(conn_id)
        except TelegramAPIError as err:
            await cb.message.answer(api_error_text(err))
            return
        status = "активно" if conn.is_enabled else "отключено"
        await cb.message.edit_text(
            f"Подключение {status}.\n\n{rights_text(conn.rights)}",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[back_button()]),
        )

    @router.callback_query(Menu.filter(F.action == "balance"), owner_only)
    async def show_balance(cb: CallbackQuery, bot: Bot) -> None:
        conn_id = await connection_or_warn(bot, cb.from_user.id)
        await cb.answer()
        if conn_id is None:
            return
        try:
            balance = await bot.get_business_account_star_balance(conn_id)
        except TelegramAPIError as err:
            await cb.message.answer(api_error_text(err))
            return
        await cb.message.edit_text(
            f"⭐ Баланс аккаунта: <b>{balance.amount}</b> звёзд",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[back_button()]),
        )

    # ---------- подарки ----------

    async def render_gifts(cb: CallbackQuery, bot: Bot, page: int) -> None:
        user_id = cb.from_user.id
        conn_id = await connection_or_warn(bot, user_id)
        if conn_id is None:
            return
        cache = caches.setdefault(user_id, GiftsCache())
        if page == 0:
            cache.offsets = [""]
        page = max(0, min(page, len(cache.offsets) - 1))
        try:
            result = await bot.get_business_account_gifts(
                conn_id, offset=cache.offsets[page] or None, limit=PAGE_SIZE
            )
        except TelegramAPIError as err:
            await cb.message.answer(api_error_text(err))
            return

        cache.page = page
        cache.gifts = list(result.gifts)
        cache.total = result.total_count
        cache.has_next = bool(result.next_offset)
        if result.next_offset:
            del cache.offsets[page + 1 :]
            cache.offsets.append(result.next_offset)

        rows = [
            [InlineKeyboardButton(
                text=gift_title(g),
                callback_data=GiftAction(action="open", index=i).pack(),
            )]
            for i, g in enumerate(cache.gifts)
        ]
        nav = []
        if page > 0:
            nav.append(InlineKeyboardButton(text="◀️", callback_data=GiftsPage(page=page - 1).pack()))
        if cache.has_next:
            nav.append(InlineKeyboardButton(text="▶️", callback_data=GiftsPage(page=page + 1).pack()))
        if nav:
            rows.append(nav)
        rows.append(back_button())

        text = f"🎁 Подарки аккаунта: {cache.total}" if cache.total else "🎁 Подарков нет."
        await cb.message.edit_text(text, reply_markup=InlineKeyboardMarkup(inline_keyboard=rows))

    @router.callback_query(Menu.filter(F.action == "gifts"), owner_only)
    async def gifts_first_page(cb: CallbackQuery, bot: Bot, state: FSMContext) -> None:
        await state.clear()
        await cb.answer()
        await render_gifts(cb, bot, 0)

    @router.callback_query(GiftsPage.filter(), owner_only)
    async def gifts_page(cb: CallbackQuery, callback_data: GiftsPage, bot: Bot) -> None:
        await cb.answer()
        await render_gifts(cb, bot, callback_data.page)

    def cached_gift(user_id: int, index: int) -> OwnedGift | None:
        cache = caches.get(user_id)
        if cache is None or not 0 <= index < len(cache.gifts):
            return None
        return cache.gifts[index]

    def gift_keyboard(owned: OwnedGift, index: int, page: int) -> InlineKeyboardMarkup:
        def btn(text: str, action: str) -> InlineKeyboardButton:
            return InlineKeyboardButton(
                text=text, callback_data=GiftAction(action=action, index=index).pack()
            )

        rows = []
        if isinstance(owned, OwnedGiftUnique) and owned.can_be_transferred:
            rows.append([btn("📤 Передать", "transfer")])
        if isinstance(owned, OwnedGiftRegular):
            if owned.can_be_upgraded:
                rows.append([btn("✨ Улучшить", "upgrade")])
            if owned.convert_star_count:
                rows.append([btn(f"💱 Продать за {owned.convert_star_count}⭐", "convert")])
        rows.append([InlineKeyboardButton(text="« К списку", callback_data=GiftsPage(page=page).pack())])
        return InlineKeyboardMarkup(inline_keyboard=rows)

    @router.callback_query(GiftAction.filter(), owner_only)
    async def gift_action(
        cb: CallbackQuery, callback_data: GiftAction, bot: Bot, state: FSMContext
    ) -> None:
        user_id = cb.from_user.id
        owned = cached_gift(user_id, callback_data.index)
        if owned is None:
            await cb.answer("Список устарел, откройте подарки заново", show_alert=True)
            return
        action, index = callback_data.action, callback_data.index

        def confirm_kb(confirm_action: str) -> InlineKeyboardMarkup:
            return InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(
                    text="✅ Подтвердить",
                    callback_data=GiftAction(action=confirm_action, index=index).pack(),
                ),
                InlineKeyboardButton(
                    text="✖️ Отмена", callback_data=GiftAction(action="open", index=index).pack()
                ),
            ]])

        if action == "open":
            await state.clear()
            await cb.message.edit_text(
                gift_details(owned), reply_markup=gift_keyboard(owned, index, caches[user_id].page),
            )

        elif action == "transfer" and isinstance(owned, OwnedGiftUnique):
            await state.set_state(Flow.transfer_recipient)
            await state.update_data(gift_index=index)
            await cb.message.answer(
                f"Кому передать <b>{escape(gift_title(owned))}</b>?\n"
                "Выберите пользователя кнопкой, перешлите его сообщение или пришлите его ID.\n"
                "Получатель должен был писать этому аккаунту за последние 24 часа.",
                reply_markup=pick_user_keyboard(),
            )

        elif action == "convert" and isinstance(owned, OwnedGiftRegular):
            await cb.message.edit_text(
                f"Продать <b>{escape(gift_title(owned))}</b> за {owned.convert_star_count}⭐?\n"
                "Подарок исчезнет из профиля, отменить это нельзя.",
                reply_markup=confirm_kb("confirm_convert"),
            )

        elif action == "upgrade" and isinstance(owned, OwnedGiftRegular):
            cost = upgrade_cost(owned)
            price = "уже оплачено" if cost is None else f"{cost}⭐ с баланса аккаунта"
            await cb.message.edit_text(
                f"Улучшить <b>{escape(gift_title(owned))}</b> до уникального?\nСтоимость: {price}.",
                reply_markup=confirm_kb("confirm_upgrade"),
            )

        elif action == "confirm_convert" and isinstance(owned, OwnedGiftRegular):
            conn_id = await connection_or_warn(bot, user_id)
            if conn_id is None:
                return
            try:
                await bot.convert_gift_to_stars(conn_id, owned.owned_gift_id)
            except TelegramAPIError as err:
                await cb.message.answer(api_error_text(err))
            else:
                caches.pop(user_id, None)
                await cb.message.edit_text(
                    f"💱 Подарок продан за {owned.convert_star_count}⭐",
                    reply_markup=InlineKeyboardMarkup(inline_keyboard=[back_button("gifts", "« К подаркам")]),
                )

        elif action == "confirm_upgrade" and isinstance(owned, OwnedGiftRegular):
            conn_id = await connection_or_warn(bot, user_id)
            if conn_id is None:
                return
            try:
                await bot.upgrade_gift(
                    conn_id,
                    owned.owned_gift_id,
                    keep_original_details=True,
                    star_count=upgrade_cost(owned),
                )
            except TelegramAPIError as err:
                await cb.message.answer(api_error_text(err))
            else:
                caches.pop(user_id, None)
                await cb.message.edit_text(
                    "✨ Подарок улучшен!",
                    reply_markup=InlineKeyboardMarkup(inline_keyboard=[back_button("gifts", "« К подаркам")]),
                )

        elif action == "confirm_transfer" and isinstance(owned, OwnedGiftUnique):
            data = await state.get_data()
            recipient = data.get("recipient_id")
            conn_id = await connection_or_warn(bot, user_id)
            if conn_id is None or recipient is None:
                await cb.answer("Получатель не выбран", show_alert=True)
                return
            await state.clear()
            try:
                await bot.transfer_gift(
                    conn_id,
                    owned.owned_gift_id,
                    new_owner_chat_id=recipient,
                    star_count=owned.transfer_star_count or None,
                )
            except TelegramAPIError as err:
                await cb.message.answer(api_error_text(err))
            else:
                caches.pop(user_id, None)
                await cb.message.edit_text(
                    f"📤 {escape(gift_title(owned))} передан пользователю <code>{recipient}</code>",
                    reply_markup=InlineKeyboardMarkup(inline_keyboard=[back_button("gifts", "« К подаркам")]),
                )
        await cb.answer()

    @router.message(Flow.transfer_recipient, owner_only)
    async def transfer_recipient(message: Message, state: FSMContext) -> None:
        recipient = extract_user_id(message)
        if recipient is None:
            await message.answer("Не понял получателя. Выберите кнопкой, перешлите сообщение или пришлите ID.")
            return
        data = await state.get_data()
        index = data.get("gift_index", -1)
        owned = cached_gift(message.from_user.id, index)
        if not isinstance(owned, OwnedGiftUnique):
            await state.clear()
            await message.answer("Список устарел, откройте подарки заново.", reply_markup=ReplyKeyboardRemove())
            return
        await state.update_data(recipient_id=recipient)
        cost = owned.transfer_star_count
        await message.answer("Проверьте данные:", reply_markup=ReplyKeyboardRemove())
        await message.answer(
            f"Передать <b>{escape(gift_title(owned))}</b> пользователю <code>{recipient}</code>?\n"
            f"Стоимость: {'бесплатно' if not cost else f'{cost}⭐ с баланса аккаунта'}.\n"
            "Отменить передачу будет нельзя.",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(
                    text="✅ Передать",
                    callback_data=GiftAction(action="confirm_transfer", index=index).pack(),
                ),
                InlineKeyboardButton(
                    text="✖️ Отмена", callback_data=GiftAction(action="open", index=index).pack()
                ),
            ]]),
        )

    # ---------- сообщения ----------

    @router.callback_query(Menu.filter(F.action == "write"), owner_only)
    async def write_start(cb: CallbackQuery, state: FSMContext) -> None:
        await state.set_state(Flow.message_recipient)
        await cb.answer()
        await cb.message.answer(
            "Кому написать от имени аккаунта? Выберите пользователя, перешлите его сообщение или пришлите ID.\n"
            "Написать можно тем, кто писал аккаунту за последние 24 часа.",
            reply_markup=pick_user_keyboard(),
        )

    @router.message(Flow.message_recipient, owner_only)
    async def write_recipient(message: Message, state: FSMContext) -> None:
        recipient = extract_user_id(message)
        if recipient is None:
            await message.answer("Не понял получателя. Выберите кнопкой, перешлите сообщение или пришлите ID.")
            return
        await state.set_state(Flow.message_text)
        await state.update_data(recipient_id=recipient)
        await message.answer(
            f"Текст для <code>{recipient}</code> (или «Отмена»):", reply_markup=ReplyKeyboardRemove()
        )

    @router.callback_query(ReplyTo.filter(), owner_only)
    async def reply_start(cb: CallbackQuery, callback_data: ReplyTo, state: FSMContext) -> None:
        await state.set_state(Flow.message_text)
        await state.update_data(recipient_id=callback_data.chat_id)
        await cb.answer()
        await cb.message.answer(f"Ответ для <code>{callback_data.chat_id}</code> (или «Отмена»):")

    @router.message(Flow.message_text, owner_only, F.text)
    async def write_text(message: Message, state: FSMContext, bot: Bot) -> None:
        conn_id = await connection_or_warn(bot, message.from_user.id)
        if conn_id is None:
            return
        recipient = (await state.get_data())["recipient_id"]
        await state.clear()
        try:
            await bot.send_message(
                recipient, message.text, business_connection_id=conn_id, parse_mode=None
            )
        except TelegramAPIError as err:
            await message.answer(api_error_text(err))
            return
        await message.answer("✉️ Отправлено.", reply_markup=main_menu())

    if config.forward_messages:

        @router.business_message()
        async def incoming(message: Message, bot: Bot) -> None:
            owner = store.owner_of(message.business_connection_id)
            if owner is None or message.from_user is None or message.from_user.id == owner:
                return
            sender = message.from_user
            body = message.text or message.caption or f"[{message.content_type}]"
            await bot.send_message(
                owner,
                f"💬 <b>{escape(sender.full_name)}</b> (<code>{message.chat.id}</code>):\n{escape(body)}",
                reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                    InlineKeyboardButton(
                        text="↩️ Ответить", callback_data=ReplyTo(chat_id=message.chat.id).pack()
                    )
                ]]),
            )

    # ---------- профиль ----------

    @router.callback_query(Menu.filter(F.action == "profile"), owner_only)
    async def profile(cb: CallbackQuery) -> None:
        await cb.answer()
        await cb.message.edit_text(
            "Что изменить в профиле аккаунта?",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[
                [InlineKeyboardButton(text="Имя", callback_data=Menu(action="set_name").pack()),
                 InlineKeyboardButton(text="Био", callback_data=Menu(action="set_bio").pack())],
                back_button(),
            ]),
        )

    @router.callback_query(Menu.filter(F.action.in_({"set_name", "set_bio"})), owner_only)
    async def profile_edit(cb: CallbackQuery, callback_data: Menu, state: FSMContext) -> None:
        await cb.answer()
        if callback_data.action == "set_name":
            await state.set_state(Flow.new_name)
            await cb.message.answer("Новое имя (фамилию можно через «|», например «Иван|Петров»):")
        else:
            await state.set_state(Flow.new_bio)
            await cb.message.answer("Новое био (до 140 символов, «-» — очистить):")

    @router.message(Flow.new_name, owner_only, F.text)
    async def set_name(message: Message, state: FSMContext, bot: Bot) -> None:
        conn_id = await connection_or_warn(bot, message.from_user.id)
        if conn_id is None:
            return
        first, _, last = message.text.partition("|")
        await state.clear()
        try:
            await bot.set_business_account_name(conn_id, first.strip()[:64], last.strip()[:64] or None)
        except TelegramAPIError as err:
            await message.answer(api_error_text(err))
            return
        await message.answer("👤 Имя обновлено.", reply_markup=main_menu())

    @router.message(Flow.new_bio, owner_only, F.text)
    async def set_bio(message: Message, state: FSMContext, bot: Bot) -> None:
        conn_id = await connection_or_warn(bot, message.from_user.id)
        if conn_id is None:
            return
        bio = None if message.text.strip() == "-" else message.text.strip()[:140]
        await state.clear()
        try:
            await bot.set_business_account_bio(conn_id, bio)
        except TelegramAPIError as err:
            await message.answer(api_error_text(err))
            return
        await message.answer("👤 Био обновлено.", reply_markup=main_menu())

    return router
