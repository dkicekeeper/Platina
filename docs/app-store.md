# Platina в App Store: что подготовлено и что сделать владельцу

Этап 11 (docs/PLAN.md §9). Здесь — черновики для App Store Connect и писем. Решения и отправка —
за владельцем: юридически значимые тексты стоит прочитать самому (или юристу) перед публикацией.

## 1. Что приложение делает с данными (основа для политики и App Privacy)

| Данные | Где живут | Кто видит |
|---|---|---|
| Вход в PSN: токены доступа и обновления | только Keychain этого устройства (`KeychainTokenStore`) | никто, кроме приложения; на наш сервер не уходят |
| Трофеи, игры, профиль PSN | кэш на устройстве (SwiftData), запрашиваются у Sony напрямую с телефона | Sony (как у любого клиента PSN) |
| Свои данные: статусы игр, сессии, заметки, разговоры с Плати, прогресс прохождений | на устройстве и в личном iCloud человека (CloudKit, приватная база) | только сам человек |
| Сообщения Плати (текст, фото экрана для «Где я?»), данные, которые Плати попросил у телефона (трофеи, игры) | идут на наш сервер (Cloudflare Worker) и в Anthropic (Claude) только для ответа; сервер их не хранит и не пишет в лог | Anthropic обрабатывает по своим правилам для коммерческого API (срок хранения и обучение — проверить по текущей политике Anthropic перед публикацией) |
| Гайды и прохождения игр | кэш на сервере (Cloudflare KV, 30 дней) — общий для всех, без данных человека | все пользователи приложения |
| Ключ App Attest и счётчики запросов | сервер (KV): id ключа и число вызовов за день/месяц | никто; нужен, чтобы сервер отвечал только настоящему приложению и держал лимиты |
| Друзья PSN и их открытые списки трофеев (1.1) | кэш на устройстве, запрашиваются у Sony с телефона | Sony |
| Уведомления о трофеях (1.1, только если включены): свои токены сервера (зашифрованы), номер аккаунта PSN, push-токен, язык, снимок списков трофеев | сервер (Durable Object на установку), стирается при выключении, выходе, отказе Sony или 410 от APNs | никто; Sony (запросы), Apple (пуши) |

Нет: аналитики, рекламы, трекинга, сторонних SDK, аккаунтов в нашем сервисе, продажи данных.

## 2. App Privacy (ответы в App Store Connect, черновик)

Осторожный вариант (данные уходят с устройства на сервер и в Anthropic, хоть и не хранятся у нас):

- **Data Used to Track You**: нет.
- **Data Linked to You**: нет.
- **Data Not Linked to You**:
  - *User Content → Photos or Videos* — фото экрана для «Где я?»; цель: App Functionality.
  - *User Content → Other User Content* — сообщения Плати; цель: App Functionality.
  - *Usage Data → Product Interaction*? — не собираем: счётчики лимитов — по ключу App Attest, без
    профиля; отметить «нет».
  - *Identifiers → Device ID* — ключ App Attest не является id устройства Apple; отметить «нет»
    (если ревью спросит — пояснить, что это ключ подписи запросов).
- PSN-данные (трофеи, профиль) берутся у Sony с телефона и на наш сервер уходят только кусками,
  которые Плати попросил для ответа, — это входит в «Other User Content».

### С 1.1 (уведомления о трофеях)

Когда выйдет 1.1, владелец меняет App Privacy: **Data Linked to You → Identifiers → User ID**
(номер аккаунта PSN, который сервер хранит для уведомлений о трофеях; только у тех, кто их
включил); цель — App Functionality; не для трекинга. Остальное — как выше. Политика на Pages уже
описывает это (раздел 4).

## 3. Политика конфиденциальности и поддержка

Опубликованы на GitHub Pages, как у Dalada и Tenra (решение владельца 2026-11-25): `docs/public`
→ workflow `Pages` на каждый пуш в `main`, который их меняет.

- Privacy Policy URL: https://dkicekeeper.github.io/Platina/privacy-policy.html
- Support URL: https://dkicekeeper.github.io/Platina/support.html
- Marketing URL (по желанию): https://dkicekeeper.github.io/Platina/

Один раз владельцу: Settings → Pages → Build and deployment → Source: GitHub Actions, затем
Actions → Pages → Run workflow. Страницы — на английском и русском на одной странице; связь —
та же почта, что у Dalada и Tenra. Хранение у Anthropic сверено 2026-11-25 (privacy.claude.com:
API — удаление в течение 30 дней, без обучения; до 2 лет — если запрос отмечен как нарушение
правил использования). Черновик ниже — история; опубликованный текст — в
`docs/public/privacy-policy.html`.

### Русский

> **Platina: политика конфиденциальности.** Platina — неофициальное приложение для трофеев
> PlayStation; оно не связано с Sony Interactive Entertainment.
>
> **Вход в PlayStation Network.** Вы входите на странице Sony; приложение не видит пароль.
> Ключи входа хранятся только в связке ключей этого устройства и никуда не отправляются.
> Трофеи и профиль приложение запрашивает у Sony напрямую с устройства.
>
> **Ваши данные.** Статусы игр, сессии, заметки, разговоры с ассистентом и прогресс
> прохождений хранятся на устройстве и в вашем iCloud (если он включён). У нас к ним доступа нет.
>
> **Ассистент Плати.** Когда вы пишете Плати, ваше сообщение (и фото экрана, если вы его
> прикрепили), а также данные о трофеях, нужные для ответа, отправляются на наш сервер и в
> Anthropic (модель Claude) только чтобы получить ответ. Наш сервер их не хранит и не записывает.
> Anthropic обрабатывает их по своей политике для API (сверить формулировку с текущей
> политикой Anthropic перед публикацией).
> Гайды и прохождения игр, которые собирает сервер, общие и не содержат ваших данных.
>
> **Чего нет.** Рекламы, аналитики, трекинга, продажи данных, сторонних SDK.
>
> **Удаление.** Выход из PSN в приложении удаляет ключи и кэш PSN. Свои данные удаляются вместе
> с приложением и в настройках iCloud. Вопросы — <почта владельца для поддержки>.

### English

> **Platina privacy policy.** Platina is an unofficial PlayStation trophy app, not affiliated with
> Sony Interactive Entertainment.
>
> **PlayStation Network sign-in.** You sign in on Sony's page; the app never sees your password.
> Sign-in keys stay in this device's keychain and are never sent anywhere. The app asks Sony for
> your trophies and profile directly from the device.
>
> **Your data.** Game statuses, sessions, notes, conversations with the assistant and walkthrough
> progress stay on the device and in your iCloud (when it is on). We have no access to them.
>
> **The Plati assistant.** When you write to Plati, your message (and a screen photo, if you
> attach one) and the trophy data needed for the answer go to our server and to Anthropic (the
> Claude model) only to get the answer. Our server doesn't store or log them. Anthropic processes
> them under its API policy (check the wording against Anthropic's current policy). The game guides and
> walkthroughs the server builds are shared and contain none of your data.
>
> **What there isn't.** Ads, analytics, tracking, selling data, third-party SDKs.
>
> **Deleting.** Signing out of PSN in the app deletes the keys and the PSN cache. Your own data
> goes with the app and in iCloud settings. Questions: <the owner's support address>.

## 4. Заметки для ревью (App Review Information → Notes)

> Platina is an unofficial companion for PlayStation trophy hunters. Sign-in: the reviewer signs
> in with a PlayStation Network account on Sony's own PlayStation Store page inside the app (we
> provide a test account below); the app never sees the password and keeps Sony's tokens only in
> the device keychain. Trophy data comes from PSN's web API, the same one the PlayStation App and
> playstation.com use. Plati, the in-app assistant, runs on our server with Anthropic's Claude; it
> retells guides in its own words with links to the sources and shows guide pictures from the
> sources' sites with their credit. App Attest protects the server, so the assistant needs a real
> device (not the simulator).
>
> Test account: <PSN email> / <password> (a separate PSN account with a few PS5 games).

Владельцу: завести отдельный аккаунт PSN для ревью (с парой игр PS5 и трофеями), без двухфакторки
или с ней, но тогда объяснить в заметках.

С 1.1 — добавить в заметки:

> Version 1.1 adds optional trophy notifications (Settings → Trophy notifications, off by
> default). To notify about trophies while the app is closed, our server needs access of its own:
> when the person turns it on and signs in to PSN once more, the app asks Sony for a one-time
> authorization code and sends only that code to our server, which exchanges it for its own
> tokens (stored encrypted) and checks PSN while the person plays. The app's own tokens stay in
> the keychain. Turning it off or signing out deletes everything on the server. Friends
> comparison reads the friends' public trophy lists from Sony on the device.

## 5. Письма источникам гайдов (черновики)

Цель: разрешение показывать картинки со ссылкой на страницу (и пересказывать шаги своими
словами — это и так можно, но лучше знать, что они не против). Кто откажет — убираем сайт из
`IMAGE_SOURCES` (wrangler.toml, деплой сервера), картинки этого сайта пропадут без релиза.

### PowerPyx / PSNProfiles (английский)

> Subject: Platina — showing your guide images with a link back
>
> Hi! I'm building Platina, an iPhone app for PlayStation trophy hunters. Its assistant leads
> players through a game chapter by chapter, and it relies on your guides: each step is retold in
> our own words with a link to your page, never copied.
>
> Where a picture of the spot helps (a collectible behind a crate, a turn that's easy to miss),
> the app would show your image the way a browser does: loaded from your site, not stored by us,
> with "[site name]" under it and a tap that opens your guide page. Would that be OK with you?
> If you'd rather we didn't show images, we'll switch them off for your site at once — the steps
> and the link stay.
>
> Thanks for the guides — they're why so many of us get our platinums.
> <owner's name>, Platina

### Stratege.ru (русский)

> Тема: Platina — картинки из ваших гайдов со ссылкой на Stratege
>
> Здравствуйте! Я делаю Platina — приложение для охотников за трофеями PlayStation на iPhone.
> Ассистент приложения ведёт по игре главами и опирается на гайды и подсказки Stratege: шаги
> пересказываем своими словами, со ссылкой на вашу страницу, без копирования.
>
> Там, где помогает картинка места, приложение показывало бы картинку из вашего гайда так, как
> это делает браузер: загружая с вашего сайта (мы её не храним), с подписью «Stratege» и
> переходом на страницу гайда по нажатию. Вы не против? Если против — сразу выключим картинки
> Stratege, шаги и ссылки останутся.
>
> Спасибо за сообщество и подсказки!
> <имя владельца>, Platina

## 6. Тексты страницы в App Store (черновик)

Ограничения App Store: название и подзаголовок — до 30 символов, ключевые слова — до 100 (через
запятую, без пробелов), рекламный текст — до 170, описание — до 4000. Чужие товарные знаки
(PlayStation, PS5, PSN) Apple не пускает в название и с осторожностью — в ключевые слова: в
названии их нет, в описании — только как описание совместимости, с пометкой о неофициальности.
Если ревью придерётся к ключевым словам — убрать оттуда PS5 и PSN.

Сами тексты (название, подзаголовок, ключевые слова, рекламный текст, описание на двух
языках), ссылки, категории, ответы анкеты возраста и заметки для ревью — в
[`appstore/metadata.json`](../appstore/metadata.json): его пишет в App Store Connect воркфлоу
**App Store** (раздел 9), поэтому правится только он.

Категория: основная — Справочники (Reference), дополнительная — Развлечения. Возраст: в арте игр,
картинках гайдов и видео бывает насилие (фэнтезийное и реалистичное, редко и мягко), оружие и
страшное; остального нет; чат Плати — с ассистентом, не между людьми.

## 7. Перед отправкой (чек-лист)

- [x] Политика конфиденциальности и поддержка опубликованы (GitHub Pages из `docs/public`,
      2026-11-25): https://dkicekeeper.github.io/Platina/privacy-policy.html и
      https://dkicekeeper.github.io/Platina/support.html; осталось вставить их в App Store Connect.
- [ ] App Privacy заполнен (раздел 2).
- [ ] Отдельный аккаунт PSN для ревью, заметки (раздел 4).
- [ ] Письма отправлены (раздел 5); ответы — в `IMAGE_SOURCES`.
- [ ] Схема CloudKit выкачена в продакшен (docs/testflight.md).
- [ ] Скриншоты (раздел 8): iPhone 6.9" (App Store уменьшает их для меньших iPhone), iPad 13"
      (приложение для iPad включено); Mac — если оставляем «Designed for iPad» на Mac.
- [ ] Название, подзаголовок, описание, ключевые слова, категория (Utilities / Games
      Reference), возрастной рейтинг; пометка, что приложение неофициальное и не связано с Sony.
- [ ] Проверка, что в ответах нет чужих текстов целиком: eval Плати (`ANTHROPIC_EVAL_API_KEY`)
      и выборочно — шаги нескольких глав против исходных страниц.

## 8. Скриншоты

Снимаются сами, без Mac под рукой: Actions → **Screenshots** → Run workflow (входы: устройства,
языки, экраны). Приложение запускается в демо (`-ScreenshotDemo`, `ios/Platina/Support/
ScreenshotDemo`): выдуманная библиотека из восьми игр (`PSNDemo` в PSNKit, тот же путь
синхронизации, что с PSN), их арт рисуется на устройстве (`DemoArt`), Плати отвечает по сценарию
(`AssistantDemoTransport`), сессии, план и галочки прохождения засеяны после синхронизации; ни PSN,
ни сервер Плати, ни iCloud не трогаются. Каждый экран приложение открывает само
(`-ScreenshotScreen <экран>`), UI-тест `PlatinaUITests/ScreenshotCaptureTests` только ждёт и
снимает; `scripts/capture_screenshots.sh` гоняет его на iPhone Pro Max (6.9", 1320×2868) и iPad
Pro 13" (2064×2752) на русском и английском.

Два артефакта прогона:

- `screenshots` — сырые снимки, `<устройство>/<язык>/NN-экран.png`;
- `store-frames` — они же в кадрах для App Store (`scripts/store_frames.py`), в порядке
  страницы магазина, и листы для просмотра (`sheet-<устройство>-<язык>.jpg`).

Кадры — решение владельца 2026-11-25: тёмная страница со свечением своего цвета, заголовок
Inter (из DesignKit той версии, с которой собирается приложение) в две строки, вторая — цветом
«Плазма»; первый кадр — наклонённый телефон, вокруг летят медали четырёх металлов с кубком
иконки; на iPhone карточка, о которой кадр, поднята из экрана крупнее (предупреждение Плати,
пропускаемое главы). Заголовки:

| № | Экран | Русский | English |
|---|---|---|---|
| 1 | Игра | Каждый трофей. / До платины. | Every trophy. / All the way to platinum. |
| 2 | Плати | Плати знает, / что дальше | Plati knows / what’s next |
| 3 | Глава | Ни одного / пропущенного | Never miss / a missable |
| 4 | Сессия | Играйте сессиями / с целями | Play in sessions / with goals |
| 5 | Прохождение | Вся игра / по главам | The whole game, / chapter by chapter |
| 6 | Гайд | Сложность, часы, / пропускаемое | Difficulty, hours, / missables |
| 7 | Путь | Всё, что вы / добиваете | Every game / you’re chasing |
| 8 | Библиотека | Вся библиотека / в одном месте | Your whole library / in one place |
| 9 | Профиль | Статистика / и серии | Stats / and streaks |

На скриншотах нет «PS5», «PlayStation» и чужих игр: товарные знаки Sony — только в описании, с
пометкой о неофициальности (раздел 6). Локально: `python3 scripts/store_frames.py --raw <снимки>
--font <DesignKit>/Sources/DesignTokens/Resources/Fonts/Inter-VariableFont_opsz,wght.ttf`.

## 9. Страница в App Store Connect

Воркфлоу **App Store** (Actions → App Store → Run workflow, `scripts/asc_metadata.py`) пишет
страницу через App Store Connect API тем же ключом, что TestFlight: названия, подзаголовки и
политику конфиденциальности языков, категории, описание, ключевые слова, рекламный текст и
ссылки версии, скриншоты (кадры из артефактов `store-frames` прогонов Screenshots: их номера во
входе `frames_runs`, поздние поверх ранних), ответы анкеты возраста и заметки для ревью. Без
`apply` он только читает App Store Connect и показывает, что бы изменил. Скриншоты набора
заменяются целиком.

API не умеет (остаётся в App Store Connect руками): App Privacy, контакт и тестовый аккаунт для
ревью, ответ о правах на чужой контент, цена и доступность, выбор сборки и отправка на ревью.
