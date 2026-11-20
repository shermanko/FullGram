# Changelog — FullGram iOS

Все значимые изменения клиента **FullGram** и облачной инфраструктуры (`fullgram.korsakovx.workers.dev`).

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
