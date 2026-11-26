# Из чего собрано (DesignKit)


| Где | Компоненты |
|---|---|
| Кнопки, формы, настройки | `DSButton`, `FormSection` + `UniversalRow` |
| Библиотека игр | `CardList`, `ThumbnailCard`, `RemotePhoto`, `ChipPicker`, `UniversalFilterButton`, `.dsSearchSuggestions` |
| Прогресс | `ProgressRing`, `LinearProgressBar`, `ProgressRingTileGrid`, `ProportionBar` (доли типов трофеев) |
| Трофеи | `AchievementMedal`, `AchievementTile`, `AchievementProgressRow`, `.holographic` + `.interactiveTilt` для платины; тип и дата получения текстом — `AppColors.readable` / `Status.positiveText` (металлы на серой карточке читались 2,1–3,6:1) |
| Экран игры | `.heroBackground(clearHeight:picture:)` + `.heroScrollEdge(isHeroUnderBar:)`, `ChipPicker` (разделы), `ScoreCard` (сложность), `InfoTip` (откуда цифра) |
| Дорожная карта | `StepTracker`, `ChecklistRow`, `ChecklistSummaryRow` |
| Подсказки и гайды | `ArticleBody`, `ExpandableText`, `StatusBanner` (пропускаемый), `RecommendationBox` |
| Сессия | `LiveSessionBar` (+ `.liveSessionAccessory`), `RelativeTime(.clock)`, `ChecklistRow`, `.completionMoment`, `.celebration`, `.sparkleBurst` |
| Журнал, лента | `ActivityTimeline`, `CalendarHeatmap`, `StreakCard` |
| Статистика | `BarChart`, `LineChart`, `ChartSwitcher`, `MetricCard`, `InsightsStatCard` |
| Чат | `ParticleCreature`, `CreatureTabLabel`, `MessageBubble(markdown:)`, `MessageComposer`, `TypingIndicator`, `SuggestionChips`, `ConversationDivider`, `.thinkingShimmer` |
| Состояния | скелетоны `<Name>Skeleton` + `.skeletonReveal`, `EmptyState`, `MessageBanner` |
| Платина | `ShareCardSheet`, `.holographic`, `AuroraBackground` |
| Первый запуск | `OnboardingPager`, `NotificationPermissionPrompt` |

Чего в DesignKit нет и что, по правилам DesignKit, надо будет добавить туда отдельными PR
(с общими названиями, страницей в Gallery и снапшотами):

- Медаль трофея четырёх типов (бронза, серебро, золото, платина) — скорее всего стиль
  `AchievementMedal`, а не новый компонент.
- Строка счётчиков трофеев по типам (`🏆 1 · 12 · 30 · 48`) — возможно `StatsStrip` со стилем.
- Цвета бронзы, серебра, золота и платины как токены (или палитра в приложении через
  `AppColors.readable` / `pale`).

Акцент приложения: `DesignKitTheme.accent` = «Плазма» (решение владельца 2026-11-25, вместо
платинового голубого `#3573BA`): `#D6006F` в светлой теме, `#FF4FA0` в тёмной (5,1:1 на белом,
6,9:1 на чёрном), та же пара в `AccentColor` каталога и в виджетах (`PlatinaPalette`); иконка —
тот же кубок на градиенте от тёмной сливы к «Плазме». Индиго
Tenra, зелёный Dalada, малиновый Platina — три приложения различимы с первого взгляда.

Поверхности — серая заливка вместо Liquid Glass (`DesignKitTheme.surface = .fill`, DesignKit
8.12.0, 2026-11-23): карточки и секции серые на белой странице, стекло остаётся у кнопок,
таб-бара и плавающих элементов.
