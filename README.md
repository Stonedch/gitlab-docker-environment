# GitLab в Docker Compose

Минимальный Docker Compose для GitLab CE/EE.

## Требования

- Docker, Docker Compose
- 4 ГБ RAM+, 2+ CPU, 10 ГБ+

## Быстрый старт

```bash
git clone https://github.com/your-username/gitlab-docker-compose.git
cd gitlab-docker-compose
cp .env.example .env
mkdir -p gitlab/config gitlab/data gitlab/logs
docker-compose up -d --build
```

## Скрипты

```bash
./scripts/gitlab-backup.sh backup
./scripts/gitlab-backup.sh restore [BACKUP_ID]

./scripts/import-from-github.sh [GITHUB_USER] [GITHUB_TOKEN] [GITLAB_TOKEN]

./scripts/gitlab-import-export.sh export
./scripts/gitlab-import-export.sh import
```

## Настройки окружения (.env)

| Переменная                  | Значение по умолчанию      | Назначение                           |
|----------------------------|----------------------------|--------------------------------------|
| `EXTERNAL_URL`             | `http://localhost`         | базовый URL GitLab                   |
| `HTTP_PORT`                | `80`                       | HTTP-порт на хосте                   |
| `HTTPS_PORT`               | `443`                      | HTTPS-порт на хосте                  |
| `SSH_PORT`                 | `22`                       | SSH-порт для Git                     |
| `GITLAB_HOME`              | `.`                        | корень томов `config/data/logs`      |
| `GITHUB_USER`              | пусто                      | логин GitHub для импорта             |
| `GITHUB_TOKEN`             | пусто                      | токен GitHub (classic PAT)           |
| `GITLAB_TOKEN`             | пусто                      | PAT GitLab (api, read/write repo)    |
| `GITLAB_MEM_LIMIT`         | `2048m`                    | лимит RAM контейнера                 |
| `GITLAB_CPUS`              | `2`                        | лимит CPU контейнера                 |
| `GITLAB_SHM_SIZE`          | `64m`                      | shared memory контейнера             |
| `GITLAB_ENABLE_REGISTRY`   | `false`                    | включение Registry                   |
| `GITLAB_PUMA_WORKERS`      | `0`                        | количество Puma workers              |
| `GITLAB_PUMA_MIN_THREADS`  | `1`                        | min threads Puma                     |
| `GITLAB_PUMA_MAX_THREADS`  | `2`                        | max threads Puma                     |
| `GITLAB_SIDEKIQ_CONCURRENCY` | `5`                      | параллелизм Sidekiq                  |

## Лицензия и автор

**Лицензия:** [MIT](LICENSE)  
**Автор:** [@stonedch](https://github.com/stonedch/)

