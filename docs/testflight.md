# Сборка на iPhone и TestFlight

## Сборка на свой iPhone (Mac с Xcode 27)

```bash
scripts/setup.sh               # один раз: ставит XcodeGen (Homebrew), включает git-хуки, генерирует проект
open ios/Platina.xcodeproj
```

`Platina.xcodeproj` генерируется из `ios/project.yml` и в git его нет. После `setup.sh` git сам
пересобирает его после `pull`, `merge`, `rebase` и смены ветки, если изменился `project.yml`
(версия DesignKit, настройки) или появились и пропали файлы (`.githooks`,
`scripts/xcodegen-if-needed.sh`); Xcode подхватывает новый проект сам. Проект, сгенерированный до
смены версии DesignKit или до новых файлов, не соберётся: обе цели (приложение и виджеты) первым
делом проверяют его (`scripts/check-xcode-project.sh`) и останавливают сборку с ошибкой «…pins
DesignKit X…» или «…generated before these files came…» и подсказкой, что запустить. Без этой
проверки старый проект падал на непонятном «Cannot find 'CompleteStepIntent' in scope». Вручную: `cd ios && xcodegen generate`; если Xcode всё равно показывает
старую версию DesignKit — File → Packages → Reset Package Caches.

1. В Xcode у целей **Platina** и **PlatinaWidgets** (Signing & Capabilities) — ваша команда
   (`SY2L2VMQP7` уже стоит), «Automatically manage signing». Xcode сам зарегистрирует
   App Group `group.dakacom.Platina` и iCloud-контейнер `iCloud.dakacom.Platina`.
2. Плати (необязательно): впишите хост сервера в `ios/Config/Local.xcconfig` (файл не в git):
   ```
   PLATINA_ASSISTANT_HOST = platina-assistant.<аккаунт>.workers.dev
   ```
   Как поднять сервер — `server/assistant/README.md`. Без сервера всё остальное работает,
   вкладка Плати объясняет, что сервер не настроен.
3. Выберите iPhone и запустите (⌘R).

Что проверить в первую очередь:

- вход в PSN через страницу Sony. Если она пишет «Время соединения с сервером истекло»:
  «Войти по токену NPSSO» — войти в PlayStation Store в Safari, в том же Safari открыть
  страницу токена, скопировать ответ целиком и вставить;
- первая синхронизация: игры PS5 появляются, трофеи догружаются партиями;
- сессия: старт из игры, Live Activity на экране блокировки, «Проверить трофеи»;
- виджеты «Путь к платине» и «Последний трофей» на домашнем экране;
- Плати: вопрос в чате, гайд на экране игры.

Если что-то не грузится: в консоли Xcode (⇧⌘C) найдите строки `PSN`, `Sync failed` и
`Name resolution` — в них запрос и код ошибки, без токенов.

## TestFlight из GitHub Actions

Workflow `.github/workflows/testflight.yml`, запуск вручную (Actions → TestFlight → Run). Его
запускает и Claude (инструмент GitHub `actions_run_trigger`, ветка `main`) — после того как
CI на `main` зелёный.

Сделано один раз (2026-11-23):

1. Приложение в App Store Connect с bundle id `dakacom.Platina`.
2. API-ключ App Store Connect с ролью **Admin** (Users and Access → Integrations) и секреты
   репозитория `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (текст файла `.p8` целиком). С этой
   ролью workflow сам создаёт сертификат и профили для публикации: первая сборка из Xcode не
   понадобилась.

Необязательно: переменная репозитория `PLATINA_ASSISTANT_HOST` — хост сервера Плати.

Что знать:

- Номер сборки — `10 + номер запуска workflow`; версия — `MARKETING_VERSION` в `ios/project.yml`.
- iPhone и iPad (этап 10): `TARGETED_DEVICE_FAMILY: "1,2"` у проекта, приложения и виджетов; у
  iPad — все четыре ориентации (`UISupportedInterfaceOrientations~ipad` в Info.plist), иначе App
  Store Connect отказывает (90474), и многозадачность без них не работает. На Mac с Apple silicon
  приложение для iPad запускается как есть («Designed for iPad»; отключается в App Store Connect,
  если понадобится).
- Отметка о шифровании (`ITSAppUsesNonExemptEncryption = NO`) в Info.plist: вопрос о
  шифровании в TestFlight не задаётся.
- Сборки идут в Xcode 27 (iOS 27 SDK): образ GitHub `xcode-27` (public preview) и
  `xcode-version: "27"` — последний стабильный 27.x. С апреля 2027 App Store Connect
  принимает только такие.
- iCloud в сборках TestFlight работает с продакшен-окружением CloudKit: схему из
  Development нужно выкатить в CloudKit Console (Deploy Schema Changes), иначе свои
  данные не синхронизируются (приложение при этом работает). Development узнаёт тип записи или
  поле, только когда Debug-сборка впервые сохранит такую запись, поэтому сначала — схема
  целиком: в Xcode схема **Platina CloudKit Schema** → Run на устройстве с iCloud
  (`-InitializeCloudKitSchema`, `App/CloudKitSchema.swift`), в консоли — «CloudKit schema:
  done»; затем в CloudKit Console проверить типы `CD_…` (все модели данных человека из
  `LibraryStore.userModels`) и выкатить. Так же — после каждой новой модели или поля.
- Плати: хост сервера — в `ios/Config/Platina.xcconfig`; переменная репозитория
  `PLATINA_ASSISTANT_HOST`, если задана, его заменяет (пустая — нет).
