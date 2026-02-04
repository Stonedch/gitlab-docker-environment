# GitLab в Docker Compose

Готовая конфигурация Docker Compose для развёртывания GitLab (CE/EE) с PostgreSQL, Redis и Container Registry.

## Содержание

- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Сервисы](#сервисы)
- [Администрирование](#администрирование)
- [Резервное копирование](#резервное-копирование)
- [Настройка](#настройка)
- [Импорт репозиториев из GitHub в GitLab](#импорт-репозиториев-из-github-в-gitlab)
- [Экономия памяти (low-memory режим)](#экономия-памяти-low-memory-режим)

## Требования

- Docker и Docker Compose
- 4 ГБ RAM (рекомендуется 8 ГБ; для небольших инстансов можно снизить в low-memory режиме), 2+ ядра CPU, от 10 ГБ диска
- Домен, указывающий на сервер

## Быстрый старт

```bash
git clone https://github.com/your-username/gitlab-docker-compose.git
cd gitlab-docker-compose
cp .env.example .env
# В .env задайте EXTERNAL_URL (ваш домен), порты и GITLAB_HOME (каталог данных, например .)
mkdir -p gitlab/config gitlab/data gitlab/logs
docker-compose up -d --build
```

Дождитесь инициализации (несколько минут) и откройте веб-интерфейс по настроенному адресу.

## Сервисы

- **GitLab:** HTTP (80), HTTPS (443). Админ по умолчанию: `root`, пароль — см. раздел [«Администрирование»](#администрирование).
- **SSH:** порт 22 для Git.
- **PostgreSQL, Redis, Container Registry** — внутри контейнера, на том же домене.

## Администрирование

Пароль root после первого запуска:
```bash
docker-compose exec -t gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

Сброс пароля root:
```bash
docker-compose exec -t gitlab gitlab-rake "gitlab:password:reset"
```

Статус и конфиг:
```bash
docker-compose exec gitlab gitlab-ctl status
docker-compose exec gitlab cat /etc/gitlab/gitlab.rb
```

## Резервное копирование

Создать бэкап:
```bash
docker-compose exec -t gitlab gitlab-backup create
```
Файлы сохраняются в `./gitlab/data/backups/`.

Восстановление (подставьте свой ID бэкапа):
```bash
docker-compose exec -t gitlab chown git:git /var/opt/gitlab/backups/ИМЯ_ФАЙЛА_БЭКАПА.tar
docker-compose exec -t gitlab gitlab-backup restore BACKUP=ИД_БЭКАПА
```
Файлы `gitlab.rb` и `gitlab-secrets.json` в бэкап не входят — сохраняйте их отдельно.

## Настройка

Переменные в `.env` (см. `.env.example`):

| Переменная     | Описание                          |
|----------------|-----------------------------------|
| `EXTERNAL_URL` | URL GitLab (например `http://gitlab.example.com`) |
| `HTTP_PORT`    | Порт HTTP на хосте (по умолчанию 80) |
| `HTTPS_PORT`   | Порт HTTPS на хосте (443)         |
| `SSH_PORT`     | Порт SSH для Git на хосте (22)    |
| `GITLAB_HOME`  | Базовый каталог для config/data/logs (например `.`) |

Если порт 22 занят системным SSH — смените порт в `.env` или перенастройте системный SSH. Для HTTPS настройте сертификаты в GitLab.

После правок `./gitlab/config/gitlab.rb`:
```bash
docker-compose exec gitlab gitlab-ctl reconfigure
```

## Импорт репозиториев из GitHub в GitLab

Скрипт `scripts/import-from-github.sh`:

- очищает/создаёт локальную директорию `.github/repositories` и импортирует туда репозитории с GitHub (mirror clone)
- создаёт (или обновляет) проекты в вашем локальном GitLab и пушит туда содержимое (`git push --mirror`)

Директория `.github/repositories` добавлена в `.gitignore` и не попадает в репозиторий.

### Требования

- `docker-compose`, `curl`, `git`
- опционально `jq` (для более надёжного парсинга JSON)

### Запуск

1) Убедитесь, что GitLab запущен и инициализирован:

```bash
docker-compose up -d
```

2) Запустите импорт (нужны GitHub login и classic access token):

```bash
./scripts/import-from-github.sh <GITHUB_USER> <GITHUB_TOKEN>
```

Скрипт попытается **создать GitLab Personal Access Token** под `root`, используя пароль root из контейнера
(см. раздел [«Администрирование»](#администрирование)).

Если токен создать не удалось, создайте его вручную в GitLab и передайте скрипту:

```bash
GITLAB_TOKEN=<YOUR_GITLAB_TOKEN> ./scripts/import-from-github.sh <GITHUB_USER> <GITHUB_TOKEN>
```

Права токена GitLab: `api`, `write_repository`, `read_repository`.

## Экономия памяти (low-memory режим)

По умолчанию в `docker-compose.yml` включён более экономичный профиль:

- отключены встроенные Prometheus/Grafana/Alertmanager и экспортеры
- отключены Pages и Mattermost
- Container Registry по умолчанию выключен (можно включить через `.env`)
- уменьшены настройки Puma/Sidekiq
- выставлены лимиты контейнера (можно переопределить в `.env`)

Настраивается через `.env` (см. `.env.example`):

| Переменная | По умолчанию | Зачем |
|---|---:|---|
| `GITLAB_MEM_LIMIT` | `2048m` | лимит памяти контейнера |
| `GITLAB_CPUS` | `2` | лимит CPU контейнера |
| `GITLAB_SHM_SIZE` | `64m` | shared memory контейнера |
| `GITLAB_ENABLE_REGISTRY` | `false` | включить/выключить Registry |
| `GITLAB_PUMA_WORKERS` | `0` | меньше воркеров = меньше RAM |
| `GITLAB_PUMA_MIN_THREADS` | `1` | минимальные потоки Puma |
| `GITLAB_PUMA_MAX_THREADS` | `2` | максимальные потоки Puma |
| `GITLAB_SIDEKIQ_CONCURRENCY` | `5` | параллелизм Sidekiq |

---

**Лицензия:** [MIT License](LICENSE)

**Автор:** [@stonedch](https://github.com/stonedch/)
