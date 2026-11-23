# Сборка на iPhone и TestFlight

## Сборка на свой iPhone (Mac с Xcode 26+)

```bash
brew install xcodegen          # один раз (без Homebrew — xcodegen.zip со страницы релизов XcodeGen)
cd ios
xcodegen generate              # Platina.xcodeproj генерируется, в git его нет
open Platina.xcodeproj
```

После `git pull` запускайте `xcodegen generate` снова, если в проекте появились или пропали
файлы; иначе хватает ⌘B.

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

Workflow `.github/workflows/testflight.yml`, запуск вручную (Actions → TestFlight → Run).

Один раз:

1. В App Store Connect создайте приложение с bundle id `dakacom.Platina`.
2. Создайте API-ключ App Store Connect (Users and Access → Integrations, роль App Manager или
   Admin) и добавьте секреты репозитория: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (текст
   файла `.p8`).
3. Необязательно: переменная репозитория `PLATINA_ASSISTANT_HOST` — хост сервера Плати.
4. Первую сборку проще отправить из Xcode (Product → Archive → Distribute): так Apple один раз
   зарегистрирует App Group и iCloud-контейнер. Дальше workflow подписывает сам.
