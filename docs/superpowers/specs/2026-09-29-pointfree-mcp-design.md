# PointFreeMCP — дизайн

Дата: 2026-09-29. Статус: согласован в чате.

## Цель

Локальный MCP-сервер на Swift, который даёт Claude Code (и другим MCP-клиентам) доступ к порталу pointfree.co так же, как sosumi даёт доступ к документации Apple: поиск по каталогу, метаданные эпизодов, транскрипты с кодом, коллекции. Всё запрашивается с сайта в момент вызова, ничего не выкачивается заранее. Платный контент доступен только при активной подписке пользователя, вход выполняется через GitHub в окне браузера.

## Ограничения и лицензия

- Видео и транскрипты pointfree.co — «all rights reserved». Сервер получает их от имени конкретного пользователя по его сессии и передаёт только в его MCP-клиент. Транскрипты не сохраняются на диск, не логируются, не попадают в репозиторий.
- Тестовые фикстуры HTML — синтетические: повторяют структуру разметки сайта, но содержат заглушечный текст, не реальные транскрипты. Реальные страницы для отладки лежат в `Fixtures/live/`, папка в `.gitignore`.
- Скиллы Point-Free Way (`pfw-*`) лицензированы лично и в проект не включаются, сервер к ним не обращается.
- Нагрузка на сайт минимальна: один запрос на вызов инструмента, кэш в памяти, User-Agent с именем проекта.
- Код проекта — MIT.

## Платформа и стек

- macOS 26+, Swift 6.2 tools, Xcode 26. Другие платформы не поддерживаются (AppKit/WebKit для входа).
- Зависимости: `modelcontextprotocol/swift-sdk` (MCP, stdio), `scinfu/SwiftSoup` (HTML), `apple/swift-argument-parser` (CLI), `pointfreeco/swift-dependencies` (инъекция зависимостей и тестируемость). Тесты на Swift Testing.

## Структура пакета

```
Package.swift
Sources/
  PointFreeKit/            # библиотека, без AppKit
    Models/                # Episode, EpisodeDetail, SearchResult, Collection, Transcript
    Client/                # PointFreeClient (dependency), HTTPClient (dependency), UserAgent
    Parsing/               # SearchPageParser, EpisodePageParser, CollectionsParser
    Rendering/             # MarkdownRenderer для каждого типа ответа
    Session/               # SessionStore (dependency), Session
    Cache/                 # MemoryCache<Key, Value> с TTL и лимитом
    Tools/                 # ToolCatalog: описания и обработчики инструментов
  PointFreeMCP/            # исполняемый target `pointfree-mcp`
    Commands/              # Serve (default), Login, Logout, Status
    Server/                # сборка MCP Server, маршрутизация CallTool → ToolCatalog
    LoginWindow/           # NSApplication + WKWebView, перехват cookie
Tests/
  PointFreeKitTests/       # парсеры, рендер, кэш, сессия, инструменты
  Fixtures/                # синтетические HTML/JSON
docs/superpowers/{specs,plans}/
```

## Инструменты MCP

Все инструменты возвращают один текстовый блок markdown. Ошибки возвращаются с `isError: true` и понятным текстом.

### `searchPointFree`

Вход: `query` (обязательно), `scope` (`dialogue` | `code` | `titles`, по умолчанию не задаётся), `access` (`free` | `subscriber-only`), `sort` (`newest` | `oldest`).
Источник: `GET /search?q=…&scope=…&access=…&sort=…`, без авторизации.
Выход: для каждого найденного эпизода — номер, название, ссылка, флаг доступа, сниппет с выделенным совпадением, список глав-совпадений с таймкодом и ссылкой вида `/episodes/ep381-…#t349`. Сверху общее число результатов.

### `fetchEpisode`

Вход: `episode` (обязательно; номер `381`, slug `ep381-designing-for-isolation-naively`, либо полный URL, включая `#t349`), `section` (необязательно; таймкод `t349`, `5:49` или slug главы `introduction`).
Источник: страница `/episodes/{slug-or-id}` с cookie сессии, если она есть; метаданные из `GET /api/episodes/{id}`.
Выход: шапка (название, номер, дата, длительность, доступ, blurb, ссылка на эпизод, ссылка на папку кода `https://github.com/pointfreeco/episode-code-samples/tree/main/{codeSampleDirectory}`, список референсов), затем транскрипт: главы как `## Заголовок [m:ss](url#tNNN)`, абзацы, код в блоках с языком `swift`. При `section` — только выбранная глава плюс шапка.
Если эпизод платный и в ответе нет тела транскрипта, инструмент возвращает ошибку «Требуется вход: вызовите инструмент login».

### `listEpisodes`

Вход: `filter` (подстрока названия, необязательно), `limit` (по умолчанию 50).
Источник: `GET /api/episodes`.
Выход: по строке на эпизод, новые сверху: номер, название, дата, длительность, доступ.

### `fetchCollection`

Вход: `slug` (необязательно), `section` (необязательно, только вместе со `slug`).
Источник: `/collections`, `/collections/{slug}` и `/collections/{slug}/{section}`, без авторизации. Страница коллекции содержит только список секций, эпизоды лежат на странице секции.
Выход: без аргументов — список коллекций с описанием; со `slug` — секции коллекции; со `slug` и `section` — группы эпизодов секции («Core lessons», «Related content») с номерами, длительностью и ссылками.

### `login`

Вход: `force` (bool, по умолчанию false).
Поведение: если сессия сохранена и проверка проходит — сообщает, до какого момента она действительна. Иначе (или при `force`) запускает дочерний процесс `pointfree-mcp login` (тот же исполняемый файл), ждёт завершения до 5 минут, перечитывает сессию и сообщает результат.

## Авторизация

- Сайт хранит сессию в cookie `pf_session` (домен `www.pointfree.co`, срок 7 дней, HttpOnly). Обновления cookie сервер не выдаёт, поэтому раз в 7 дней нужен повторный вход.
- `pointfree-mcp login` создаёт `NSApplication` с политикой `.regular`, окно с `WKWebView` на `https://www.pointfree.co/login`. `WKWebsiteDataStore` — постоянный, поэтому GitHub запоминает пользователя и повторный вход сводится к одному клику.
- Наблюдатель `WKHTTPCookieStoreObserver` при каждом изменении ищет cookie `pf_session` для `www.pointfree.co`. Найдя её, команда проверяет сессию запросом с этой cookie к странице `/account` (успех: HTTP 200 без редиректа на `/login`), сохраняет и закрывает окно с кодом 0. Таймаут ожидания 5 минут, закрытие окна пользователем — код 1.
- Хранилище: `~/.pointfree-mcp/session.json` с правами 0600, поля `cookie`, `expiresAt`, `savedAt`. Переопределяется переменной `POINTFREE_MCP_HOME`.
- Fallback: `pointfree-mcp login --cookie <value>` сохраняет значение без окна после той же проверки.
- `pointfree-mcp logout` удаляет файл. `pointfree-mcp status` печатает состояние сессии.

## Сеть и кэш

- `HTTPClient` — dependency с методом `data(for: URLRequest)`; live-реализация на `URLSession` с таймаутом 20 с и User-Agent `pointfree-mcp/<version>`.
- `PointFreeClient` — dependency поверх `HTTPClient` и `SessionStore`: `episodes()`, `episode(id)`, `episodePage(ref)`, `search(query, scope, access, sort)`, `collections()`, `collection(slug)`. Cookie добавляется только для запросов к `www.pointfree.co`.
- `MemoryCache`: единый TTL 1 ч для всех ответов сайта, не больше 50 записей, вытеснение старейшей. Кэш только в памяти процесса.

## Разбор HTML

Классы CSS на сайте хэшированы, парсеры опираются только на семантику:

- Поиск: карточка эпизода — `h4 > a[href^="/episodes/"]`; сниппет — соседний `p` с `<mark>`; главы — `a[href*="#t"]` с текстом «Название (m:ss)».
- Страница эпизода: главы — `a[id]` (пустой якорь) и следующий `h4`; таймкоды — `div[id^="t"] > a[data-timestamp]`; абзацы — `p`; код — `pre > code`. Тело транскрипта — участок документа от первого якоря главы до конца ближайшего общего контейнера. Для платного эпизода без сессии в теле нет `pre` и абзацев, есть только оглавление; это признак «требуется вход».
- Коллекции: ссылки `a[href^="/collections/"]` и заголовки секций.
- Если парсер не нашёл ожидаемой структуры, инструмент возвращает ошибку «Разметка сайта изменилась» с URL, сервер продолжает работать.

## Обработка ошибок

| Ситуация | Ответ инструмента |
| --- | --- |
| Нет сети, таймаут, 5xx | `isError`, текст с кодом и URL |
| 404 эпизода/коллекции | `isError`, «не найдено» |
| Платный эпизод без сессии | `isError`, «вызовите login» |
| Сессия есть, но сайт вернул только оглавление | `isError`, «сессия истекла, вызовите login» и удаление сохранённой сессии |
| Неизвестный аргумент | `isError`, описание допустимых значений |

## Тестирование

- Unit: парсеры на синтетических фикстурах, рендер markdown, кэш (TTL, лимит), `SessionStore` (права файла, чтение/запись), разбор аргументов инструментов, `login`-обработчик с подменённым запуском процесса.
- Все внешние эффекты — dependencies (`HTTPClient`, `SessionStore`, `ProcessRunner`, `Date`, `ContinuousClock`), в тестах подменяются.
- Живые проверки: `POINTFREE_LIVE=1 swift test` включает тесты, которые ходят на сайт (без сессии: поиск, API, бесплатный эпизод; с сессией из файла: платный эпизод).
- Ручная проверка: `claude mcp add pointfree -- <path>/.build/release/pointfree-mcp serve`, затем вызовы из Claude Code.

## Вне первой версии

Инструмент для кода эпизодов с GitHub, Homebrew-формула, дисковый кэш, HTTP-транспорт, Linux.
