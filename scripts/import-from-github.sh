#!/bin/bash

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Logging ---
# Определяем путь к директории логов относительно корня проекта (где находится .env)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/.logs/import"
RUN_TS="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="${LOG_DIR}/import_${RUN_TS}.log"

# Создаём директорию для логов перед перенаправлением вывода
mkdir -p "${LOG_DIR}"

# Redirect all output to log + console
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "============================================================"
echo "GitHub -> GitLab import started: ${RUN_TS}"
echo "Log file: ${LOG_FILE}"
echo "============================================================"
echo ""

# Функция для URL-encoding
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

for cmd in curl git docker-compose; do
    if ! command -v $cmd > /dev/null 2>&1; then
        echo -e "${RED}Ошибка: команда '$cmd' не найдена. Установите её и повторите попытку.${NC}"
        exit 1
    fi
done

if [ ! -f .env ]; then
    echo -e "${RED}Ошибка: файл .env не найден${NC}"
    exit 1
fi

source .env

# Аргументы (если переданы) имеют приоритет над .env
ARG_GITHUB_USER="$1"
ARG_GITHUB_TOKEN="$2"
ARG_GITLAB_TOKEN="$3"

GITHUB_USER="${ARG_GITHUB_USER:-${GITHUB_USER}}"
GITHUB_TOKEN="${ARG_GITHUB_TOKEN:-${GITHUB_TOKEN}}"

REPOS_DIR=".github/repositories"

# GitLab token можно передать:
# - 3-м аргументом
# - через переменную окружения GITLAB_TOKEN
# - через .env (GITLAB_TOKEN=...)
if [ -n "$ARG_GITLAB_TOKEN" ]; then
    GITLAB_TOKEN="$ARG_GITLAB_TOKEN"
    USE_EXISTING_TOKEN=true
elif [ -n "$GITLAB_TOKEN" ]; then
    USE_EXISTING_TOKEN=true
else
    USE_EXISTING_TOKEN=false
fi

if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}Ошибка: не заданы GITHUB_USER/GITHUB_TOKEN${NC}"
    echo ""
    echo "Укажите их одним из способов:"
    echo "  1) Аргументами:"
    echo "     $0 <GITHUB_USER> <GITHUB_TOKEN> [GITLAB_TOKEN]"
    echo "  2) В .env:"
    echo "     GITHUB_USER=... "
    echo "     GITHUB_TOKEN=... "
    echo "  3) Через переменные окружения"
    exit 1
fi

if [ -z "$EXTERNAL_URL" ]; then
    echo -e "${RED}Ошибка: EXTERNAL_URL не задан в .env${NC}"
    exit 1
fi

GITLAB_PORT="${HTTP_PORT:-80}"

# Формирование базового URL
GITLAB_URL="${EXTERNAL_URL}"
GITLAB_URL="${GITLAB_URL%/}"  # Убираем trailing slash

# Если EXTERNAL_URL не содержит порт и порт не стандартный, добавляем его
if [[ ! "$EXTERNAL_URL" =~ :[0-9]+(/|$) ]]; then
    if [ "$GITLAB_PORT" != "80" ] && [ "$GITLAB_PORT" != "443" ]; then
        # Определяем протокол
        if [[ "$EXTERNAL_URL" =~ ^https:// ]]; then
            GITLAB_URL="${EXTERNAL_URL}:${GITLAB_PORT}"
        else
            GITLAB_URL="${EXTERNAL_URL}:${GITLAB_PORT}"
        fi
    fi
fi

GITLAB_API_URL="${GITLAB_URL}"

echo -e "${GREEN}Настройки:${NC}"
echo "  GitHub User: $GITHUB_USER"
echo "  GitLab URL: $GITLAB_API_URL"
echo "  GitLab Port: ${GITLAB_PORT}"
echo "  EXTERNAL_URL из .env: ${EXTERNAL_URL}"
echo ""

echo -e "${YELLOW}Получение пароля root из GitLab...${NC}"
ROOT_PASSWORD=$(docker-compose exec -T gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | cut -d' ' -f2 || echo "")

if [ -z "$ROOT_PASSWORD" ]; then
    echo -e "${RED}Ошибка: не удалось получить пароль root. Убедитесь, что GitLab запущен и инициализирован.${NC}"
    exit 1
fi

echo -e "${GREEN}Пароль root получен${NC}"
echo ""

# Проверка доступности GitLab
echo -e "${YELLOW}Проверка доступности GitLab...${NC}"
if ! curl -s --connect-timeout 5 --max-time 10 "${GITLAB_API_URL}" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ GitLab недоступен по адресу ${GITLAB_API_URL}${NC}"
    echo "  Проверьте, что GitLab запущен: docker-compose ps"
    echo "  Или попробуйте использовать localhost вместо домена в EXTERNAL_URL"
    echo ""
fi

# Создание или использование существующего токена
if [ "$USE_EXISTING_TOKEN" = true ]; then
    echo -e "${GREEN}Используется переданный токен GitLab${NC}"
    echo ""
else
    echo -e "${YELLOW}Создание токена GitLab API...${NC}"
    TOKEN_NAME="github-import-$(date +%s)"
    TOKEN_EXPIRES=$(date -d '+1 year' -Iseconds 2>/dev/null || date -v+1y +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")

    TOKEN_RESPONSE=$(curl -s -w "\n%{http_code}" --request POST \
        --url "${GITLAB_API_URL}/api/v4/user/personal_access_tokens" \
        --header "Content-Type: application/json" \
        --user "root:${ROOT_PASSWORD}" \
        --data "{
            \"name\": \"${TOKEN_NAME}\",
            \"scopes\": [\"api\", \"write_repository\", \"read_repository\"],
            \"expires_at\": \"${TOKEN_EXPIRES}\"
        }" 2>&1)

    TOKEN_HTTP_CODE=$(echo "$TOKEN_RESPONSE" | tail -n1)
    TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | sed '$d')

    if [ "$TOKEN_HTTP_CODE" = "201" ] || [ "$TOKEN_HTTP_CODE" = "200" ]; then
        # Успешное создание токена
        if command -v jq > /dev/null 2>&1; then
            GITLAB_TOKEN=$(echo "$TOKEN_BODY" | jq -r '.token' 2>/dev/null || echo "")
        else
            GITLAB_TOKEN=$(echo "$TOKEN_BODY" | grep -o '"token":"[^"]*' | cut -d'"' -f4 || echo "")
        fi
        
        if [ -n "$GITLAB_TOKEN" ] && [ "$GITLAB_TOKEN" != "null" ]; then
            echo -e "${GREEN}✓ Токен успешно создан${NC}"
        else
            echo -e "${RED}✗ Не удалось извлечь токен из ответа${NC}"
            echo "  Ответ сервера: $(echo "$TOKEN_BODY" | head -5)"
            exit 1
        fi
    else
        # Ошибка создания токена
        echo -e "${RED}✗ Ошибка создания токена (HTTP $TOKEN_HTTP_CODE)${NC}"
        if command -v jq > /dev/null 2>&1; then
            ERROR_MSG=$(echo "$TOKEN_BODY" | jq -r '.message // .error // empty' 2>/dev/null || echo "")
        else
            ERROR_MSG=$(echo "$TOKEN_BODY" | grep -o '"message":"[^"]*' | cut -d'"' -f4 || echo "")
        fi
        
        if [ -n "$ERROR_MSG" ]; then
            echo "  Сообщение: $ERROR_MSG"
        fi
        echo "  Полный ответ:"
        echo "$TOKEN_BODY" | head -10 | sed 's/^/    /'
        echo ""
        echo "Попробуйте создать токен вручную через веб-интерфейс GitLab:"
        echo "  ${GITLAB_API_URL}/-/user_settings/personal_access_tokens"
        echo ""
        echo "Или передайте существующий токен:"
        echo "  GITLAB_TOKEN=your_token $0 $GITHUB_USER $GITHUB_TOKEN"
        echo "  $0 $GITHUB_USER $GITHUB_TOKEN your_gitlab_token"
        exit 1
    fi
fi

echo -e "${YELLOW}Проверка подключения к GitLab API...${NC}"
echo "  URL: ${GITLAB_API_URL}/api/v4/user"

USER_RESPONSE=$(curl -s -w "\n%{http_code}" --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "${GITLAB_API_URL}/api/v4/user" 2>&1)
HTTP_CODE=$(echo "$USER_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$USER_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}Ошибка: не удалось подключиться к GitLab API${NC}"
    echo "  HTTP код: $HTTP_CODE"
    if [ -n "$RESPONSE_BODY" ]; then
        echo "  Ответ: $(echo "$RESPONSE_BODY" | head -3)"
    fi
    echo ""
    if [ "$USE_EXISTING_TOKEN" = true ]; then
        echo -e "${YELLOW}Переданный токен недействителен или не имеет необходимых прав${NC}"
        echo "Создайте новый токен с правами: api, write_repository, read_repository"
        echo "  ${GITLAB_API_URL}/-/user_settings/personal_access_tokens"
    else
        echo "Проверьте:"
        echo "  1. GitLab запущен: docker-compose ps"
        echo "  2. EXTERNAL_URL в .env правильный: $EXTERNAL_URL"
        echo "  3. HTTP_PORT в .env правильный: ${HTTP_PORT:-80}"
        echo "  4. GitLab доступен по адресу: ${GITLAB_API_URL}"
        echo "  5. Токен создан успешно (проверьте вывод выше)"
    fi
    exit 1
fi
echo -e "${GREEN}Подключение к GitLab успешно${NC}"
echo ""

echo -e "${YELLOW}Получение списка репозиториев из GitHub...${NC}"
REPOS_JSON=$(curl -s --header "Authorization: Bearer ${GITHUB_TOKEN}" \
    --header "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/user/repos?per_page=100&type=all&sort=updated" || echo "[]")

if [ "$REPOS_JSON" = "[]" ] || [ -z "$REPOS_JSON" ]; then
    echo -e "${RED}Ошибка: не удалось получить список репозиториев из GitHub${NC}"
    exit 1
fi

REPO_COUNT=$(echo "$REPOS_JSON" | grep -o '"full_name"' | wc -l)
echo -e "${GREEN}Найдено репозиториев: $REPO_COUNT${NC}"
echo ""

echo -e "${YELLOW}Подготовка директории .github/repositories...${NC}"
if [ -d "$REPOS_DIR" ]; then
    rm -rf "$REPOS_DIR"
fi
mkdir -p "$REPOS_DIR"
echo -e "${GREEN}Директория подготовлена${NC}"
echo ""

if command -v jq > /dev/null 2>&1; then
    REPO_LIST=$(echo "$REPOS_JSON" | jq -r '.[].full_name' 2>/dev/null || echo "")
else
    REPO_LIST=$(echo "$REPOS_JSON" | grep -o '"full_name":"[^"]*' | cut -d'"' -f4 || echo "")
fi

if [ -z "$REPO_LIST" ]; then
    echo -e "${RED}Ошибка: не удалось распарсить список репозиториев${NC}"
    exit 1
fi

echo "$REPO_LIST" | while read -r REPO_FULL_NAME; do
    REPO_NAME=$(echo "$REPO_FULL_NAME" | cut -d'/' -f2)
    REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO_FULL_NAME}.git"
    
    echo -e "${YELLOW}Обработка: $REPO_FULL_NAME${NC}"
    
    echo "  Клонирование из GitHub..."
    if git clone --mirror "$REPO_URL" "${REPOS_DIR}/${REPO_NAME}.git" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Клонирован${NC}"
    else
        echo -e "  ${RED}✗ Ошибка клонирования${NC}"
        continue
    fi
    
    # Проверяем, существует ли проект в GitLab (и параллельно получаем URL репозитория)
    PROJECT_GET=$(curl -s -w "\n%{http_code}" --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        "${GITLAB_API_URL}/api/v4/projects/root%2F${REPO_NAME}" 2>/dev/null)
    PROJECT_GET_CODE=$(echo "$PROJECT_GET" | tail -n1)
    PROJECT_GET_BODY=$(echo "$PROJECT_GET" | sed '$d')

    if [ "$PROJECT_GET_CODE" = "200" ]; then
        echo "  Репозиторий уже существует в GitLab, обновление..."
        if command -v jq > /dev/null 2>&1; then
            GITLAB_REPO_URL=$(echo "$PROJECT_GET_BODY" | jq -r '.http_url_to_repo' 2>/dev/null || echo "")
        else
            GITLAB_REPO_URL=$(echo "$PROJECT_GET_BODY" | grep -o '"http_url_to_repo":"[^"]*' | cut -d'"' -f4)
        fi
    elif [ "$PROJECT_GET_CODE" = "404" ]; then
        echo "  Создание репозитория в GitLab..."
        PROJECT_CREATE=$(curl -s -w "\n%{http_code}" --request POST \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            --header "Content-Type: application/json" \
            --data "{\"name\":\"${REPO_NAME}\",\"visibility\":\"private\"}" \
            "${GITLAB_API_URL}/api/v4/projects" 2>/dev/null)

        PROJECT_CREATE_CODE=$(echo "$PROJECT_CREATE" | tail -n1)
        PROJECT_CREATE_BODY=$(echo "$PROJECT_CREATE" | sed '$d')

        if [ "$PROJECT_CREATE_CODE" != "201" ] && [ "$PROJECT_CREATE_CODE" != "200" ]; then
            echo -e "  ${RED}✗ Ошибка создания репозитория (HTTP ${PROJECT_CREATE_CODE})${NC}"
            echo "$PROJECT_CREATE_BODY" | head -3 | sed 's/^/    /'
            # Частый кейс: проект уже существует, но GET по root/path не вернул 200 (например, из-за прав/namespace).
            # Попробуем найти проект через search и использовать его URL.
            if echo "$PROJECT_CREATE_BODY" | grep -q "has already been taken"; then
                echo "  Похоже, проект уже существует. Пробую найти его через поиск..."
                SEARCH=$(curl -s -w "\n%{http_code}" --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
                    "${GITLAB_API_URL}/api/v4/projects?search=${REPO_NAME}&simple=true&per_page=100" 2>/dev/null)
                SEARCH_CODE=$(echo "$SEARCH" | tail -n1)
                SEARCH_BODY=$(echo "$SEARCH" | sed '$d')

                if [ "$SEARCH_CODE" = "200" ]; then
                    if command -v jq > /dev/null 2>&1; then
                        # Берём первый проект с совпадающим path
                        GITLAB_REPO_URL=$(echo "$SEARCH_BODY" | jq -r --arg p "$REPO_NAME" '.[] | select(.path==$p) | .http_url_to_repo' 2>/dev/null | head -n1)
                    else
                        # Fallback без jq: грубо берём первый http_url_to_repo из результатов
                        GITLAB_REPO_URL=$(echo "$SEARCH_BODY" | grep -o '"http_url_to_repo":"[^"]*' | head -n1 | cut -d'"' -f4)
                    fi

                    if [ -n "$GITLAB_REPO_URL" ] && [ "$GITLAB_REPO_URL" != "null" ]; then
                        echo -e "  ${GREEN}✓ Найден существующий проект${NC}"
                        # Пропускаем continue — ниже будет push
                    else
                        echo -e "  ${RED}✗ Поиск не нашёл URL репозитория${NC}"
                        continue
                    fi
                else
                    echo -e "  ${RED}✗ Ошибка поиска проекта (HTTP ${SEARCH_CODE})${NC}"
                    echo "$SEARCH_BODY" | head -3 | sed 's/^/    /'
                    continue
                fi
            else
            continue
            fi
        fi

        if [ -z "$GITLAB_REPO_URL" ] || [ "$GITLAB_REPO_URL" = "null" ]; then
            if command -v jq > /dev/null 2>&1; then
                GITLAB_REPO_URL=$(echo "$PROJECT_CREATE_BODY" | jq -r '.http_url_to_repo' 2>/dev/null || echo "")
            else
                GITLAB_REPO_URL=$(echo "$PROJECT_CREATE_BODY" | grep -o '"http_url_to_repo":"[^"]*' | cut -d'"' -f4)
            fi
            echo -e "  ${GREEN}✓ Репозиторий создан${NC}"
        fi
    else
        echo -e "  ${RED}✗ Ошибка запроса к GitLab (HTTP ${PROJECT_GET_CODE})${NC}"
        echo "$PROJECT_GET_BODY" | head -3 | sed 's/^/    /'
        continue
    fi

    # Санити-чек URL репозитория (jq может вернуть 'null')
    if [ -z "$GITLAB_REPO_URL" ] || [ "$GITLAB_REPO_URL" = "null" ]; then
        echo -e "  ${RED}✗ Не удалось получить URL репозитория из GitLab API${NC}"
        continue
    fi
    
    echo "  Отправка в GitLab..."
    cd "${REPOS_DIR}/${REPO_NAME}.git"
    
    # URL-encoding токена для использования в URL
    ENCODED_TOKEN=$(urlencode "${GITLAB_TOKEN}")
    
    if [[ "$GITLAB_REPO_URL" =~ ^https?:// ]]; then
        GITLAB_REPO_URL_WITH_AUTH=$(echo "$GITLAB_REPO_URL" | sed "s|://|://root:${ENCODED_TOKEN}@|")
    else
        GITLAB_REPO_URL_WITH_AUTH="http://root:${ENCODED_TOKEN}@${GITLAB_REPO_URL}"
    fi
    
    if git remote set-url origin "$GITLAB_REPO_URL_WITH_AUTH" 2>/dev/null; then
        PUSH_OUTPUT=$(git push --mirror origin 2>&1)
        PUSH_EXIT_CODE=$?
        
        if [ $PUSH_EXIT_CODE -eq 0 ]; then
            echo -e "  ${GREEN}✓ Успешно отправлено в GitLab${NC}"
        elif echo "$PUSH_OUTPUT" | grep -q "Everything up-to-date"; then
            echo -e "  ${GREEN}✓ Уже синхронизировано${NC}"
        else
            echo -e "  ${YELLOW}⚠ Ошибка отправки:${NC}"
            echo "$PUSH_OUTPUT" | head -3 | sed 's/^/    /'
        fi
    else
        echo -e "  ${YELLOW}⚠ Ошибка настройки remote${NC}"
    fi
    
    cd - > /dev/null
    echo ""
done

echo -e "${GREEN}Импорт завершен!${NC}"
echo ""
echo "Репозитории сохранены в: $REPOS_DIR"
echo "Репозитории доступны в GitLab: ${GITLAB_URL}"

echo ""
echo "============================================================"
echo "Import finished: $(date +%Y-%m-%d_%H-%M-%S)"
echo "Log file: ${LOG_FILE}"
echo "============================================================"
