# Инфраструктура MeshPad: сборка, сеть и перенос в приложение «Поделиться»

Документ описывает, **как устроены окружение и сборка MeshPad** (Windows / Android / Linux) и **как устройства обмениваются данными по LAN**, чтобы эту же модель можно было задействовать в новом проекте — сервисе быстрой отправки файлов и папок («Поделиться»).

Источник: репозиторий MeshPad (`AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/SYNC_WIRE.md`, `docs/HUB.md`, `docs/DEVELOPMENT.md`, `scripts/build-*.ps1`).

---

## 1. Общие принципы окружения проекта

### 1.1. Стек

| Слой | Технология |
|------|------------|
| Язык | **Dart 3** |
| UI-клиент | **Flutter** (Windows, Android; Linux desktop — в CI) |
| Монорепо | **melos** (несколько пакетов в одном git-репозитории) |
| Локальная БД/индекс | **Drift** (SQLite); файлы на диске — источник истины |
| Качество кода | `dart analyze`, `dart format`, `flutter_lints` |
| Production-сеть | **только LAN** (не облако): mDNS/UDP + HTTP/HTTPS |
| Headless-сервер | `apps/meshpad_server` — AOT-бинарник (`dart compile exe`) |

Ключевые правила MeshPad, которые стоит сохранить в Share-проекте:

1. **Local-first** — данные живут на устройстве; сеть нужна для доставки, а не как единственное хранилище.
2. **Доверие через pairing** — чужие устройства в Wi‑Fi не получают доступ, пока явно не с paired PIN/QR.
3. **Разделение пакетов** — чистая логика без UI (`core`), транспорт (`p2p`), UI (`app`), опционально headless (`server`).
4. **Один wire-протокол** — не менять формат обмена без версии и документации.
5. **Платформы продукта** — Windows + Android (+ Linux как сервер/CI); iOS/macOS/Web в MeshPad сознательно вне scope.

### 1.2. Структура монорепо (шаблон для нового проекта)

```
packages/
  <product>_core/     # FS, модели, очередь отправки, crypto — без Flutter
  <product>_p2p/      # discovery, pairing, HTTP-транспорт
apps/
  <product>/          # Flutter UI + платформенные интеграции (Share, shell)
  <product>_server/   # headless Linux: приём файлов в папку / hub
scripts/              # setup, bootstrap, build-windows, build-android, deploy
docs/                 # ARCHITECTURE, SYNC_WIRE (или TRANSFER_WIRE), HUB
```

В MeshPad аналог:

| Путь | Роль |
|------|------|
| `packages/meshpad_core` | FS, Drift, sync engine, outbox, crypto |
| `packages/meshpad_p2p` | LAN transport, discovery, pairing, coordinator |
| `apps/meshpad` | Flutter UI |
| `apps/meshpad_server` | Hub + REST (dev) |

### 1.3. Ежедневный цикл разработки (Windows)

```powershell
# Первый раз
.\scripts\setup.ps1          # Flutter stable + melos
.\scripts\bootstrap.ps1      # зависимости workspace

# Каждый день
.\dev.ps1                    # запуск Windows
.\dev.ps1 -Test              # analyze + тесты
.\dev.ps1 -Device dual       # Win + Android одновременно (LAN-отладка)
```

Инструменты окружения:

| Инструмент | Зачем |
|------------|--------|
| **Git** | репозиторий |
| **Flutter stable** (см. `.fvmrc`) | SDK + Dart |
| **melos** (`dart pub global activate melos`) | bootstrap / analyze / test / скрипты сборки |
| **Android Studio / SDK + JDK** | APK |
| **Visual Studio 2022+** (Desktop C++ + **C++ ATL**) | `flutter build windows` |
| **Inno Setup 6** (`ISCC.exe`) | установщик `.exe` |
| **clang / cmake / GTK** (на Ubuntu) | `flutter build linux` |
| **avahi-daemon** (на Linux hub) | mDNS discovery |

Rust/libp2p в MeshPad **не нужен** для production (эксперименты в `native/` — архив).

---

## 2. Чем и как собираются артефакты

### 2.1. Сводная таблица

| Платформа | Что получается | Чем собирается | Скрипт / команда MeshPad |
|-----------|----------------|----------------|---------------------------|
| **Windows** | `meshpad.exe` + zip + **setup.exe** | Flutter → MSVC; упаковка **Inno Setup 6** | `.\scripts\build-windows.ps1` |
| **Android** | `app-release.apk` → `meshpad-<ver>.apk` | Flutter + Android SDK + JDK; подпись keystore | `.\scripts\build-android.ps1` |
| **Linux desktop** | Flutter Linux release | Flutter + clang/cmake/GTK | CI: `flutter build linux --release` |
| **Linux hub** | AOT `meshpad-hub` (без GUI) | **`dart compile exe`** | `dart run melos run build:hub` / `deploy-hub.ps1` |

Релизный CI (`.github/workflows/build-release.yml`) на тег `v*` прогоняет validate (analyze/format/test), затем собирает Linux desktop, APK, Windows zip+Inno, hub-бинарь.

---

### 2.2. Windows: exe + zip + установщик

**Цепочка:**

```
flutter build windows --release
  → apps/meshpad/build/windows/x64/runner/Release/meshpad.exe (+ DLL)
  → Compress-Archive → meshpad-<ver>-windows-x64.zip
  → ISCC.exe (Inno Setup 6) + scripts/windows/meshpad.iss
  → meshpad-<ver>-windows-x64-setup.exe
```

**Программы:**

1. **Flutter** — компиляция Dart/Flutter в нативный Windows runner.
2. **Visual Studio Build Tools / VS 2022+** — C++ toolchain для desktop embedding; нужен workload *Desktop development with C++* и компонент **C++ ATL** (для плагинов вроде `flutter_secure_storage_windows`).
3. **Inno Setup 6** — `ISCC.exe` (типичные пути: `Program Files (x86)\Inno Setup 6\ISCC.exe`). Установка: [jrsoftware.org](https://jrsoftware.org/isinfo.php) или `choco install innosetup`.
4. **PowerShell-скрипты** — оркестрация (`build-windows.ps1`, `package-windows-installer.ps1`).

Команда:

```powershell
.\scripts\build-windows.ps1
# или: .\dev.ps1 -Release
```

**Для Share-проекта:** тот же пайплайн подойдёт для фонового агента + UI настроек. Контекстное меню Проводника обычно добавляют **отдельным shell-расширением / COM / AppExecutionAlias + реестр**, а не только Flutter UI — Flutter-приложение может принимать путь к файлу/папке как аргумент и показывать список адресатов или сразу слать выбранному peer.

---

### 2.3. Android: APK

**Цепочка:**

```
flutter build apk --release
  → apps/meshpad/build/app/outputs/flutter-apk/app-release.apk
  → копирование в meshpad.apk + meshpad-<ver>.apk
```

**Программы / окружение:**

1. **Flutter**
2. **Android SDK** (`ANDROID_HOME` / `LOCALAPPDATA\Android\Sdk`)
3. **JDK** (в MeshPad часто JBR из Android Studio: `C:\Program Files\Android\Android Studio\jbr`)
4. **Подпись** — `android/key.properties` + keystore (`setup-android-signing.ps1`); без них APK debug-signed.

Команда:

```powershell
.\scripts\build-android.ps1
.\scripts\install-android-apk.ps1 -Build   # сборка + установка на устройство
```

**Для Share-проекта:** регистрация в системном меню «Поделиться» — Android **Share Intent / Intent Filter** (`SEND`, `SEND_MULTIPLE`, опционально `ACTION_SEND` с `EXTRA_STREAM`). После выбора MeshPad-подобного приложения открывается экран выбора **доверенного peer** (или сразу подменю, если платформа позволяет).

---

### 2.4. Linux: два разных артефакта

#### A) Desktop-клиент (как Flutter-приложение)

```bash
cd apps/meshpad
flutter build linux --release
```

Нужны: Flutter, clang, cmake, ninja, GTK 3. В MeshPad это в основном **CI**, не основной продукт.

#### B) Headless hub / «сервер, который кладёт в папку» (релевантнее для Share)

```bash
cd apps/meshpad_server
dart pub get
dart compile exe bin/meshpad_server.dart -o meshpad-hub
```

Или с Windows деплой на машину в LAN:

```powershell
.\scripts\deploy-hub.ps1   # пакует workspace, на сервере собирает AOT, ставит systemd
```

**Программы:**

| Компонент | Роль |
|-----------|------|
| **Dart SDK** (из Flutter или standalone) | `dart compile exe` → один ELF без Flutter UI |
| **systemd** | сервис `meshpad-hub.service` |
| **avahi-daemon** | mDNS (`_meshpad._tcp`) |
| **ufw / firewall** | порты discovery + sync |

Порты hub в MeshPad:

| Порт | Назначение |
|------|------------|
| `8787/tcp` | веб UI (PIN + QR) |
| `45837/udp` | discovery |
| `45838/tcp` | pairing + sync HTTP |
| `45840/tcp` | sync HTTPS (pinned cert) |

**Для Share на Linux:** логично сделать **приёмник-демон** (аналог hub): слушает LAN, после pairing принимает файлы/архивы директорий и пишет в настроенный каталог (`~/Inbox`, `/var/share/...`). UI pairing — простая веб-страница или CLI.

---

## 3. Как работает обмен по сети (модель MeshPad)

### 3.1. Картина целиком

```
┌─────────────┐     mDNS/UDP :45837      ┌─────────────┐
│  Устройство │ ◄──── discovery ──────► │  Устройство │
│  A (host)   │                          │  B (guest)  │
└──────┬──────┘                          └──────┬──────┘
       │  PIN/QR pairing HTTP :45838            │
       │  (offer → confirm → auth token)        │
       │                                        │
       │  Sync HTTP :45838 / HTTPS :45840       │
       │  catalog → push/pull notes+attachments │
       └────────────────┬───────────────────────┘
                        │
                 опционально Hub
              (store-and-forward на диске)
```

MeshPad синхронизирует **заметки** (markdown + вложения). Для Share тот же каркас можно заменить на **задания передачи файлов**, сохранив discovery + pairing + auth.

### 3.2. Discovery («снюхивание»)

- Сервис **mDNS**: тип `_meshpad._tcp` (имя сервиса можно сменить на `_myshare._tcp`).
- Дополнительно UDP-beacon на порту discovery.
- Результат: список соседей в LAN с IP, портом, `peer_id`, display name.

Ограничения среды:

- Устройства в **одной LAN/Wi‑Fi**.
- На роутере не должно быть **AP client isolation**.
- На Windows иногда нужен firewall allow-скрипт (`allow-meshpad-firewall.ps1`).
- На Linux hub — `avahi-daemon`.

### 3.3. Pairing (регистрация доверия)

Модель **один host — один guest** за сессию:

1. Host показывает **6-digit PIN** и/или **QR**:
   ```text
   meshpad://pair?host=<lan-ip>&port=<http-port>&pin=<6-digit>[&tls=<tls-port>]
   ```
2. Guest вводит PIN или сканирует QR.
3. HTTP:
   - `GET /meshpad/p2p/pairing/offer` — сверка PIN / оффер
   - `POST /meshpad/p2p/pairing/confirm` — обмен идентичностью
4. После успеха оба сохраняют peer в **trusted store**:
   - `peer_id`
   - `auth_token`
   - опционально Ed25519 `signing_public_key`
   - TLS cert pin (`tls_cert_sha256`)

Дальше запросы к sync-эндпоинтам требуют заголовков:

- `X-MeshPad-Peer-Id`
- `X-MeshPad-Auth-Token`
- (волна 2.8+) `X-MeshPad-Timestamp` + `X-MeshPad-Signature` (Ed25519)

Payload JSON может шифроваться **AES-256-GCM** ключом, выведенным из auth token (HKDF).

**Важно для UX Share:** после pairing имя устройства появляется в списке адресатов. Пере-pairing нужен при 401/403, а не «забывание» из discovery cache (в MeshPad при auth failure peer не стирают из discovery).

### 3.4. Передача данных в MeshPad (sync plane)

Не «сокет с файлом целиком сразу», а **каталог + дельты**:

1. `GET /meshpad/p2p/catalog` — список голов (id, updated_at, deleted…).
2. Сравнение с локальным каталогом (LWW / conflict copies для заметок).
3. `GET/PUT /meshpad/p2p/notes/<id>` — meta + markdown.
4. `GET/PUT .../attachments/<name>` — сырые байты; крупные — resumable (`X-MeshPad-Upload-Offset/Total/Sha256`).
5. **Outbox**: исходящее считается доставленным только когда remote подтвердил meta **и** проверил вложения (sha256).
6. **Cascade**: после успешного sync — `POST .../sync/cascade`, чтобы peer подтянул остальных (эпидемическое распространение в mesh).

Оркестрация: `LanSyncCoordinator` — параллелизм 1–2 пира, hub приоритетнее, offline = skip без падения всего batch.

Hub — **равноправный peer** с диском: устройства могут синхронизироваться с ним в разное время (store-and-forward).

### 3.5. Что переиспользовать в Share vs что переписать

| Компонент MeshPad | Для Share |
|-------------------|-----------|
| mDNS + UDP discovery | **Переиспользовать идею 1:1** |
| PIN/QR pairing + auth token + TLS pin | **Переиспользовать** |
| HTTP peer server на фиксированных портах | **Переиспользовать** |
| Catalog/note LWW sync | **Заменить** на transfer jobs (файл/дерево) |
| Outbox + sha256 verify | **Сохранить** (надёжность доставки) |
| Chunked upload headers | **Особенно важны** для больших файлов/папок |
| Drift index заметок | Опционально: очередь заданий + метаданные transfers |
| Git sync | Не нужен |

Рекомендуемый wire для Share (черновик):

```
POST /share/p2p/transfer/offer   { transfer_id, name, is_dir, size, sha256?, peer_display }
POST /share/p2p/transfer/accept
PUT  /share/p2p/transfer/<id>/blob   (stream / chunks)
GET  /share/p2p/transfer/<id>/status
```

Для **директорий**: упаковать в tar/zip на лету **или** передавать дерево файлов с относительными путями + manifest (второй вариант лучше для resume и частичных сбоев).

---

## 4. Целевой продукт «Поделиться» — как стыковать с этой инфраструктурой

### 4.1. Роли по платформам

| Платформа | UX | Техническая привязка |
|-----------|----|----------------------|
| **Windows** | Контекстное меню Проводника → подменю адресатов → отправка | Shell extension / `SendTo` / кастомный verb в реестре → запуск агента с путями `%1` / списком файлов; агент читает trusted peers |
| **Android** | Стандартное меню Share → выбор приложения → выбор пользователя (или сразу список peers) | `Intent.ACTION_SEND` / `SEND_MULTIPLE`; UI выбора peer из trusted store |
| **Linux** | Фоновый сервер: принять → сохранить в указанную папку | Headless `dart compile exe` + systemd + конфиг `inbox_dir=`; pairing через веб как у hub |

### 4.2. UX выбора адресата

Требование: *после «Поделиться» сразу видно, кому слать*.

Практика:

1. Фоновый **агент** всегда онлайн в LAN (tray на Windows, foreground service на Android, systemd на Linux).
2. Агент держит актуальный список **trusted peers** (+ online/offline из discovery).
3. Контекстное меню Windows:
   - идеально: **динамическое подменю** из имён peers (нужен shell extension, который спрашивает агент по named pipe / localhost HTTP);
   - упрощённо: пункт «Отправить через Share…» → маленькое окно со списком (быстрее внедрить на чистом Flutter).
4. Android: после Share Intent — экран «Кому» со списком trusted; при одном peer — опция «отправлять всегда ему».
5. Не paired устройства в подменю **не показывать** (только discovery для экрана pairing).

### 4.3. Произвольные файлы и папки

- Файлы: stream + chunk + sha256 (как attachments MeshPad).
- Папки: manifest относительных путей → параллельная/последовательная заливка файлов; на приёмнике воссоздать дерево в inbox.
- Лимиты: квоты диска на Linux-сервере; на мобильных — Wi‑Fi only (как SSID allowlist в MeshPad).
- Прогресс: локальный outbox job + UI уведомление.

### 4.4. Минимальный MVP на базе MeshPad-подхода

1. Скопировать каркас monorepo + melos + скрипты `setup` / `build-windows` / `build-android` / `deploy-hub`.
2. Выкинуть notes UI; оставить `p2p`: discovery, pairing, auth, HTTP server.
3. Добавить transfer API + inbox writer на Linux.
4. Windows: сначала «окно выбора peer» по аргументам командной строки; потом shell submenu.
5. Android: Intent Filter Share + экран peers.
6. Документировать порты и wire в `TRANSFER_WIRE.md` (аналог `SYNC_WIRE.md`).

---

## 5. Чеклист инструментов «что поставить с нуля»

### На машине разработчика (Windows)

- [ ] Git
- [ ] Flutter stable
- [ ] melos
- [ ] Visual Studio 2022+ (C++ desktop + ATL)
- [ ] Android Studio / SDK + устройство или эмулятор
- [ ] Inno Setup 6 (для setup.exe)
- [ ] (опционально) SSH-доступ к Linux-хосту для hub

### На Linux-сервере (приёмник)

- [ ] Ubuntu 22.04/24.04
- [ ] Dart SDK **или** готовый AOT-бинарник с CI
- [ ] avahi-daemon
- [ ] systemd unit + каталог данных / inbox
- [ ] открытые порты discovery + HTTP(S) sync/transfer

### Команды-ориентиры из MeshPad

```powershell
.\scripts\setup.ps1
.\scripts\bootstrap.ps1
.\scripts\build-windows.ps1      # exe + zip + Inno setup
.\scripts\build-android.ps1      # apk
.\scripts\deploy-hub.ps1         # Linux hub AOT на сервере
.\dev.ps1 -Test -WithFormat      # полный локальный CI перед релизом
```

```bash
# Linux hub вручную
cd apps/meshpad_server
dart compile exe bin/meshpad_server.dart -o meshpad-hub
sudo ./scripts/install-hub-ubuntu.sh ./meshpad-hub
```

---

## 6. Слабые точки и уроки MeshPad (на что смотреть в Share)

Ниже — то, что в MeshPad стоило дорого по времени и багам. Для Share это не «nice to have», а **обязательный каркас с первого MVP**.

### 6.1. Синхронизация / доставка: как лучше поступать

#### Контракт устойчивости (скопировать почти дословно)

| Ситуация | Правильное поведение | Типичная ошибка |
|----------|----------------------|-----------------|
| Один peer недоступен | Статус `partial`, остальные получают данные | Весь batch падает → «никому не ушло» |
| Один файл/задание упало | Retry только этого задания | Сброс всей очереди или молчаливый skip |
| Meta уже на peer, bytes нет | Задание **остаётся** в outbox до verify sha256 | Ack слишком рано → «файл есть в UI, байтов нет» |
| Сеть/сокет недоступен (`TransportException`) | **Не** крутить retry-счётчик outbox | Исчерпали retries за минуту офлайна |
| HTTP 401/403 | Пометить «нужен re-pair», **не** удалять peer из discovery | `forgetPeer` → устройство «пропало», хотя Wi‑Fi жив |
| Неожиданная ошибка batch | Логировать + опционально bump; отличать от transport | Один catch на всё |

В MeshPad ack outbox разрешён **только** когда remote подтвердил meta **и** все вложения (см. `sync_ack`). Для Share то же: transfer считается доставленным только после `sha256` (или эквивалента) на приёмнике.

#### Outbox-driven, не «fire-and-forget»

1. Пользователь нажал «Отправить» → запись в **локальную очередь** (файл/манифест папки, peer_id, state).
2. Фоновый цикл (debounce + periodic) пытается доставить.
3. UI показывает: queued / sending / partial / failed / delivered.
4. Не чистить failed jobs на старте приложения автоматически (в MeshPad это прятало поломки — C8). Чистка — только явным действием пользователя.

#### Частичная доставка — норма, не исключение

- Meta без bytes, 3 из 50 файлов папки, один peer из трёх — всё это должно быть **видимым** в статусе.
- Для папок: манифест + per-file state; resume с offset (как `X-MeshPad-Upload-Offset` в MeshPad).
- Не полагайтесь на «один большой zip без resume» для больших директорий — обрыв Wi‑Fi на телефоне будет частым.

#### Hub / always-on peer

Если Linux-сервер — inbox, держите его как **равноправный trusted peer**, а не «особый протокол». Устройства с разным uptime догоняют через hub (store-and-forward). Каскад (`sync/cascade`) в MeshPad помогал mesh, но для Share чаще достаточно: отправитель → выбранный peer (+ опционально копия на hub).

#### Что не смешивать

- **Discovery** (кто в сети) ≠ **Trust** (кому можно слать).
- **Transport down** ≠ **данные битые**.
- **Имя в UI** ≠ стабильный `peer_id` (имена устаревают — в MeshPad чинили отдельным sync display name).

---

### 6.2. Сеть и среда — самые частые «не баги кода»

| Проблема | Симптом | Что делать заранее |
|----------|---------|-------------------|
| **AP client isolation** на роутере | Устройства не видят друг друга | Документировать; fallback: ручной `IP:port` + PIN |
| **Windows Firewall** | Pairing/sync с телефона не проходит | Скрипт allow ports (как `allow-meshpad-firewall.ps1`), один раз от admin |
| **mDNS/avahi** | Hub «невидим» | `avahi-daemon` на Linux; не полагаться только на mDNS |
| **Гостевая Wi‑Fi / VPN** | Ложный peer / нет маршрута | SSID allowlist (Android); предупреждение в UI |
| **Рассинхрон часов** | 401 `clock_skew` при подписи | Допуск ±N минут; понятный текст «проверьте время» |
| **Подмена mDNS в чужой сети** | Фейковый host | PIN + TLS pin после pairing; не доверять одному discovery |

Для Share в контекстном меню это критично: пользователь жмёт «Отправить Васе», а сеть молчит — нужен **понятный статус**, а не пустой fail.

---

### 6.3. Pairing и безопасность — особый фокус

1. **Один host / один guest** за сессию PIN — иначе гонки и «тихий false» на confirm (в MeshPad C6).
2. Токен **не** класть в plaintext рядом с публичными метаданными peer (в MeshPad токен не в `trusted/*.json`).
3. Приватный signing key — только secure storage / отдельный файл headless.
4. 401/403 → UX «переподключить устройство», endpoint cache оставить.
5. Лимиты upload: размер, типы, rate limit на публичных API; inbox на Linux — квота диска.
6. Не выставлять hub в интернет без reverse proxy + TLS + ключа.
7. Wire format версионировать с первого дня (`TRANSFER_WIRE.md`); любое изменение — тест совместимости или bump major.

Асимметрия trust (host доверил guest, guest — нет) — отдельный класс багов (C2). После confirm **оба** должны записать полный endpoint + keys в одном транзакционном смысле.

---

### 6.4. Платформенные слабые места Share (сверх MeshPad)

| Платформа | Риск | Внимание |
|-----------|------|----------|
| **Windows shell menu** | Explorer зависает / падает от тяжёлого расширения | Shell extension только спрашивает локальный агент (named pipe / `127.0.0.1`); список peers кэшировать; таймаут короткий |
| **Windows** | Меню без актуальных peers | Агент в tray должен жить; при остановленном агенте — пункт «Share не запущен» |
| **Android Share** | Процесс убит, передача оборвалась | Foreground service / WorkManager; outbox на диске; resume |
| **Android** | Фон режется OEM | Не обещать «тихую фоновую mesh-синхронизацию всех»; Share — явная пользовательская операция + retry |
| **Linux inbox** | Коллизии имён, path traversal | Sanitize относительных путей (`../`); уникальные имена / подпапки по transfer_id |
| **Любая** | Огромные деревья (сотни тысяч мелких файлов) | Лимиты, прогресс, отмена; возможно предупреждение до старта |

---

### 6.5. Какие тесты нужны (приоритет с первого дня)

Без этого LAN-фичи «зелёные на ноутбуке» и ломаются на телефоне. В MeshPad приоритет: **package-level** с HTTP-харнессом (`LanPeerServer`), не только widget-тесты.

#### Обязательный набор для Share

| Слой | Что покрыть | Зачем |
|------|-------------|--------|
| **Core: outbox** | enqueue → fail mid-file → resume → ack только после sha256 | Главный класс багов C1/C3 |
| **Core: dirs** | манифест N файлов; один файл fail → остальные продолжают; итоговый статус partial | Папки — ваш основной кейс |
| **P2P: coordinator** | 2 peers: один unreachable, второй ok → `partial` | Нельзя ронять batch |
| **P2P: transport** | `TransportException` не bump'ает retries | Офлайн не сжигает очередь |
| **P2P: auth** | 401/403 тела причин; peer остаётся в discovery | Re-pair UX |
| **P2P: pairing** | offer/confirm HTTP codes; host+guest оба trusted | C2/C6 |
| **P2P: chunked upload** | обрыв на offset → продолжение | Большие файлы |
| **Server/hub** | принять transfer → файлы в inbox; path traversal отклонён | Linux-роль |
| **E2E pipeline** | два in-process peer server: send file/dir end-to-end | Как `pipeline_e2e_test` |
| **Property / invariant** | «ack никогда до verify» | В ROADMAP MeshPad всё ещё желательно |

#### Ручные / полуавтоматические сценарии

```text
1. Win + Android dual на одной Wi‑Fi (скрипт dual + сбор логов)
2. Firewall: до allow-скрипта / после
3. Client isolation: документированный fail + manual IP
4. Убить процесс mid-transfer → после рестарта resume
5. Hub выключен → включён → догон очереди
6. Re-pair после смены «пароля»/токена
7. Отправка папки с вложенными пустыми dirs и «странными» именами
```

Логи: один merged log с двух устройств (`CollectLogs`) экономит часы при «у меня не синхронится».

#### CI до тега

Как в MeshPad: **analyze (fatal infos) + format + unit/integration** локально (`dev.ps1 -Test -WithFormat`) **до** пуша тега. Не надеяться, что Release CI «поймает».

Benchmark (opt-in tags) — отдельно: скорость catalog/transfer на больших payload, не в каждом PR.

---

### 6.6. Архитектура и сопровождение кода

Уроки Wave 2 / debt register:

1. **Не монолиты** — `note_repository` ~1000 строк и sheets >1300 ломали скорость правок. Сразу `part` / модули: outbox, transfer, pairing UI.
2. **Граница пакетов** — `core` без Flutter; сеть в `p2p`; UI тонкий. Иначе тесты LAN требуют подъёма всего приложения.
3. **Рефактор ≠ смена семантики** — менять wire/outbox ack только вместе с тестами и записью в debt register.
4. **Stream/subscriptions** — всегда `onError` + лог (C7); иначе «тихие» обрывы discovery.
5. **Версии** — `pubspec` + константа в app + CHANGELOG синхронно; установщик/APK именовать с версией.
6. **Hub в CI** — headless-бинарь собирать в том же Release pipeline, иначе сервер отстаёт от клиентов (C10).
7. **Подпись Android** — `key.properties` с первого релиза; debug-signed APK нельзя «тихо» раздавать как production.

---

### 6.7. UX статусов (иначе поддержка утонет)

Пользователь Share не читает `SYNC_WIRE.md`. Нужно сразу:

| Событие | Что показать |
|---------|----------------|
| Peer offline | Серый адресат + «не в сети», не «ошибка отправки» |
| Partial | Сколько файлов/байт прошло, что осталось |
| Auth fail | «Нужно заново связать устройства» + кнопка pairing |
| Disk full на Linux | Явная ошибка на отправителе |
| В очереди | Можно закрыть Explorer; агент дошлёт |

В MeshPad долго игнорировали результат sync в UI (C4) — выглядело как «кнопка ничего не делает».

Для контекстного меню: после клика по адресату — toast/notify «Отправка начата» / «Share не запущен» / «Нет сети», иначе клик ощущается мёртвым.

---

### 6.8. Чеклист «не повторить» перед MVP Share

- [ ] Outbox на диске; ack только после verify
- [ ] Различие TransportException vs data/auth errors
- [ ] Partial multi-peer / multi-file
- [ ] Package-тесты с fake/real HTTP peer harness
- [ ] Dual-device ручной прогон + firewall script
- [ ] Pairing: оба конца пишут trust; 401 → re-pair UX
- [ ] Chunked resume для файлов > N МБ
- [ ] Path sanitization на приёмнике
- [ ] Документ wire + порты + threat notes
- [ ] Агент живёт отдельно от UI Explorer/Share sheet
- [ ] Release validate локально до тега
- [ ] Версия артефактов и changelog

---

### 6.9. Рекомендуемый порядок внедрения (чтобы не утонуть)

1. **P2P skeleton** — discovery + pairing + health (без UI Share).
2. **Один файл** peer↔peer + outbox + sha256 + тесты.
3. **Папка** (manifest) + partial + resume.
4. **Linux inbox** как trusted peer.
5. **Android Share Intent** + экран выбора peer.
6. **Windows** сначала «окно/tray отправка по путям»; shell submenu — когда агент стабилен.
7. Полировка: cascade/hub-only если реально нужен store-and-forward между офлайн-устройствами.

Не начинайте с shell extension и «красивого подменю» — это самая хрупкая оболочка вокруг ещё не готовой доставки.

---

## 7. Краткие выводы

1. **Сборка клиентов** — Flutter; **установщик Windows** — Inno Setup поверх `flutter build windows`; **APK** — `flutter build apk`; **Linux-сервер** — `dart compile exe`, не обязательно Flutter UI.
2. **Оркестрация** — PowerShell (`dev.ps1`, `scripts/build-*.ps1`) + melos + GitHub Actions на тегах.
3. **Сеть** — LAN discovery (mDNS/UDP) → PIN/QR pairing → HTTP(S) с token/подписью → доставка с проверкой целостности; hub как always-on peer.
4. **Для «Поделиться»** — переиспользовать discovery/pairing/auth/chunked HTTP; data plane — **transfer jobs** (файлы/директории), не notes LWW.
5. **Главный риск** — не UI, а **надёжная очередь доставки** при partial failure, офлайне и обрывах; без outbox-контракта и package-тестов проект повторит долги MeshPad (C1–C8).
6. **Среда LAN** (firewall, client isolation, mDNS) ломает демо чаще кода — закладывайте fallback и диагностику с первого дня.
7. **Порядок работ** — протокол и outbox → файлы/папки → hub inbox → Share Intent → и только потом контекстное подменю Проводника.

---

*Документ подготовлен для переноса инфраструктуры MeshPad в отдельный Share-проект. Опыт устойчивости и debt register: `AGENTS.md`, `ROADMAP.md`, `docs/SYNC_WIRE.md`, `docs/SECURITY.md`.*
