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

После завершения первой инициализации GitLab получите начальный пароль пользователя `root`:

```bash
cat config/initial_root_password
```

Команда приведена для `GITLAB_HOME=.`. Если указан другой путь, файл находится в `$GITLAB_HOME/config/initial_root_password`.

## Настройки окружения (.env)

| Переменная                  | Значение по умолчанию      | Назначение                           |
|----------------------------|----------------------------|--------------------------------------|
| `EXTERNAL_URL`             | `http://localhost`         | базовый URL GitLab                   |
| `HTTP_PORT`                | `80`                       | HTTP-порт на хосте                   |
| `HTTPS_PORT`               | `443`                      | HTTPS-порт на хосте                  |
| `SSH_PORT`                 | `22`                       | SSH-порт для Git                     |
| `GITLAB_HOME`              | `.`                        | корень томов `config/data/logs`      |
| `GITLAB_MEM_LIMIT`         | `2048m`                    | лимит RAM контейнера                 |
| `GITLAB_CPUS`              | `2`                        | лимит CPU контейнера                 |
| `GITLAB_SHM_SIZE`          | `64m`                      | shared memory контейнера             |
| `GITLAB_ENABLE_REGISTRY`   | `false`                    | включение Registry                   |
| `GITLAB_PUMA_WORKERS`      | `0`                        | количество Puma workers              |
| `GITLAB_PUMA_MIN_THREADS`  | `1`                        | min threads Puma                     |
| `GITLAB_PUMA_MAX_THREADS`  | `2`                        | max threads Puma                     |
| `GITLAB_SIDEKIQ_CONCURRENCY` | `5`                      | параллелизм Sidekiq                  |
