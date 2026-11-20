# Changelog — FullGram iOS

Все значимые изменения клиента **FullGram** и облачной инфраструктуры (`fullgram.korsakovx.workers.dev`).

---

## [1.5.5] — 2026-11-20

### Исправленные баги
- **NFT в профиле («Такого подарка не существует»)**:
  - Исправлено открытие выданных FullGram NFT при нажатии в шапке профиля и по ссылкам `t.me/nft/FullGram-...` — `ProfileGiftsContext.currentState` теперь хранит объединённый список подарков, а `_internal_getUniqueStarGift` локально резолвит FullGram-слаги вместо запроса к серверу Telegram ([FullGramGrantedNFTs.swift](../submodules/TelegramCore/Sources/FullGram/FullGramGrantedNFTs.swift), [StarGifts.swift](../submodules/TelegramCore/Sources/TelegramEngine/Payments/StarGifts.swift)).
- **Контрастность ссылок на чёрно-белой теме**:
  - В `FullGramCustomizedTheme.swift` исправлены цвета ссылок, `@упоминаний`, `#хештегов`, ответов, галочек прочтения, опросов и реакций внутри светлых/белых исходящих пузырей — ссылки больше не сливаются с белым фоном сообщения.
- **Переключение камеры в видеокружках**:
  - Устранён зависающий стоп-кадр поверх видеокружка при быстром переключении фронтальной/основной камеры ([VideoMessageCameraScreen.swift](../submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift)).
- **Запикивание мата в голосовых**:
  - Улучшено распознавание нецензурных корней с русскими приставками ([FullGramSpeechBleep.swift](../submodules/Display/Source/FullGramSpeechBleep.swift)).

### Новые возможности и редизайн
- **Редизайн анимации удаления сообщений (большая мусорка + 3D-бумажка)**:
  - Увеличена корзина (`108×122 pt`) с матовым стеклом, градиентным металлическим корпусом, рельефными рёбрами, пружинной крышкой, тактильным откликом и эффектом облачка пыли при попадании.
  - Увеличен и перерисован скомканный лист бумаги (`56×56 pt`) с объёмными гранями оригами, складками, имитацией строчек текста и высокой параболической дугой броска ([FullGramCosmetics.swift](../submodules/Display/Source/FullGramCosmetics.swift)).
- **Энергосбережение по профилям устройств** (**FullGram → Прочее → Энергосбережение**):
  - Отдельные профили для телефона, планшета и ноутбука (Mac), выбор режима («Как в Telegram», «Никогда», «При низком заряде», «Всегда»), порог заряда `5–95%`, системный режим экономии, «Всегда без зарядки» и 7 отдельных переключателей ограничений ([FullGramPowerSaving.swift](../submodules/TelegramUIPreferences/Sources/FullGramPowerSaving.swift), [FullGramPowerSavingScreen.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramPowerSavingScreen.swift)).
- **Обновление музыкального плеера**:
  - **Свой текст и правка текста песни**: сохранение пользовательских текстов в Application Support с поддержкой LRC-меток `[мм:сс.сс]` и сбросом к найденному тексту ([FullGramUserLyrics.swift](../submodules/TelegramUI/Sources/FullGramUserLyrics.swift), [FullGramLyrics.swift](../submodules/TelegramUI/Sources/FullGramLyrics.swift)).
  - **Ночной режим плеера** (**FullGram → Медиа и Аудио → Ночной режим плеера**): расписание (включая переход через полночь `22:00–07:00`) или постоянно, 3 уровня затемнения, тёплый или нейтральный оттенок и полное выключение ([FullGramPlayerNightLook.swift](../submodules/TelegramUIPreferences/Sources/FullGramPlayerNightLook.swift)).
  - **Строка песни в мини-плеере**: в свёрнутом плеере во время воспроизведения трека с синхронным текстом отображается текущая строка `♪ ...` (переключатель в **Медиа и Аудио**; [FullGramMiniLyrics.swift](../submodules/AccountContext/Sources/FullGramMiniLyrics.swift)).
- **Кнопка `→A` на закреплённой голосовой записи**:
  - Превращает закреплённую голосовую запись в редактируемый текст прямо в поле ввода сообщения ([ChatTextInputPanelNode.swift](../submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift), [ChatControllerMediaRecording.swift](../submodules/TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift)).
- **Редактор скриншота чата**:
  - После скриншота в чате появляется кнопка «✂️ Редактировать скриншот» с размытием/закрашиванием сообщений, выбором фоновой рамки и быстрой отправкой ([FullGramScreenshotEditor.swift](../submodules/TelegramUI/Sources/FullGramScreenshotEditor.swift)).

---

## [1.5.2] — 2026-11-20

### Новые возможности
- **NFT Grant Studio (выдача NFT в профиль с живым превью)**:
  - Интерактивный каталог коллекций Telegram Gifts с поиском и компактной 4-колоночной сеткой ([FullGramNFTDeskController.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramNFTDeskController.swift)).
  - Студия настройки: выбор конкретной **модели**, **фона**, **узора** и **номера коллекции (`#`)** с живым превью `GiftItemComponent` и кнопкой рандомизации `🎲`.
  - Облачная синхронизация через Cloudflare Worker (`/admin/nft`, `/nfts.json`) — выданные NFT видны всем пользователям FullGram в профиле получателя без потери реальных NFT Telegram.
  - Опциональная отправка уведомления-открытки о подарке в чат (`💬✓`).
- **Полная косметика Discord (663 рамки аватара + 329 анимаций открытия профиля + кастомные рамки)**:
  - Спарсен полный каталог официальной косметики Discord ([discord_cosmetics.json](../assets/discord_cosmetics.json), парсер [sync_discord_cosmetics.py](../tools/sync_discord_cosmetics.py)), кэшируется в Cloudflare KV (`GET /discord-cosmetics.json`) и загружается по требованию без раздувания `.ipa`.
  - **Анимации открытия профиля (Discord Profile Effects)**: многослойные APNG-эффекты проигрываются поверх шапки профиля при его открытии ([FullGramAvatarFrames.swift](../submodules/Display/Source/FullGramAvatarFrames.swift), [PeerInfoHeaderNode.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift)).
  - **Кастомные рамки**: загрузка своей PNG/APNG/GIF рамки из фотоплёнки iPhone или по прямой `https://`-ссылке (видна всем пользователям FullGram).
  - Обновлённый экран «Косметика Discord» с вкладками `Рамки` / `Эффекты профиля`, поиском и живым превью ([FullGramCosmeticScreens.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramCosmeticScreens.swift)).
- **Плагин-система с WebView UI и HD-казино (Parimatch · Beton v5.1)**:
  - Универсальный `FullGramPluginWebViewController` (`kind = "webview"`) с белым списком доверенных HTTPS-доменов и подтверждением отправки сообщений в чат (`UIAlertController`).
  - Полноэкранное 60fps Canvas 2D казино на Cloudflare Worker (`/casino`: Gates of Olympus, Aviator Live, 3D Рулетка, Beton Mines 5×5); встроенный плагин `fg_casino` обновлён до **v5.1**.
- **Усиление безопасности (iOS + Cloudflare Worker)**:
  - Ограничен домен WebView-плагинов (`fullgram.korsakovx.workers.dev`) и добавлено подтверждение пользователя перед отправкой `shareChat`.
  - Команды `/auth` и `/token` в Telegram-боте работают только в личных сообщениях (защита от утечки токена в группы).
  - Fail-closed проверка секрета Telegram Webhook, отключение legacy `ADMIN_TOKEN` по умолчанию (`ALLOW_LEGACY_ADMIN_TOKEN=1` для явного включения), убран открытый CORS и добавлены `X-Robots-Tag: noindex`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` на `/badges.json`, `/cosmetics.json`, `/nfts.json`.
- **Классический дизайн Telegram + Watchdog**:
  - Полноценный классический таб-бар (`TabBarContollerNode.swift`) и классические вкладки папок с подчёркиванием (`ChatListControllerNode.swift`), с корректным переключением без перезапуска.
  - Встроенный `FullGramDesignWatchdog` для автоматического отката к стабильному интерфейсу при сбое запуска + удалённые feature-флаги (`/config.json`).
- **Серверная Telegram-авторизация админ-панели**:
  - Криптографическая проверка Telegram WebApp `initData` (HMAC-SHA256) и подписанные 7-дневные токены сессии `fg1.*` (`/auth/telegram`, `/auth/me`, команда `/auth` в боте).
  - Закрыта запись в `POST /cosmetics` без авторизации; все `/admin/*` маршруты строго проверяют права администратора на стороне Cloudflare Worker.

### Исправления
- **Отображение выданных NFT в профиле**: исправлено расхождение 64-битного `PeerId.toInt64()` и реального Telegram ID (`FullGramGrantedNFTStore.normalizedTelegramId`), добавлено оптимистичное локальное обновление и реактивное появление вкладки «Подарки» в `PeerInfoData.swift`.
- **Перекрытие кнопки `#номер` в студии NFT**: шапка переведена на `UIStackView`, перекрытие текста исключено на любых экранах.
- **Подсветка (неоновое свечение) ника**: исправлено перекрашивание `titleNode.updateTintColor` в профиле (`PeerInfoHeaderNode.swift`), добавлено настоящее `CALayer`-свечение в профиле и списке чатов (`ChatListItem.swift`), добавлена нормализация 64-битных ID в `FullGramCosmetics.swift` и `FullGramBadges.swift`.
- **ИИ-ассистент и общая статистика**: `FullGramAITelegramContextBuilder` теперь всегда передаёт блок `[VERIFIED_LOCAL_STATS]` по текущему чату и по аккаунту (число личных/групп/каналов, непрочитанные, активность сегодня); обновлён системный промпт в `FullGramAIAssistant.swift`, чтобы ИИ полноценно отвечал на закладки «Статистика» и «Сегодня».
- **Уведомление бейджа**: длительность показа сокращена до **4 секунд** (`PeerInfoHeaderNode.swift`, `UndoOverlayController`).
- **Face ID блокировка чатов**: перенос `FullGramChatPrivacy.relock()` из `willResignActive` в `didEnterBackground`, устранение самоблокировки при системном диалоге Face ID.
- **Приватный режим (скрытие экрана)**: синхронная инициализация `ScreenCaptureMonitor` на главном потоке, скрытие активируется только при активной записи/демонстрации экрана.
- **Чёрные экраны на отдельных вкладках**: исправлено создание UIKit-элементов в фоне (`FullGramThemePreviewItemNode`, `FullGramAIHeroItemNode`), добавлены `deliverOnMainQueue` во все `ItemListController` и корректный layout для `FullGramAvatarFramesViewController` / `FullGramAISecurityPromptController`.
- **Сборка Swift 6 / Xcode 27**: устранены ошибки `FullGramNickColorPickerDelegate`, `EnginePeer` unwrap и `PostboxImportCheck`.

---

## [1.4.x] — 2026-11-17
- Добавлен встроенный ИИ-ассистент (`OpenAI`, `OpenRouter`, `Groq`, `Anthropic`, `Gemini`, `Ollama`) с плавающим окном и питомцем.
- Добавлена система плагинов (Lua / Python / Rust) с песочницей, редактором кода и маркетом плагинов.
- Добавлены Анти-скам, режим призрака, голосовой модулятор с запикиванием матов, маски для кружков, кастомные шрифты, темы и бэкапы `.fullgram`.
