# Плати: ассистент и его сервер

Контракт между приложением (`ios/`) и сервером (`server/assistant/`). Основан на протоколе
ассистента Тен в Tenra (`dkicekeeper/Tenra`, `docs/domains/assistant.md` §8), упрощён: ответы —
Markdown-текст, а не блоки `render_reply`.

## 1. Что где

```
 Приложение                                  Сервер (Cloudflare Worker)             Anthropic
 ──────────                                  ──────────────────────────             ─────────
 AssistantConversation: цикл хода   ──POST /v1/turn (SSE)──▶  промпт, инструменты, ──▶ Claude
   инструменты на телефоне (база)  ◀── text / tool / done ──  web_search (серверный)
 GuideStore: гайд по игре           ──POST /v1/guide (SSE)──▶  Stratege.ru + Claude ──▶ Claude
                                    ◀── progress / guide ───   кэш в KV
 WalkthroughService: главы, шаги    ──POST /v1/walkthrough[/chapter] (SSE)──▶ поиск + чтение
                                    ◀── progress / walkthrough / chapter ──   страниц, кэш в KV
 AssistantAttestation: App Attest   ──/v1/attest/challenge, /v1/attest──▶ ключ в KV
```

- Ключ Anthropic только на сервере. Токены PSN на сервер не уходят никогда.
- Сервер ничего не пишет в логи о содержании: только коды статусов и ошибок.
- Один вызов `/v1/turn` — один вызов модели. Цикл (модель просит инструмент → телефон отвечает
  → новый вызов) крутит приложение. Исключение — долгий серверный веб-поиск, поставленный
  моделью на паузу (`pause_turn`): сервер сам продолжает ход (до двух раз) и отдаёт один `done`
  со всем содержимым.

## 2. Защита и лимиты

- **App Attest**, как в Tenra: `GET /v1/attest/challenge` → `{challenge}` (одноразовый, 5 минут);
  приложение создаёт ключ `DCAppAttestService`, аттестацию с `clientDataHash = SHA256(challenge)`;
  `POST /v1/attest {keyId, attestation, challenge}`. Каждый `/v1/turn`, `POST /v1/guide` и
  `POST /v1/walkthrough[/chapter]` несёт
  заголовки `x-platina-key` (keyId) и `x-platina-assertion` (base64, подпись SHA256 тела).
  App id: `SY2L2VMQP7.dakacom.Platina`. Ответ 401 `{error: "attest", reason}`; `reason:
  "unknown_key"` — приложение делает новый ключ и повторяет один раз. Ключи и challenge — в KV
  `ATTEST`. Отказ в регистрации ключа — 400 `{error: "attestation", reason}`.
- **Симулятор и отладка**: App Attest на симуляторе не работает. Переменная Worker'а
  `DEV_TOKEN` (секрет, по умолчанию не задан): если задана, запрос с заголовком
  `x-platina-dev: <DEV_TOKEN>` проходит без App Attest (неверный токен — 401 `attest`,
  `reason: "dev_token"`; без секрета заголовок ничего не значит). В приложении —
  `PlatinaAssistantDevToken` в Info.plist (через xcconfig, только Debug).
- **Квоты** (KV `QUOTA`): вызовов модели на ключ App Attest в месяц (`MONTHLY_CALLS`, 3000),
  сборок гайда на ключ в день (`DAILY_GUIDES`, 20; гайд из кэша бесплатен), всего вызовов в день
  (`GLOBAL_DAILY_CALLS`, 3000) — предохранитель трат; сборка гайда весит в нём
  `GUIDE_CALL_WEIGHT` (50) вызовов. 429 `{error: "quota", reason: "monthly" | "daily" | "global",
  used, limit}`.
- Выключатель `ASSISTANT_ENABLED` ("false" → 503 `disabled`). Страны, где Anthropic не работает,
  `BLOCKED_COUNTRIES` ("RU,BY") → 451 `region_unavailable`. Оба касаются `/v1/turn`, `/v1/guide`
  и `/v1/walkthrough`; `/v1/attest*` и `/v1/health` отвечают всегда.

## 3. `POST /v1/turn`

Тело:

```json
{
  "protocol": 1,
  "language": "ru",
  "messages": [ ...Messages API: user/assistant, text, tool_use, tool_result... ]
}
```

- Ограничения: тело до 256 КБ, до 80 сообщений, текстовый блок до 16 КБ, результат инструмента
  до 64 КБ; роль `system` и `cache_control` от клиента — 400 `invalid`.
- `language` — код языка приложения (`ru`, `en`, `ru-RU`…): русская локаль → ответы на
  русском, любая другая → на английском. Без него — 400 `invalid`, `reason: "language"`.
- Сервер добавляет системный промпт (характер Плати, правила спойлеров и пропускаемых трофеев,
  язык ответа = `language`), клиентские инструменты из §5, серверный `web_search` (если
  `WEB_SEARCH_ENABLED`), модель (`ASSISTANT_MODEL`), кэширование промпта.
- Первое сообщение пользователя в разговоре начинается с блока `<app_context>…</app_context>`:
  сегодняшняя дата, язык, PSN-ник и уровень, открытая игра (если чат открыт из игры) и текущая
  сессия (если идёт). Новый контекст — когда что-то из этого меняется.

Ответ — SSE (`text/event-stream`), события:

| Событие | Данные | Что делает приложение |
|---|---|---|
| `text` | `{"text": "…"}` | дописывает ответ в пузырь по мере генерации |
| `tool` | `{"name": "list_trophies"}` | показывает шаг «смотрю трофеи…» |
| `search` | `{"query": "…"}` | Плати ищет в интернете (серверный web_search) |
| `done` | `{"content": [...], "stop_reason": "end_turn" \| "tool_use" \| …, "usage": {...}}` | сохраняет `content` как ход ассистента без изменений; на `tool_use` выполняет инструменты и шлёт следующий вызов |
| `error` | `{"code": "…", "retryable": true}` | показывает ошибку с «Повторить» |

История только дописывается: `done.content` хранится и отправляется обратно как есть
(иначе ломаются thinking-блоки и кэш). Ошибки до потока: 400 `invalid`, 401 `attest`,
429 `quota`, 451 `region_unavailable`, 503 `disabled`.

В `done` есть ещё: `model`; `refused` (модель отказалась: `content` пуст, ход не сохранять);
`truncated` (вход инструмента обрезан `max_tokens`: не выполнять); `quota {used, limit}`;
в `usage` — `web_search_requests`. Коды `error`: `upstream_busy`, `upstream_unavailable`
(можно повторить), `bad_request`, `internal`.

## 4. Гайды: `POST /v1/guide`, `GET /v1/guide/{id}`

`GET /v1/guide/{npCommunicationId}?language=ru` → 200 с гайдом из кэша или 404.

`POST /v1/guide` (App Attest, квота гайдов) — собрать (или вернуть из кэша) гайд:

```json
{
  "protocol": 1,
  "language": "ru",
  "refresh": false,
  "game": {
    "npCommunicationId": "NPWR28536_00",
    "name": "Cult of the Lamb",
    "platform": "PS5",
    "trophySetVersion": "01.20",
    "trophies": [
      {"id": 12, "name": "Улыбка фортуны", "detail": "…", "type": "silver", "hidden": false, "groupId": "default"}
    ]
  }
}
```

Ответ — SSE: `progress {"step": "stratege" | "search" | "writing"}`, затем
`guide {…Guide…}` или `error {code, retryable}`. Кэш в KV `GUIDES` по
`{npCommunicationId}:{language}`; живёт 30 дней или до `refresh: true`.

Как сервер собирает гайд:
1. **Stratege.ru**: находит страницу игры (`stratege.ru/ps5/games/<slug>/trophies/spisok`;
   slug из названия, проверка — в путях картинок есть `npCommunicationId`, иначе поиск),
   разбирает HTML без модели: сводку из подсказки к платине (сложность, время, прохождения,
   онлайн, пропускаемые, глючные, влияние сложности), подсказки игроков к каждому трофею
   (автор, дата, «спасибо», текст), среднее время платины и % получивших.
2. **Claude** (`GUIDE_MODEL`, по умолчанию Sonnet 5.5) с web_search (PSNProfiles, PowerPyx,
   PlayStationTrophies, TrueTrophies, Reddit, YouTube) и разобранным Stratege пишет гайд через
   инструмент `save_guide` со строгой схемой. Своими словами, коротко, со ссылками на источники;
   без копирования чужих текстов целиком.

### Схема гайда

```json
{
  "gameId": "NPWR28536_00",
  "language": "ru",
  "generatedAt": "2026-11-20T10:00:00Z",
  "summary": {
    "difficulty": 4,
    "hoursMin": 10, "hoursMax": 15,
    "playthroughs": 1,
    "onlineTrophies": 0,
    "missableTrophies": 1,
    "glitchedTrophies": 0,
    "difficultyAffects": false,
    "overview": "2–4 предложения: что за платина и как к ней идти"
  },
  "steps": [
    {"title": "Шаг 1. Сюжет", "text": "…Markdown…", "trophyIds": [1, 2, 3]}
  ],
  "missable": [
    {"trophyId": 12, "note": "Сыграйте в кости со всеми до финала: после него игроки уходят"}
  ],
  "tips": [
    {"trophyId": 12, "text": "…Markdown, 1–5 предложений…", "sourceIds": ["s1", "s2"]}
  ],
  "sources": [
    {"id": "s1", "title": "Stratege.ru: подсказка от TailyMile", "url": "https://…"}
  ],
  "stratege": {
    "url": "https://stratege.ru/ps5/games/cult_of_the_lamb/trophies/spisok",
    "averagePlatinumHours": 49,
    "platinumPercent": 16.57
  }
}
```

Числа сводки, которых нет ни в одном источнике, — `null`. `trophyIds` и `trophyId` — только из
переданного списка трофеев. `stratege` — `null`, если на Stratege нет страницы игры. В
`sources` подсказки Stratege — `st<id подсказки>` со ссылкой на страницу трофея; веб-страницы —
только из результатов поиска этой сборки (сервер проверяет). Шаги и обзор не называют скрытые
трофеи (сервер проверяет); подсказки и заметки о пропускаемых — могут: приложение показывает их
по нажатию.

Коды `error` гайда: `refused` (не повторять), `invalid_guide`, `no_guide`, `truncated`,
`upstream_busy`, `upstream_unavailable` (можно повторить), `bad_request`, `internal`. Сборка,
которую модель так и не начала, квоту не тратит. Разобранная страница Stratege хранится в
`GUIDES` 14 дней (её же берёт гайд на другом языке).

## 5. Инструменты на телефоне

Определения (имя, описание, JSON-схема входа) — в `server/assistant/src/tools.ts`; выполняет их
приложение (`AssistantToolkit`) по своей базе. Результат — JSON-текст в `tool_result`.

| Инструмент | Вход | Что возвращает |
|---|---|---|
| `get_profile` | — | ник, уровень, платины, трофеи по типам, часы |
| `list_games` | `filter`: `in_progress` \| `chasing` \| `platinum` \| `not_started` \| `shelved` \| `all`; `limit` | игры: id, название, прогресс, трофеи, часы, статус |
| `get_game` | `game_id` | игра: прогресс, группы (DLC), время, статус, сводка гайда и текущая глава прохождения, если есть |
| `list_trophies` | `game_id`; `filter`: `unearned` \| `earned` \| `all`; `type`; `group_id`; `include_hidden_details`; `limit` | трофеи: id, название, описание (у скрытых — только если `include_hidden_details`), тип, %, прогресс, дата, заметка, пропускаемый ли |
| `get_guide` | `game_id` | гайд (§4); если его нет — приложение собирает его через `/v1/guide` |
| `get_game_help` | `game_id`; `trophy_ids`? (1–5) | подсказки PlayStation (Game Help), прямо из PSN: без `trophy_ids` — какие трофеи с подсказкой (id, название — у скрытых неполученных нет, скрытый ли, получен ли); с ними — шаги каждого (заголовок, текст, есть ли видео: оно на экране трофея в приложении) |
| `get_walkthrough` | `game_id` | план прохождения (§8) с тем, где человек: обзор, прохождения, главы (id, название, описание, `state`: `done` \| `current` \| `ahead`, пропускаемое с названием трофея — у скрытых неполученных нет — и получен ли он, выборы, коллекционки, трофеи), текущая глава, зачистка, источники; если плана нет — приложение собирает его |
| `get_chapter` | `game_id`; `chapter_id`? (по умолчанию текущая) | шаги главы: id, вид, текст, `done`, `spoiler`, трофеи, номер коллекционки, есть ли картинка и видео, источник; `next_step_id`; если шагов нет — приложение собирает их |
| `set_walkthrough_progress` | `game_id`; `chapter_id`; `done_step_ids`?; `undone_step_ids`?; `chapter_done`?; `current`? | отмечает сделанное человеком; возвращает текущую главу и её следующий шаг |
| `get_sessions` | `game_id`; `limit` | прошлые сессии: даты, время, трофеи, итоги |
| `get_current_session` | — | идущая сессия: игра, время, цели, трофеи за сессию |
| `set_session_goals` | `game_id`; `trophy_ids`; `note` | ставит цели текущей (или следующей) сессии |
| `set_game_status` | `game_id`; `status`: `chasing` \| `later` \| `skip` \| `none` | меняет статус игры |
| `save_note` | `game_id`; `trophy_id`?; `text` | заметка к игре или трофею |
| `save_session_summary` | `session_id`; `summary`; `next_steps` | итог сессии в журнал |

Типы входов: `game_id` — строка (npCommunicationId); `trophy_id` — целое (PSN trophyId);
`trophy_ids` — массив целых, 1–6 (у `get_game_help` — 1–5); `limit` — целое; `include_hidden_details` — bool; `session_id`,
`note`, `text`, `summary`, `next_steps` — строки (`next_steps` — короткий Markdown-список).
Обязательны только `game_id` (кроме `list_games`, `get_sessions`), `trophy_ids`, `status`,
`text`, `session_id`, `summary`, `next_steps`, `chapter_id` у `set_walkthrough_progress`; остальные модель может не прислать:
`filter` у `list_games` и `list_trophies` по умолчанию `all`, `include_hidden_details` — `false`,
`get_sessions` без `game_id` — все игры. Лишних полей нет (`additionalProperties: false`).

Новый инструмент совместим со старым приложением: неизвестное имя оно возвращает модели ошибкой
(`Unknown tool …`), и разговор идёт дальше; `PROTOCOL_VERSION` не меняется.

## 6. Режимы

- **Чат** (вкладка «Плати», чат игры): вопросы, «что пройти дальше», подсказки.
- **План сессии**: при старте сессии приложение шлёт ход «Начинаю сессию в <игра>» — Плати
  смотрит гайд и трофеи и ставит 2–4 цели через `set_session_goals`, предупреждает о
  пропускаемых.
- **Итог сессии**: при финише — ход «Сессия закончена» с полученными трофеями; Плати пишет итог
  и «что дальше» через `save_session_summary`.

## 7. Настройка (один раз)

Описана в `server/assistant/README.md`: Cloudflare-аккаунт, KV-пространства (ручной запуск
`setup`), секреты `ANTHROPIC_API_KEY` (и опционально `DEV_TOKEN` из секрета репозитория
`PLATINA_DEV_TOKEN`), деплой из GitHub Actions (`.github/workflows/assistant.yml`, ручной
запуск `deploy`). Хост Worker'а (без `https://`: в xcconfig `//` — начало комментария) —
`PLATINA_ASSISTANT_HOST` в `ios/Config/Local.xcconfig` (не в git) или в
`ios/Config/Platina.xcconfig`; для симулятора там же `PLATINA_ASSISTANT_DEV_TOKEN`. Пустой хост —
вкладка Плати объясняет, что сервер не настроен.

## 8. Прохождение по главам: `/v1/walkthrough` (этап 6)

Подробно о задумке — docs/PLAN.md §5, «Прохождение по главам». Сервер собирает два слоя, оба
моделью гайдов (`GUIDE_MODEL`) с `web_search` и `web_fetch`, оба в KV `GUIDES` на 30 дней:

- **план** (`walk:{npCommunicationId}:{language}`): главы игры по порядку, что в каждой можно
  пропустить, выборы, коллекционки, трофеи, трофей за главу, зачистка;
- **шаги главы** (`walk:{id}:{language}:{chapterId}`): что делать по порядку, собираются, когда
  игрок до главы дошёл. Шаги привязаны к `generatedAt` плана: пересобранный план делает их
  устаревшими (сервер их не отдаёт, приложение собирает заново).

`GET /v1/walkthrough/{npCommunicationId}?language=ru` и
`GET /v1/walkthrough/{npCommunicationId}/chapter/{chapterId}?language=ru` → 200 из кэша или 404.

`POST /v1/walkthrough` — тело как у `POST /v1/guide` (§4). `POST /v1/walkthrough/chapter` — то
же плюс `"chapterId": "c3"`. Ответ — SSE: `progress {"step": "search" | "reading" | "writing"}`,
затем `walkthrough {…}` или `chapter {…}`, или `error {code, retryable}`. Квота — как у гайдов
(`DAILY_GUIDES`, вес `GUIDE_CALL_WEIGHT`); из кэша бесплатно. Заголовок `x-platina-prompt` —
`WALKTHROUGH_PROMPT_VERSION` (он же `walkthrough_prompt` в `/v1/health`).

Как собирается: модель ищет прохождение (PowerPyx первым, затем PSNProfiles, Stratege,
PlayStationTrophies), читает одну-две страницы `web_fetch` (только сайты гайдов, до
`WALKTHROUGH_MAX_FETCHES` за вызов, страница до ~20k токенов) и сохраняет результат строгим
инструментом `save_walkthrough` / `save_chapter`. Для плана в запрос идёт гайд игры из кэша, если
он есть (его источники можно цитировать); для главы — план с отмеченной главой и его источники.
Пересказ своими словами, ничего не копируется.

### План

```json
{
  "gameId": "NPWR12345_00", "language": "ru", "generatedAt": "2026-11-23T12:00:00Z",
  "overview": "2–4 предложения: как идти к платине",
  "playthroughs": 1,
  "chapters": [
    {
      "id": "c1", "title": "Пролог", "summary": "1–2 предложения, без спойлеров",
      "missable": [{"trophyId": 4, "note": "Пощадите рыцаря в конце главы"}],
      "choices": ["Пощадить рыцаря"],
      "collectibles": [{"kind": "Реликвии", "count": 3}],
      "trophyIds": [1, 4], "completionTrophyId": 1, "playthrough": 1, "sourceIds": ["w1"]
    }
  ],
  "cleanup": "Markdown: что останется после сюжета",
  "sources": [{"id": "w1", "title": "PowerPyx: walkthrough", "url": "https://…"}]
}
```

### Шаги главы

```json
{
  "gameId": "NPWR12345_00", "language": "ru", "chapterId": "c1",
  "walkthroughGeneratedAt": "2026-11-23T12:00:00Z", "generatedAt": "2026-11-23T12:05:00Z",
  "steps": [
    {
      "id": "s2", "kind": "collectible", "text": "Markdown, 1–3 предложения",
      "trophyIds": [2], "spoiler": false,
      "collectible": {"kind": "Реликвия", "number": 1},
      "sourceId": "w1",
      "image": {"url": "https://www.powerpyx.com/wp-content/uploads/….jpg", "sourceId": "w1"},
      "video": {"youtubeId": "dQw4w9WgXcQ", "startSeconds": 95}
    }
  ],
  "sources": [{"id": "w1", "title": "PowerPyx: глава 1", "url": "https://…"}]
}
```

`kind`: `path` (куда идти), `collectible`, `choice` (выбор ради трофея), `point_of_no_return`
(дальше не вернуться — что доделать до него), `trophy`, `boss`, `tip`. Id шагов — `s1`, `s2`… по
порядку, их приложение и хранит в прогрессе.

Что проверяет сервер (как у гайда: одна просьба исправить, потом сохраняется пригодное):
- `trophyIds`, `trophyId`, `completionTrophyId` — только из переданного списка; id глав `c1`…
  уникальные, глав 1–60, шагов до 80;
- ссылки источников — только страницы, которые сборка видела (результаты поиска, прочитанные
  страницы и ссылки на них, источники гайда или плана);
- скрытые трофеи: в плане имя не появляется (заменяется на «скрытый трофей»); шаг, который
  называет или даёт скрытый трофей, — `spoiler: true` (приложение раскрывает по нажатию);
- `image` — только `https`, только если адрес был на прочитанной странице и сайт в
  `IMAGE_SOURCES` (по умолчанию `powerpyx.com,psnprofiles.com,stratege.ru,playstationtrophies.org`;
  пусто — картинок нет); иначе `null` без жалобы. Приложение грузит картинку с сайта источника
  (не хранит), с подписью источника и переходом на страницу;
- `video` — id YouTube, который был в результатах или на странице; иначе `null`.

Коды `error`: `no_walkthrough` (сначала план), `unknown_chapter`, `refused` — не повторять;
`invalid`, `no_result`, `truncated`, `upstream_busy`, `upstream_unavailable` — можно повторить;
`bad_request`, `internal`. Сборка, которую модель не начала, квоту не тратит.

### Дальше (этапы 6–9)

- **Инструменты на телефоне** (§5): `get_walkthrough`, `get_chapter`, `set_walkthrough_progress`.
  Прогресс — свои данные человека (`WalkthroughProgressRecord`: отмеченные шаги `c2/s5`, главы,
  текущая глава; iCloud), на сервер не уходит, кроме ответа инструмента. Где человек, приложение
  считает само (`WalkthroughPosition`): глава позади, если отмечена или получен её трофей за
  главу (и все главы до неё); шаг сделан, если отмечен, получены его трофеи или глава позади.
- **Инструменты показа** (этап 7): `show_checklist`, `show_step`, `show_trophies`,
  `show_warning`, `suggest_replies` — приложение рисует карточки и отвечает модели «показано».
  Старое приложение на незнакомый инструмент ответит ошибкой; модель тогда пишет текстом.
- **Фото** (этап 9): картинка в сообщении пользователя (content block `image`), только для
  ответа, сервер её не хранит.
