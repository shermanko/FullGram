# Changelog — FullGram iOS

Все значимые изменения клиента **FullGram** и облачной инфраструктуры (`fullgram.korsakovx.workers.dev`).

---

## [1.7.0 Beta Test] — 2026-11-23

### Бета-тест, рамки FullGram и оптимизации
- **Закрытый бета-тест (`1.7.0 · Бета-тест`)**:
  - Генерация пригласительных ссылок (`https://.../beta/...`, `fullgram://beta?code=...`, `tg://fullgram/beta?code=...`) прямо в обоих Telegram-ботах (`/beta`, `/beta_list`, `/beta_revoke` и интерактивные кнопки).
  - Разблокировка функций FullGram по ссылке или ручному коду в Настройки → FullGram (без блокировки самого Telegram и аккаунта владельца).
- **Исправление отображения рамок FullGram (`fg_*.png`)**:
  - Оптимизированы все 50 анимированных APNG-рамок FullGram в 8-битный индексированный формат (`PLTE` + `tRNS`, 224×224, общий вес снижен с 43.9 МБ до ~6.4 МБ, улучшена видимость на светлых и тёмных темах).
  - Добавлен кэшируемый прокси `/assets/frames/*.png` в Cloudflare Worker, исправлена двойная загрузка превью/полной анимации, повторы при сбое сети и поддержка рамок в `AvatarComponent`.
- **Исправления багов и оптимизация сборки**:
  - Исправлены ошибки Swift 6 concurrency в `FullGramSettingsController`, `FullGramAIOverlay`, `FullGramMediaAudioScreens`, `FullGramPlayerOverlays` и синхронизация баланса в `FullGramEconomy`.
  - Оптимизирован CI-пайплайн (`assets/**` в `paths-ignore`, `ccache -s`, пререлизы Beta Test) и усилены проверки в `tools/ci_checks.py`.

---

## [1.6.0] — 2026-11-23

### Новые возможности
- **Роль «Спонсор+», ведущие бейджи и прозрачность удалённых**:
  - Уровень `sponsor_plus` на сервере и в клиенте с правом выдачи/снятия NFT любым пользователям прямо из профиля или по ID ([index.js](../tools/cloudflare-worker/src/index.js), [FullGramBadgeDeskController.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramBadgeDeskController.swift)).
  - Полупрозрачные удалённые сообщения в чате (`dimDeletedMessages`) и отображение бейджа FullGram в начале ника для владельцев купленного Telegram Premium, не перекрывая их звезду или эмодзи-статус.
- **Полная блокировка бота для посторонних**:
  - Вебхук Telegram-бота теперь отклоняет любые типы обновлений (`message`, `callback_query`, `inline_query`, `chat_member` и т.д.) не от `OWNER_USER_ID` и отвечает только в личном чате владельца.
- **Студия нарезки и склейки аудио перед отправкой**:
  - Новый контроллер `FullGramAudioTrimSpliceController` (обрезка начала/конца, вырезка середины на фрагменты, склейка нескольких аудиофайлов через `AVMutableComposition`, предпрослушивание и экспорт `.m4a`).
- **Запрос перед отправкой в выбранных чатах**:
  - Включение/отключение подтверждения «Вы точно хотите это отправить?» для отдельных чатов (через профиль собеседника/группы/канала) или для всех чатов.
- **Субтитры для видеокружков и видео**:
  - Временная сегментная разметка речи (`FullGramSpeechBleep.recognizeSubtitleCues`) с кэшированием и отображением синхронных субтитров поверх проигрываемого кружка.
- **Встроенный просмотрщик документов (`docx`, `xlsx`, `pdf`) и предпросмотр архивов (`zip`, `rar`)**:
  - `FullGramDocumentViewerController` (`PDFView` + поиск + миниатюры страниц для PDF; `WKWebView` + извлечение текста OOXML и поиск для `docx`/`xlsx`).
  - `FullGramArchivePreviewController` с разбором содержимого ZIP (Stored/Deflate и распаковкой выбранных файлов по тапу) и RAR v4/v5, статистикой и проверкой опасных расширений.
- **Переименование файла, авто-обрезка скриншотов, выбор обложки кружка и правка при пересылке**:
  - Переименование файла в 1 тап перед отправкой.
  - Автоматическое кадрирование iOS статус-бара и индикатора при отправке скриншотов (`autoCropScreenshots`).
  - Выбор кадра-обложки видеокружка перед отправкой (`FullGramVideoCircleCoverPickerController`).
  - Редактирование текста и исключение лишних сообщений при пересылке (`FullGramForwardEditController`, `FullGramForwardEditorStore`).
- **Очередь отправки и докачки файлов + оптимизация сборки и проекта**:
  - `FullGramTransferQueue` на базе `NWPathMonitor` для отслеживания сети, автовозобновления передач при восстановлении связи и очистки временных кэшей.
  - Оптимизация `.bazelrc` (`reuse_sandbox_directories`, `nobuild_runfile_links`, `experimental_remote_cache_async`) и расширение `ccache` в [build.yml](../.github/workflows/build.yml).

---

## [1.6.0] — 2026-11-21

### Исправленные баги
- **Рамка аватара на чате «Избранное» и системных иконках**:
  - `AvatarNode` теперь подавляет отображение рамки при наличии `overrideImage` (Избранное, Архив, Удалённые аккаунты) и в `setCustomLetters` ([AvatarNode.swift](../submodules/AvatarNode/Sources/AvatarNode.swift)).
- **Видимость косметики других пользователей**:
  - На сервере Cloudflare Worker добавлен `POST /auth/session`, загрузка кастомных рамок из фотоплёнки (`POST /cosmetics/upload-frame`, `GET /frames/<id>.png`), нормализация `peerId` во всех маршрутах и `ctx.waitUntil` ([index.js](../tools/cloudflare-worker/src/index.js)).
  - Клиент автоматически получает сессионный токен устройства через Keychain (`FullGramAdmin.ensureClientSession`), загружает кастомные рамки в облако и обновляет косметику при запуске и возвращении в приложение ([FullGramAdmin.swift](../submodules/Display/Source/FullGramAdmin.swift), [FullGramCosmetics.swift](../submodules/Display/Source/FullGramCosmetics.swift), [SharedAccountContext.swift](../submodules/TelegramUI/Sources/SharedAccountContext.swift)).
- **Локальный Telegram Premium и Эмодзи-статус**:
  - При включении только локального Premium скрыты элементы выбора/редактирования эмодзи-статуса в настройках, списке чатов и шапке профиля ([PeerInfoSettingsItems.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift), [ChatListController.swift](../submodules/ChatListUI/Sources/ChatListController.swift), [PeerInfoScreen.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift)).
- **Привязка эффекта профиля к шапке при скролле**:
  - `FullGramProfileEffectOverlayView` перенесён внутрь `backgroundBannerView` с фиксированной высотой, чтобы баннер профиля не смещался и не прыгал при прокрутке ([PeerInfoHeaderNode.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift)).
- **Загрузка, качество баннеров и превью рамок**:
  - Перерисованы все 50 кастомных APNG-рамок (`288×288`, 16 кадров, прозрачный центр) и зарегистрированы в клиенте ([generate_custom_cosmetics.mjs](../tools/generate_custom_cosmetics.mjs), [FullGramAvatarFrames.swift](../submodules/Display/Source/FullGramAvatarFrames.swift)).
  - Повышено разрешение декодирования баннеров профиля (`960px`, `60` кадров, Retina `.trilinear`), добавлен поиск первого видимого кадра (`isImageVisiblyOpaque`), предпочтение ambient-слоя `layer_1` и зеркало `raw.githubusercontent.com`.
  - Исправлен ключ анимации `"fg.apng"`, увеличены лимиты кэшей и добавлен индикатор загрузки на ячейках ([FullGramCosmeticScreens.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramCosmeticScreens.swift)).
- **Графический баг (щель) в аудиоплеере**:
  - Высота `historyFrameTopOverlayNode` под шапкой плейлиста синхронизирована с реальной высотой `topOverlayFrame.height` ([OverlayAudioPlayerControllerNode.swift](../submodules/TelegramUI/Sources/OverlayAudioPlayerControllerNode.swift)).

### Новые возможности и оптимизация
- **Система спонсоров FullGram**:
  - Владелец может назначать/снимать спонсоров в Desk бейджей профиля, админ-панели и командой `/sponsor` в Telegram-боте; спонсоры получают панель самообслуживания для настройки собственного бейджа (без ролей `creator`/`official`) и выдачи/удаления себе NFT без админ-токена ([FullGramBadgeDeskController.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramBadgeDeskController.swift), [FullGramNFTDeskController.swift](../submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/FullGramNFTDeskController.swift)).
- **Удобное переключение шрифтов**:
  - Убран текст-превью из строк списка шрифтов; при смене шрифта приложение автоматически перезагружает интерфейс и открывает сразу вкладку «Шрифты» ([Font.swift](../submodules/Display/Source/Font.swift), [FullGramAppearance.swift](../submodules/Display/Source/FullGramAppearance.swift), [AppDelegate.swift](../submodules/TelegramUI/Sources/AppDelegate.swift)).
- **Новые иконки и удаление чисто чёрных иконок**:
  - Обновлены основная и альтернативные иконки приложения (иконки маскота не затронуты), удалены чисто чёрные варианты иконок и тонированы тёмные системные иконки интерфейса.
- **Энергосбережение и оптимизация проекта / CI**:
  - Упрощено энергосбережение без профилей по устройствам и системного профиля, добавлено кэширование `FullGramPowerSaving` и поиск, кэш иконок меню, а также `ccache` + Bazel `--repository_cache` в [build.yml](../.github/workflows/build.yml).

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
