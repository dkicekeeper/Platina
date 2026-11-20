# Сервер Плати

Cloudflare Worker между приложением Platina и Claude: хранит ключ Anthropic, проверяет, что
запрос пришёл из настоящего приложения (App Attest), считает квоты, ведёт чат Плати и собирает
гайды по играм (Stratege.ru + веб-поиск). Протокол с приложением — [docs/assistant.md](../../docs/assistant.md).
Содержание переписки сервер не логирует: только коды статусов и ошибок.

## Что внутри

| Файл | Что делает |
|---|---|
| `src/index.ts` | маршруты, App Attest или `DEV_TOKEN`, квоты, SSE |
| `src/claude.ts` | запрос к модели для чата, события потока → SSE, `done`, ошибки |
| `src/prompt.ts` | характер и правила Плати (`PROMPT_VERSION`) |
| `src/tools.ts` | 11 инструментов на телефоне и серверный `web_search` |
| `src/guide.ts` | сборка гайда: вход для модели, `save_guide`, проверка, кэш |
| `src/stratege.ts` | поиск и разбор страницы Stratege.ru без модели |
| `src/quota.ts`, `src/validate.ts` | квоты в KV, проверка тел запросов |
| `src/appattest.ts`, `cbor.ts`, `der.ts`, `apple-root.ts` | App Attest (как в Tenra) |
| `test/` | юнит-тесты (`npm test`), страницы Stratege в `test/fixtures/` |
| `eval/` | eval на реальном API: синтетический игрок, 11 случаев (ручной запуск) |
| `scripts/kv-namespaces.mjs` | создаёт KV-пространства и подставляет их id при деплое |

## Эндпоинты

| Запрос | Что отвечает |
|---|---|
| `GET /v1/health` | `{ok, protocol, prompt, guide_prompt}` |
| `GET /v1/attest/challenge` | `{challenge}`: одноразовый, 5 минут |
| `POST /v1/attest` | регистрирует ключ App Attest: `{keyId, attestation, challenge}` → `{ok, environment}` |
| `POST /v1/turn` | один вызов модели чата, SSE: `text`, `tool`, `search`, `done`, `error` |
| `POST /v1/guide` | гайд из кэша сразу (`guide`) или сборка: `progress` (`stratege`, `search`, `writing`), `guide` или `error` |
| `GET /v1/guide/{npCommunicationId}?language=ru` | гайд из кэша или 404 |

`/v1/turn` и `POST /v1/guide` принимают только подписанные App Attest запросы
(`x-platina-key`, `x-platina-assertion`) или, пока задан секрет `DEV_TOKEN`, заголовок
`x-platina-dev: <DEV_TOKEN>` (симулятор). Ошибки до потока: 400 `invalid` (с `reason`),
401 `attest` (с `reason`; `unknown_key` — приложение делает новый ключ), 429 `quota`
(`reason`: `monthly`, `daily` или `global`), 451 `region_unavailable`, 503 `disabled`.

## Настройка (`wrangler.toml`, `[vars]`)

| Переменная | По умолчанию | Что это |
|---|---|---|
| `ASSISTANT_ENABLED` | `true` | `false` — все ходы и гайды отвечают 503, модель не вызывается |
| `ASSISTANT_MODEL`, `ASSISTANT_EFFORT` | `claude-haiku-5-5`, `low` | модель чата |
| `GUIDE_MODEL`, `GUIDE_EFFORT` | `claude-sonnet-5-5`, `medium` | модель сборки гайдов |
| `GUIDE_MAX_SEARCHES` | `5` | веб-поисков на вызов модели гайда (`0` — гайд только по Stratege) |
| `WEB_SEARCH_ENABLED`, `WEB_SEARCH_MAX_USES` | `true`, `3` | веб-поиск в чате и его лимит на вызов |
| `MONTHLY_CALLS` | `3000` | вызовов модели на ключ App Attest в месяц |
| `DAILY_GUIDES` | `20` | сборок гайда на ключ в день (гайд из кэша бесплатен) |
| `GLOBAL_DAILY_CALLS` | `3000` | всех вызовов за день — предохранитель трат |
| `GUIDE_CALL_WEIGHT` | `50` | сколько вызовов в `GLOBAL_DAILY_CALLS` весит одна сборка гайда |
| `BLOCKED_COUNTRIES` | `RU,BY` | страны, где Anthropic не работает → 451 |
| `APP_ID` | `SY2L2VMQP7.dakacom.Platina` | Team ID + bundle id для App Attest |

Секреты (не в файлах): `ANTHROPIC_API_KEY`, необязательный `DEV_TOKEN`. KV: `ATTEST`
(ключи App Attest), `QUOTA` (счётчики), `GUIDES` (гайды на 30 дней, разобранный Stratege на
14 дней).

Новая модель или лимит — правка `wrangler.toml` и деплой. Изменение промпта — новый
`PROMPT_VERSION` и прогон eval до деплоя.

## Первый запуск (один раз)

1. **Cloudflare.** Аккаунт на [dash.cloudflare.com](https://dash.cloudflare.com) и план
   Workers Paid ($5 в месяц): на бесплатном у запроса 10 мс процессора и 1 000 записей в KV
   в день, сборке гайда этого мало. В Workers & Pages один раз выберите поддомен
   `*.workers.dev`.
2. **Токен Cloudflare.** My Profile → API Tokens → Create Token → шаблон «Edit Cloudflare
   Workers» (в нём есть Workers Scripts и Workers KV Storage) → ваш аккаунт → Create. Account
   ID — на странице Workers & Pages справа.
3. **Ключ Anthropic.** [console.anthropic.com](https://console.anthropic.com) → Settings →
   Workspaces: отдельное пространство «Platina» с лимитом трат в месяц (например, $30) →
   API key в нём. Для eval — второе пространство «Platina eval» со своим лимитом и своим ключом.
4. **Секреты репозитория.** GitHub → Settings → Secrets and variables → Actions → New
   repository secret:
   - `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` — из шага 2;
   - `ANTHROPIC_API_KEY` — ключ «Platina»;
   - `PLATINA_DEV_TOKEN` — по желанию, для симулятора: длинная случайная строка
     (`openssl rand -hex 24`); тот же токен — в Debug-конфигурацию приложения
     (`PlatinaAssistantDevToken` в Info.plist через xcconfig). Без него симулятор к серверу
     не пройдёт, а деплой удалит старый `DEV_TOKEN` с Worker'а;
   - `ANTHROPIC_EVAL_API_KEY` — по желанию, ключ «Platina eval».
5. **KV-пространства.** Actions → Assistant server → Run workflow → action `setup`. Он
   создаст `platina-assistant-attest`, `-quota`, `-guides` (если их нет) и напечатает их id.
   Вписывать их в `wrangler.toml` не обязательно: деплой находит их по имени сам. Если
   хочется видеть их в файле — замените ими `REPLACE_WITH_..._NAMESPACE_ID` и закоммитьте.
   (Без Actions: `npx wrangler kv namespace create platina-assistant-attest` и т. д.)
6. **Деплой.** Run workflow → action `deploy`. Он прогонит тесты, задеплоит Worker,
   загрузит секреты и напишет в Summary адрес вида
   `https://platina-assistant.<поддомен>.workers.dev`; проверка — `<адрес>/v1/health`.
7. **Адрес в приложение.** В `ios/Config/Platina.xcconfig`:
   ```
   PLATINA_ASSISTANT_URL = https:/$()/platina-assistant.<поддомен>.workers.dev
   ```
   (`//` в xcconfig начинает комментарий, поэтому `/$()/`.) Пустой адрес — вкладка Плати
   объясняет, что сервер не настроен.

Дальше любой деплой — тот же action `deploy`. Выключить Плати без релиза —
`ASSISTANT_ENABLED = "false"` и деплой.

## Разработка

```bash
cd server/assistant
npm ci
npm run typecheck && npm test
npx wrangler dev          # локально; секреты — в .dev.vars (не в git)
```

Eval (тратит кредиты, только вручную): `ANTHROPIC_API_KEY=<ключ eval> npm run eval -- --models
claude-haiku-5-5 --effort low --yes` или Actions → action `eval`. Без `--yes` печатает только
оценку стоимости. Отчёт — `eval/out/<время>/summary.md`.

## Стоимость

Цены Anthropic за 1M токенов: Haiku 5.5 $0.10 / $0.50, Sonnet 5.5 $2 / $10; веб-поиск $0.01
за запрос.

- **Чат**: вызов на Haiku — около $0.001–0.003 (промпт и инструменты кэшируются), вопрос — 2–4
  вызова, плюс $0.01 за каждый веб-поиск. 60 вопросов в месяц — порядка $0.2–0.5.
- **Гайд**: сборка на Sonnet с 3–5 поисками — около $0.10–0.25, один раз на игру и язык;
  потом 30 дней из кэша бесплатно. Stratege читается одной страницей на игру и тоже кэшируется.
- **Cloudflare**: Workers Paid $5 в месяц покрывает такой трафик с запасом.
- Жёсткий предел — лимит трат пространства в консоли Anthropic; `GLOBAL_DAILY_CALLS` гасит
  всплеск за день раньше, чем лимит выключит Плати до конца месяца.
- Eval: все случаи на Haiku — несколько центов, на Sonnet — до доллара.
