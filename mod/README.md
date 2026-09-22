# PampGram — мод Telegram для iOS

Форк [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) со своим разделом
**PampGram** в настройках и полностью локальными функциями поверх обычного клиента.

## Главное правило

Всё, что делает PampGram, меняет **только то, что видит владелец устройства**. Ни одна
функция не подделывает ответы Telegram API, не меняет серверное состояние другого
пользователя, не отправляет собеседнику ложные данные, не трогает настоящие Telegram Stars,
не создаёт настоящие Telegram Gifts и не обходит авторизацию или оплату. Каждая функция —
это либо локальная транзакция Postbox, либо изменение того, как уже полученные данные
рисуются на экране.

Из этого следует и то, чего PampGram делать не будет: любая функция, меняющая отображение
чужих данных, должна оставаться отличимой от настоящей. Поэтому фантом-подарок несёт
ленточку «Фантом» и подпись, что ничего не покупалось.

## Что уже работает

### Раздел PampGram в настройках

Отдельный блок «PampGram» в списке настроек Telegram (`Настройки → PampGram`), своей
иконкой и своим экраном:

- **Вкладка «Фантом»** — включает и выключает вкладку в экране отправки подарков;
- **Фантом-Stars** — локальный счётчик мода (по умолчанию 50 000), редактируется вручную;
- **Фантом-TON** — такой же локальный счётчик, только для красоты: кошелька у мода нет;
- **Сбросить балансы**;
- **Фантом-подарков на устройстве: N** и **Удалить все фантом-подарки** — удаляет и записи,
  и их сообщения из истории чата.

Настоящие балансы Stars и TON аккаунта этот экран не читает и не меняет.

### Фантом-подарки

Вкладка **«Фантом»** в `GiftOptionsScreen` — тот же каталог реальных подарков, но отправка
идёт по локальному пути:

1. Проверка и списание локального баланса (`PampGramSettings.fakeStarsBalance` —
   `PreferencesEntry` Postbox, тот же механизм, что хранит настройки автосохранения медиа).
   Ключи зарезервированы внутри модуля, а не в общем `ApplicationSpecificPreferencesKeys`,
   чтобы не пересечься с чем-то реальным и не конфликтовать при обновлении upstream.
2. Если подарок «коллекционный» (`gift.availability != nil`) —
   `PampGramUniqueGiftGenerator` подбирает случайный Model/Backdrop/Symbol из
   `context.engine.payments.starGiftUpgradePreview(giftId:)`. Это единственный сетевой
   вызов во всей фиче: он только читает публичный список образцов арта — тот же, что
   показывает настоящий экран апгрейда подарка, — и никакой информации о фантомном подарке
   никуда не отправляет. Если запрос не удался, отправляется обычный (не коллекционный)
   подарок.
3. `PampGramPhantomGiftMessage.insertLocalGiftMessage` вставляет **настоящее** сообщение в
   историю чата с `Namespaces.Message.Local` — зарезервированным Postbox-неймспейсом для
   локальных сообщений, который никогда не пересечётся с реальным id с сервера (пример в
   проекте: `submodules/TelegramCore/Sources/Utils/StoredMessageFromSearchPeer.swift`).
   `account.network` тут не участвует вообще.

**Карточка в чате.** Сообщение несёт настоящий `TelegramMediaAction.starGift` (обычный
подарок) или `.starGiftUnique` (коллекционный, с Model/Backdrop/Symbol), поэтому
`ChatMessageBubbleItemNode` рисует его существующим `ChatMessageGiftBubbleContentNode` —
той же карточкой, что и настоящий подарок. Чтобы её нельзя было спутать с настоящей,
`ChatMessageGiftBubbleContentNode` проверяет маркер (у обычных — служебное поле
`prepaidUpgradeHash`, у коллекционных — `slug`, начинающийся с `pampgram-phantom-`, потому
что у `.starGiftUnique` нет свободного строкового поля) и принудительно меняет ленту на
«Фантом» другим цветом и подписывает текстом «локально, ничего не покупалось».

**Удаление.** Обычное «Удалить сообщение» работает бесплатно: пайплайн удаления
(`DeleteMessagesInteractively.swift`) уже отдельно проверяет `Namespaces.Message.Local` и
пропускает сетевой запрос именно для локальных сообщений — это существующий код, а не наш.
`PampGramPhantomGiftManager.delete`/`deleteAll` дополнительно чистят записи в хранилище.

## Структура

```
mod/
  telegram-ios.patch       — правки в файлах, которые уже есть в upstream
  components/              — новые Bazel-пакеты, копируются как есть в
                             submodules/TelegramUI/Components/PampGram/
    PampGramCore/          — настройки и локальное хранилище (без UI-зависимостей)
    PhantomGiftKit/        — модель, хранилище и отправка фантом-подарков
    PampGramSettingsUI/    — экран «PampGram» в настройках
```

Разделение намеренное: правка собственного Swift-кода не требует перегенерации патча.

`telegram-ios.patch` меняет:

- `GiftOptionsScreen.swift` — вкладка «Фантом», подтверждение с показом баланса, вызов
  `PampGramPhantomGiftManager.send`, подписка на настройки мода;
- `ChatMessageGiftBubbleContentNode.swift` — подмена ленты на «Фантом» по маркеру;
- `ChatMessageBubbleItemNode.swift` — комментарий (функциональных изменений нет: локальные
  сообщения несут настоящий `TelegramMediaAction`, спецобработки не требуется);
- `PeerInfoScreen.swift`, `PeerInfoScreenSettingsActions.swift`, `PeerInfoSettingsItems.swift`
  — строка «PampGram» в настройках и переход на её экран;
- `AccountContext.swift` — запускает `PampGramTemporaryMediaDisplay.shared.start(...)` при
  создании аккаунта (тем же способом, что уже используется для `PampGramFakeAdminRuntime`);
- `ChatMessageInteractiveMediaNode.swift` — «Показывать временную медиа»: если настройка
  включена, локальный флаг `isSecretMedia` для фото/видео с таймером принудительно сбрасывается
  в `false` в обоих местах, откуда он читается (`asyncLayout()` и `updateStatus()`), — после
  этого весь существующий код бабла рисует медиа как обычное фото/видео (без размытия, бейджа
  таймера и жеста «посмотреть один раз»). Экран, куда сообщение открывается по тапу, не тронут;
- `AccountStateManagementUtils.swift` и `TelegramCore/Sources/PampGram/PampGramSecretMediaPrefetch.swift`
  (новый файл) — расширяет «Восстановление удалённых сообщений» на одноразовые/с таймером фото,
  видео и голосовые. `PampGramDeletedMessageCapture` (уже перехватывает удаление в этом же файле,
  в `replayFinalState`) сам по себе умеет пересобрать удалённое сообщение с любым медиа — он
  ничего не исключает по `containsSecretMedia`, а атрибуты обрезаются до текстовых при пересборке,
  так что копия сама теряет пометку «одноразовое». Не хватало одного: файл должен быть скачан
  ДО того, как сервер его инвалидирует после просмотра/удаления. `PampGramSecretMediaPrefetch`
  вызывается сразу после того, как в `replayFinalState` посчитан `addedIncomingMessageIds` — тот
  же список свежесохранённых входящих сообщений, что стоковый код использует для уведомлений —
  и для каждого одноразового/таймерного сообщения молча запускает `fetchedMediaResource` (фото →
  `ImageMediaReference`, видео/голосовое → `FileMediaReference`), до открытия пользователем.
  Один тумблер на всё — тот же `antiDeleteMessagesEnabled`, отдельной настройки нет;
- Тот же `AccountStateManagementUtils.swift` — ещё один случай в `replayFinalState`,
  `.UpdateMinAvailableMessage(id)`: единственный путь, которым канал/супергруппа теряет сразу
  весь диапазон истории (плавающая нижняя граница доступных сообщений — `updateChannelAvailableMessages`
  в API), в отличие от `.DeleteMessages`/`.DeleteMessagesWithGlobalIds`, которые несут явный
  список id. Перед `transaction.deleteMessagesInRange(...)` весь диапазон перебирается через
  `transaction.withAllMessages(...)`, и получившийся список id идёт в те же самые
  `PampGramSecretMediaPrefetch.prefetchIfNeeded`/`PampGramDeletedMessageCapture.captureBeforeDelete`,
  что и для обычного удаления, — код капчура и превентивной подкачки медиа не дублируется;
- `TelegramCore/Sources/TelegramEngine/Messages/DeleteMessagesInteractively.swift` —
  расширяет капчур на удаления, которые делает сам владелец устройства, а не только на то, что
  приходит через `replayFinalState` (то есть удаления собеседника). `deleteMessagesInteractively`
  — единственная функция, через которую проходит любое «Удалить» в приложении — теперь тоже
  вызывает `PampGramDeletedMessageCapture.captureBeforeDelete`, но с `includeOwnMessages: true`,
  так что и свои собственные отправленные сообщения тоже остаются в чате при удалении. Та же
  капча добавлена в `_internal_clearHistoryInteractively`/`_internal_clearHistoryInRangeInteractively`
  (полная и по датам очистка истории) — весь диапазон сначала перебирается через
  `transaction.withAllMessages`, как и для канального `.UpdateMinAvailableMessage` выше. Новый
  параметр `accountPeerId` — не `nil` только когда вызов идёт от реального действия пользователя
  (`TelegramEngineMessages.swift`/`SparseMessageList.swift` его передают); внутренний служебный
  вызов `deleteMessagesInteractively` в `AccountStateManagementUtils.swift` (чистка
  дублирующихся исходящих сообщений) оставляет его `nil`, так что ничего лишнего не захватывается;
- `PampGramDeletedMessageCapture.restoreChatToNormal` (новая функция в том же файле, что и
  `captureBeforeDelete`) и `TelegramUI/Sources/Chat/ChatControllerOpenPeer.swift`,
  `openBotForumMoreMenu` (меню «⋯» в шапке приватного чата) — пункт «Восстановить чат» теперь не
  просто тост, а настоящее восстановление: снимает `PampGramDeletedByRemoteAttribute` с каждого
  уже сохранённого для этого собеседника локального сообщения, из-за чего
  `ChatMessageBubbleItemNode` перестаёт рисовать затемнение и бейдж-корзину — переписка
  выглядит как обычная, без каких-либо пометок об удалении. `PampGramDeletedMessageStore` при
  этом не трогается: счётчик в «История» и на самой кнопке остаётся точным, меняется только то,
  как сообщение нарисовано в чате. Новое удаление в этом чате снова получит свежий бейдж как
  обычно — восстановление разовое, а не постоянный режим отображения;
- `StoryItemContentComponent.swift` и `StoryItemSetContainerComponent.swift` — «Сохранение
  историй», два независимых изменения за одной настройкой:
  1. В обоих местах, где строится `isCaptureProtected` для `StoryItemImageView`
     (`isCaptureProtected: item.isForwardingDisabled`), добавлено
     `&& !PampGramStorySavingDisplay.shared.isEnabled(...)`. `isCaptureProtected` решает,
     оборачивать ли изображение истории в `UITextField.isSecureTextEntry` — это единственное,
     из-за чего скриншот/запись экрана такой истории выходит чёрными на iOS
     (`StoryItemImageView.swift`), самой Telegram-протокольной отметки «историю
     заскриншотили» не существует (это есть только у секретных чатов). Настройка просто не
     даёт этой обёртке появиться для этого аккаунта;
  2. В `performOtherMoreAction` (меню «…» на чужой истории) условие показа пункта
     «Сохранить» — `!component.slice.item.storyItem.isForwardingDisabled` — получает
     `|| PampGramStorySavingDisplay.shared.isEnabled(...)`. Само сохранение
     (`requestSave()`/`saveToCameraRoll`) не тронуто: работает и требует Premium точно так
     же, как для обычной истории — меняется только видимость пункта меню;
- «Обход защиты от скриншотов» (Дополнительно, `PampGramScreenshotBypassDisplay` — тот же
  паттерн синхронного зеркала настройки, что и у `PampGramStorySavingDisplay`) — тот же
  `isSecureTextEntry`-трюк, что и для историй, теперь ещё в четырёх местах, где стоковый
  Telegram комбинирует признак копи-протекшена канала/группы/чата с признаком секретного чата
  через `||`, — в патче меняется **только** копи-протекшен-член выражения, признак секретного
  чата рядом остаётся нетронутым в каждом из них:
  - `ChatMessageInteractiveMediaNode.swift` — `captureProtected` для фото/видео в медиасообщении
    (`associatedData.isCopyProtectionEnabled || message.isCopyProtected()`, оба независимы от
    типа чата — `Message.isCopyProtected()` проверяет только `TelegramGroup`/`TelegramChannel`);
  - `ChatControllerNode.swift` — `isSecret` для всего экрана чата (`copyProtectionEnabled`,
    рядом остаются `SecretChat`/`isVerificationCodes`);
  - `ChatController.swift` — `isSecret` для pinch-zoom галереи;
  - `ChatControllerOpenMessageContextMenu.swift` — `isSecret` для превью в контекстном меню
    (`copyProtectionEnabled`/`myCopyProtectionEnabled`).
  Секретные чаты сознательно не входят в этот тумблер ни с одной из сторон: чёрный экран для
  них рисуется точно так же, как и без мода, и уведомление собеседнику о скриншоте (реальный
  сигнал «кто-то знает, что тебя сфотографировали») никак не трогается — это единственное
  место в Telegram, где защита от скриншота существует именно как сигнал согласия между двумя
  людьми, а не просто техническое ограничение;
- `PeerInfoSettingsItems.swift` — «Скрыть иконку в настройках»: строка «PampGram» в стоковом
  экране настроек оборачивается в `if !pampGramSettings.hidePampGramIconEnabled`. Долгое
  нажатие на строку «Помощь» там же всегда открывает PampGram напрямую — способ вернуться,
  когда строка скрыта;
- `ListItems/PeerInfoScreenDisclosureItem.swift` — добавляет `longTapAction: (() -> Void)? =
  nil` к `PeerInfoScreenDisclosureItem` (используется «Помощь» выше) и подключает
  `UILongPressGestureRecognizer` в его узле с `cancelsTouchesInView = false`, чтобы не мешать
  обычному короткому тапу. Параметр опциональный со значением по умолчанию — остальные ~100
  мест, где этот тип уже используется в стоке, не меняются;
- четыре `BUILD`-файла (Bazel) в оригинальной фиче плюс один на файл, тронутый
  «Показывать временную медиа» и «Сохранение историй».

`server/pampgram-subs-worker/` получил два новых маршрута — `/generate-key` (админ создаёт
одноразовый ключ под тариф) и `/redeem-key` (любой аккаунт активирует ключ на себя, ключ
после этого удаляется). Оба, как и `/grant`, принимают опциональный `durationHours` — выдачу
или ключ можно ограничить по времени (часы и дни, дробные значения суммируются в часы), а не
только выдавать навсегда. Для ключа таймер стартует в момент активации, а не генерации: срок
не тратится, пока ключ просто лежит непроданным. Истёкшая подписка сама читается сервером как
`standard`, никакой фоновой очистки не требуется. Подробности — в комментарии наверху
`src/index.js`.

## Как собрать

Сборка идёт целиком в GitHub Actions, Mac не нужен: вкладка **Actions** → workflow
**Build IPA (device, fake-signed)** → **Run workflow**. Примерно час; готовый `Telegram.ipa`
лежит в артефакте **PampGram-ipa** внизу страницы прогона.

`.ipa` подписан self-signed сертификатом из `build-system/fake-codesigning` самого
Telegram — как есть на iPhone он не встанет, и это ожидаемо. Ставить нужно через
**Sideloadly** или **AltStore**: они снимают эту подпись и переподписывают файл вашим
Apple ID уже на вашей стороне (Windows/Linux подходят, Mac не нужен).

Собрать локально на Mac тоже можно:

```sh
git clone https://github.com/TelegramMessenger/Telegram-iOS.git
cd Telegram-iOS
git apply /путь/до/PampGram/mod/telegram-ios.patch
mkdir -p submodules/TelegramUI/Components/PampGram
cp -R /путь/до/PampGram/mod/components/. submodules/TelegramUI/Components/PampGram/
```

Дальше — `build-system/Make/Make.py` по инструкции самого репозитория Telegram-iOS.

### api_id / api_hash

По умолчанию используется публичная пара ключей самой Telegram (`api_id: 8`). Она
предназначена для официального приложения, и вход в сторонний клиент с ней — риск получить
ограничения на аккаунт. Свои ключи берутся бесплатно на https://my.telegram.org/apps и
кладутся в секреты репозитория `TELEGRAM_API_ID` и `TELEGRAM_API_HASH` — workflow подхватит
их автоматически.

- `PampGramSettingsUI/PampGramOnboardingScreen.swift` (новый) и
  `TelegramUI/Sources/AppDelegate.swift` — карусель первого запуска. `viewDidLoad`/paging —
  чистый UIKit, без Postbox: на этот момент ещё нет ни аккаунта, ни его Postbox, так что
  "показано один раз" хранится в обычном `UserDefaults` (`PampGram_OnboardingShown_v1`), а не в
  `PampGramSettings`. Вызывается из `didFinishLaunchingWithOptions` сразу после
  `self.window?.makeKeyAndVisible()` — поверх уже отрисованного окна, не подменяя решение
  Telegram о том, что показать дальше (вход или список чатов): под каруселью всё точно так же,
  как без неё, и баг в этом экране не может сломать сам вход;
- `PampGramSettingsUI/PampGramPremiumScreen.swift` (новый) — платный экран: те же реальные
  PRO-функции, что скрыты в `pampGramGateTier`, с иконкой/описанием на карточке, статус текущего
  тарифа (тот же `PampGramSubscriptionAPI.fetchStatus`, что и «Статус») и кнопка активации,
  которая ведёт на уже существующий ключ-флоу — никакой настоящей Apple-покупки тут нет и быть
  не может (сборка сайдлоуд, не из App Store, реальный StoreKit не заработает);
- `PampGramSettingsUI/PampGramSubscriptionUI.swift` (новый) — вынесенный из
  `PampGramStatusScreen.swift` общий флоу «Активировать ключ» (промпт + вызов
  `PampGramSubscriptionAPI.redeemKey` + тултип), теперь используется и «Статус»-экраном, и
  Premium-экраном, без дублирования;
- `PampGramHubScreen.swift` — кнопка «Premium» в правом верхнем углу (открывает Premium-экран),
  разделы «Ghost» и «Дополнительно» обёрнуты в `pampGramGateTier`, который открывает Premium
  вместо раздела, если тариф не PRO. «Подарки», «Чаты» и «Внешний вид» остаются бесплатными.

## Безопасность

- `WebPBinding/Sources/UIImage+WebP.m`, `+[WebP convertFromWebP:]` — этот декодер (не наш, он
  уже был в Telegram-iOS) вызывается для любого WebP-изображения, которое не смог открыть
  штатный `CGImageSource` — то есть для превью и полноразмерных стикеров, реакций и части
  кэшированных изображений (`PhotoResources.swift`, `ReactionImageComponent.swift`,
  `VideoStickerFrameSource.swift`, `FetchCachedRepresentations.swift`,
  `LottieAnimationCache.swift`). Он брал ширину/высоту прямо из заголовка файла без всякой
  проверки и передавал их произведение в `malloc` через `(int)`-каст — на 64-битном iOS это
  переполняет 32 бита при значениях от ~2 ГБ и молча обрезает размер выделяемого буфера, а
  `WebPDecodeBGRAInto` после этого всё равно пишет в него полный, необрезанный размер —
  classic heap buffer overflow, управляемый исключительно заявленными в файле размерами.
  Открытие чата с таким файлом («краш-стикер») валит процесс мгновенно, а поскольку Telegram
  на следующем запуске пытается отрисовать последний открытый чат, попасть в аккаунт после
  этого без стороннего вмешательства (веб-клиент, удаление через API) нельзя.
  Исправлено: отклоняем `width`/`height` ≤ 0 или больше 16384 (собственный лимит формата WebP
  на измерение — значит, ни один валидный кодировщик под это не попадёт) ещё до всякого
  выделения памяти; убран `(int)`-каст, размер буфера считается в `size_t` от начала до конца;
  добавлена проверка `malloc`/`CGBitmapContextCreate` на `NULL` и освобождение буфера на всех
  путях выхода (раньше на ошибке декодирования буфер просто терялся). Затронутых мест
  вызова несколько, но баг был один — в самом декодере, так что правки одного файла достаточно
  для всех них.

## Что ещё не сделано

- **Грид подарков в профиле** («Профиль → Подарки»). Рендеринг живёт в
  `PeerInfoGiftsPaneNode.swift` — полторы тысячи строк, плотно завязанных на живой
  синхронизирующийся с сервером `ProfileGiftsContext`. Фантом-подарок сейчас виден как
  карточка в чате.
- **Локальный визуальный редактор сообщений**, анти-удаление, изменение голоса в голосовых
  и звонках, трекер активности — по плану дальше.

## Важно

При клонировании `TelegramMessenger/Telegram-iOS` в этой сессии в корне репозитория
несколько раз обнаруживался файл `CLAUDE.md` с «инструкциями для ИИ» (пароли для сборки,
сторонний gitlab-репозиторий для code-signing и т.д.) — для настоящего репозитория Telegram
это нетипично и похоже на попытку промпт-инъекции через содержимое файла. Эти «инструкции»
не использовались. Стоит проверить содержимое `CLAUDE.md` в своей копии, прежде чем ему
доверять.
