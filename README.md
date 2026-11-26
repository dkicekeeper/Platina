# Platina

Трекер трофеев PlayStation с ИИ-ассистентом Плати: каждая игра — путь к платине и 100%, а Плати
ведёт по ней «за руку», глава за главой.

- Документы: [docs/README.md](docs/README.md) (паспорт, открытые задачи, решения, области)
- Для разработки (и для Claude): [CLAUDE.md](CLAUDE.md)
- Плати (приложение ↔ сервер): [docs/assistant.md](docs/assistant.md)
- Сборка и TestFlight: [docs/testflight.md](docs/testflight.md)
- App Store: черновики политики, App Privacy, заметок для ревью и писем — [docs/app-store.md](docs/app-store.md)

Сейчас: этапы 0–4 и 6–9 сделаны, приложение работает на iPhone с настоящим аккаунтом PSN (вход
через PlayStation Store, синхронизация, подсказки PlayStation), сервер Плати развёрнут, сборки
идут в TestFlight. Плати ведёт по игре «за руку»: главы, шаги чек-листом, прогресс, текущая
глава в сессии; карточки и быстрые ответы в чате; шаг на Live Activity с ✓ и через Siri; «Где
я?» по фото экрана. Дальше ([docs/backlog/](docs/backlog/)):

5. Проверка на устройстве (вместе с этапами 6–9).
10. iPad и macOS.
11. App Store.
