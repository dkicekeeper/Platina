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

## 3. Политика конфиденциальности (черновик)

Нужна по ссылке (App Store Connect → App Privacy → Privacy Policy URL). Можно опубликовать
страницей (GitHub Pages, сайт) — текст ниже, русский и английский.

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

## 6. Перед отправкой (чек-лист)

- [ ] Политика конфиденциальности опубликована, ссылка в App Store Connect.
- [ ] App Privacy заполнен (раздел 2).
- [ ] Отдельный аккаунт PSN для ревью, заметки (раздел 4).
- [ ] Письма отправлены (раздел 5); ответы — в `IMAGE_SOURCES`.
- [ ] Схема CloudKit выкачена в продакшен (docs/testflight.md).
- [ ] Скриншоты: iPhone 6.9" и 6.5", iPad 13" (приложение для iPad включено), Mac — если
      оставляем «Designed for iPad» на Mac.
- [ ] Название, подзаголовок, описание, ключевые слова, категория (Utilities / Games
      Reference), возрастной рейтинг; пометка, что приложение неофициальное и не связано с Sony.
- [ ] Проверка, что в ответах нет чужих текстов целиком: eval Плати (`ANTHROPIC_EVAL_API_KEY`)
      и выборочно — шаги нескольких глав против исходных страниц.
