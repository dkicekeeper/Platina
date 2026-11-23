# Platina — руководство для Claude

iOS-приложение: трекер трофеев PlayStation (пока только PS5) с ИИ-ассистентом Плати, который
ведёт к платине и 100%. План, решения владельца и этапы — [docs/PLAN.md](docs/PLAN.md); перед
работой прочитай его.

## Как собрать

```bash
# Тесты PSNKit — работают и на Linux (в облачном контейнере тоже, если поставлен Swift 6):
cd ios/Packages/PlatinaKit && swift test

# Приложение — только на macOS, Xcode 26+:
cd ios && xcodegen generate && open Platina.xcodeproj
xcodebuild build -project ios/Platina.xcodeproj -scheme Platina \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Код часто пишется в контейнере на Linux, где SwiftUI не собирается. **Компилятор — CI**
(`.github/workflows/ios.yml`): на каждый пуш в `main` и `claude/**` тесты PSNKit на Linux,
сборка приложения и тесты пакета на macOS. Запушил — прочитай логи.

**TestFlight** — workflow `.github/workflows/testflight.yml` (ручной запуск; секреты ключа App
Store Connect уже в репозитории). Запускай его на `main` после зелёного CI, когда владелец
просит сборку или когда в `main` пришло то, что ему нужно проверить на телефоне; затем читай
логи загрузки. Подробности и подводные камни — [docs/testflight.md](docs/testflight.md).

## Устройство

```
ios/
├── project.yml                 XcodeGen; Platina.xcodeproj генерируется и не хранится в git
├── Config/Platina.xcconfig     хост сервера Плати; локальные значения — Config/Local.xcconfig (не в git)
├── Platina/                    приложение
│   ├── App/                    точка входа, AppModel (сессия PSN, синхронизация, сессии, Плати),
│   │                           RootView и вкладки, фоновое обновление
│   ├── Features/<Экран>/       Path, Library, Game (+ гайд), Trophy, Session, Plati, Profile,
│   │                           Onboarding, Share, Widgets (снимок для виджетов)
│   ├── Support/                цвета приложения, тексты
│   ├── Localizable.xcstrings   строки: русский (основной) и английский, плюс ключи DesignKit
│   └── Platina.entitlements    App Group (виджеты), iCloud (данные человека), пуши CloudKit
├── PlatinaWidgets/             расширение: Live Activity сессии, виджеты «Путь к платине» и
│                               «Последний трофей» (читают снимок из App Group)
└── Packages/PlatinaKit/
    ├── PSNKit                  единственная дверь в PSN: вход, токены (Keychain), клиент, модели
    ├── PlatinaCore             логика без UI и SwiftData: план синхронизации, время в играх,
    │                           статистика, фильтры библиотеки
    ├── PlatinaAssistant        клиент Плати: протокол, цикл разговора, сервер, App Attest, гайд
    ├── PlatinaShared           общее с расширением: атрибуты Live Activity, снимок виджетов
    └── PlatinaStore            SwiftData (кэш PSN + данные человека), LibrarySync,
                                SessionTracker, AssistantService, GuideService, AssistantToolkit
                                (только Apple; на Linux файлы в `#if canImport(SwiftData)`)
server/assistant/               сервер Плати: Cloudflare Worker (docs/assistant.md)
scripts/designkit_strings.py    ключи строк DesignKit → каталог приложения
```

PSNKit, PlatinaCore, PlatinaAssistant и PlatinaShared тестируются и на Linux (`swift test`);
PlatinaStore — на симуляторе в CI.

## PSN

- API неофициальный (как у psn-api, PSNAWP); всё обращение к нему — только в `PSNKit`.
- Вход (`SonyLoginSheet`): вход PlayStation Store в `WKWebView` (`PSNAuth.storeSignInURL`,
  веб-клиент Sony, UA Safari, данные не сохраняются). Когда Sony возвращает на
  `web.np.playstation.com/api/session/v1/session`, приложение отменяет переход и берёт `npsso`
  из cookie (или со страницы `ssocookie`), затем меняет его на код клиента PlayStation App
  (`authorize` с cookie `npsso` → редирект `com.scee.psxandroid.scecompcall://redirect?code=…`)
  и токены. Запасной путь — токен NPSSO вручную. URL-scheme PlayStation App приложение **не
  регистрирует**.
- Токены — в Keychain (`KeychainTokenStore`), на наш сервер они не уходят.
- Страница входа клиента PlayStation App (`/sonyacct/signin` с нашим `client_id`) у части людей
  не грузится нигде, даже в Safari («Время соединения с сервером истекло»; у пользователей GOG
  Galaxy то же). Вход на store.playstation.com (веб-клиент) у них работает, и после него
  `ssocookie` отдаёт `npsso`: поэтому вход приложения идёт через Store. На playstation.com
  Safari может не оставить `npsso`. Сервис входа Store возвращает только на playstation.com
  (другой `redirect_uri` — `400`), поэтому системное окно Safari (`webAuthenticationSession`)
  для него не годится: ему некуда вернуться.
- Где-то DNS подменяет адрес `m.np.playstation.com` (адреса не Akamai, TLS обрывается,
  `URLError -1200`): у владельца на Wi-Fi, на сотовой сети всё работает. Поэтому
  `URLSessionTransport` при таком сбое переключает приложение на свой зашифрованный DNS
  (`NameResolution`: DNS-over-HTTPS Google, для всего приложения) и повторяет запрос один раз;
  сработавший режим запоминается.
- Тесты `PSNKit` идут на JSON-фикстурах (`Tests/PSNKitTests/Fixtures`) через `MockTransport`;
  сеть в тестах не трогается. Фикстуры собраны по моделям psn-api и сверены с настоящими
  ответами из [andshrew/PlayStation-Trophies](https://github.com/andshrew/PlayStation-Trophies/blob/master/docs/APIv2.md)
  (psn-api ошибается: `trophyLevel` — число, не строка). Модели читают поля терпимо там, где
  PSN и библиотеки расходятся.
- Game Help (подсказки PlayStation к трофеям): `PSNGameHelp.swift`, GraphQL
  `graphql/v1/op` с сохранёнными хэшами приложения PlayStation и заголовком
  `apollographql-client-name`; в приложении — `GameHelpService` (кэш на запуск) и
  `GameHelpSection` на экране трофея. Ошибка (например, Sony сменила хэш) — раздел молча не
  показывается.
- Сбои запросов PSN и синхронизации пишутся в системный журнал (`PSNLog`, категория `PSN` и
  `Sync`): пути и коды ошибок, без токенов. Первым делом проси у владельца эти строки из
  консоли Xcode.
- Запросы PSN бережём: у Sony неопубликованные лимиты. Без лишних повторов и опросов.

## Данные

- Два хранилища в одном `ModelContainer` (`LibraryStore.makeContainer`): **кэш** (игры, трофеи,
  группы, профиль, связи «игра → список трофеев») — его можно пересобрать синхронизацией, и
  версия, которая не может его открыть, создаёт его заново; **данные человека**
  (`GamePlanRecord`, дальше заметки и сессии) — никогда не удаляются, готовы к iCloud: у всех
  полей значения по умолчанию, нет `.unique`, на игры ссылаются по id.
- Экраны читают через `@Query`; пишет только `LibraryStore` (главный контекст).
- `LibrarySync`: каждая синхронизация — профиль и список игр (3 запроса), трофеи только
  изменившихся игр в пределах бюджета (`SyncPlanner.defaultRequestBudget`), время в играх.
  Сама — не чаще раза в 10 минут, если не ждут игры; открытая игра догружается сразу
  (`refreshGame`).

## Плати

Контракт приложения и сервера — [docs/assistant.md](docs/assistant.md). Инструменты на телефоне
— `AssistantToolkit` (имена в `AssistantProtocol.Tool`, определения на сервере в
`server/assistant/src/tools.ts`: менять вместе). История разговора только дописывается.
Без хоста сервера (`PLATINA_ASSISTANT_HOST`) Плати выключен, остальное работает.

## DesignKit

Весь интерфейс — на DesignKit (`https://github.com/dkicekeeper/DesignKit`, точная версия в
`ios/project.yml`). Правила — ниже, в блоке DesignKit, и в `docs/components.md` DesignKit.
Чего не хватает — добавляется в DesignKit отдельным PR, а не рисуется в приложении.

- Акцент: `DesignKitTheme.accent = PlatinaColors.accent` в `PlatinaApp.init()`, тот же цвет в
  `AccentColor`.
- Поверхности — серая заливка, не стекло: `DesignKitTheme.surface = .fill` там же (DesignKit
  8.12.0, решение владельца 2026-11-23: меньше Liquid Glass). Карточки, секции, чипы, плитки и
  плашки иконок — серые на белой странице; кнопки, таб-бар и поле чата остаются стеклом. Фон
  экранов — `AppColors.Background.base` (белый): на сером фоне карточки сольются. Своя серая
  фигура внутри карточки — `.surfaceNeutral1` / `.surfaceNeutral2`, не `Background.neutral1`.
- Цвета металлов трофеев — `TrophyType.color` в `Support/PlatinaColors.swift` (кандидат в
  токены DesignKit).
- DesignKit не несёт строк: после подъёма версии DesignKit запусти
  `python3 scripts/designkit_strings.py --designkit <DesignKit> --ru <Dalada>/ios/Dalada/Localizable.xcstrings --ru <Tenra>/Tenra/ru.lproj/Localizable.strings`.

## Правила кода

- Swift 6, iOS 26+, только iPhone.
- Каждая строка интерфейса — ключ в `Localizable.xcstrings` на двух языках (`ru`, `en`).
- Ошибки PSN показываются через `PSNError.userMessage`; истёкшая сессия ведёт на экран входа
  (`AppModel.handle`).
- Скрытые трофеи не спойлерим: название и описание — по нажатию.

<!-- designkit:agents:start -->
<!-- From DesignKit 8.12.0, docs/agents.md. Do not edit here: the DesignKit update workflow rewrites it. -->

## DesignKit for an app's agent

The short version of DesignKit's rules for a session working in Tenra or Dalada (8.9.0, benchmark
round 4: Astryx's `init`, which writes such a block into an app's AGENTS.md). Each app's
**DesignKit update** workflow puts this file into the app's CLAUDE.md between the
`designkit:agents` markers when it moves the pin (`scripts/sync_agents_block.py`), so it always
matches the version the app builds with. Do not edit the block in the app; change it here.

### Look a component up

- `docs/components.md` in the DesignKit checkout: one entry per component (`### Name`), what it is
  for, its initialisers, rules, do and don't, its skeleton. `docs/components.json` is the same as
  data. The full rules: `docs/design-system.md`.
- The Gallery app (TestFlight) shows every component with its parameters and states.
- A missing component goes to DesignKit by PR (CLAUDE.md, "Porting a component"); the app keeps a
  thin adapter over its model.

### The rules

1. Tokens, never raw values: `AppColors`, `AppTypography`, `AppSpacing`, `AppRadius`,
   `AppIconSize`, `AppAnimation` / `AppMotion`. Status text is `AppColors.Status.*Text` (4.5:1);
   a colour of your own as text is `AppColors.readable(color)` on `AppColors.pale(color)`; a grey
   shape of your own inside a card is `.surfaceNeutral1` / `.surfaceNeutral2`.
2. Every symbol is an `Icon`: a glyph under 44 pt, a tile on its plate from 44 pt. iOS's own bars,
   menus, tabs and segments, and a symbol inside a line of text, stay `Image` / `Label`.
3. A form or settings list is `FormSection` cards of `UniversalRow(_:icon:accessory:)`; the
   section draws the dividers. No system `Form`. The cards are Liquid Glass, or a grey fill when
   the app sets `DesignKitTheme.surface = .fill` (8.12.0); no glass or grey of your own.
4. A list of things a person keeps is a `CardList`: a tap opens, a long press shows Edit and
   Delete, the toolbar selects, reorders and adds. No swipe actions.
5. Every view that shows data has a skeleton (`<Name>Skeleton`); a list that loads pages ends in
   `LoadMoreFooter`.
6. An outcome that comes and goes is spoken: `MessageBanner` and the failure states of
   DesignKit's components do it; an app's own outcome calls `AccessibilityAnnouncer.announce(_:)`.
7. Motion through DesignKit (`AppMotion` springs, `.popIn`, `.riseIn`, effects); everything stops
   under Reduce Motion and `.designKitMotion(false)`.

### What a screen needs → the component

| Need | Component |
|---|---|
| A button | `DSButton` (`.dsButton` for a custom label) |
| A form, settings | `FormSection` + `UniversalRow(accessory: .toggle / .menu / .picker / .date / .stepper / .slider / .navigation / .action / .info)` |
| A list of the person's things | `CardList` (a card per item, or rows in one card), `ItemRow` + `MetaLine` |
| Pick from a long list, with search and "Create" | `SearchablePicker` |
| Pick from a few | `UniversalRow(accessory: .menu)`, `ChipPicker`, `SegmentedPicker` |
| A section title | `SectionHeader` |
| Money | `FormattedAmountText`, `AmountRow`, `AmountInput` / `CurrencyAmountInput`, `LiveAmountText` |
| When something happened, how long it runs | `RelativeTime` (`.relative`, `.elapsed`, `.clock`) |
| Explain a number | `InfoTip` / `.infoTip(_:title:)` |
| A value over what was tapped, a coachmark | `Tooltip`, `.spotlight` |
| A state that lasts | `StatusBanner` |
| An outcome that comes and goes | `MessageBanner` |
| Nothing here, or loading failed | `EmptyState` (`.error` with Retry) |
| Loading | the component's `<Name>Skeleton`, `.skeletonReveal` when it gives way |
| A chat | `MessageBubble` (`markdown:`, `time:`, `status:`), `ConversationDivider`, `MessageComposer`, `TypingIndicator`, `SuggestionChips` |
| Charts | `LineChart`, `BarChart`, `ChartSwitcher`, `Sparkline`, `OrbChart`, `CalendarHeatmap` (docs/charts.md) |
| Progress | `ProgressRing`, `LinearProgressBar`, `LimitProgressCard`, `StepTracker` |
| People | `Avatar`, `AvatarGroup`, `PersonRow`, `CommentRow` |
| Photos | `RemotePhoto`, `PhotoTile`, `PhotoGrid`, `PhotoCarousel`, `PhotoViewer` |
| Edit sheet | `EditSheetContainer`, `EditableHero`, `AmountEntrySheet` |
| A moment of success | `.celebration`, `.completionMoment` |

### Check before pushing

```bash
python3 <DesignKit>/scripts/designkit_lint.py all --source <the app's Swift folders>
```

`tokens` finds raw design values, swipe actions and the system `Form` (against the app's
`scripts/design-lint-baseline.json`); `section-rows` finds section rows without their own padding
or divider inset. A major DesignKit version: `scripts/migrate.py --from <old> --to <new> --source …`
rewrites what it can and leaves `TODO(DesignKit X.0)` where `docs/migration-X.0.md` needs a person.

<!-- designkit:agents:end -->
