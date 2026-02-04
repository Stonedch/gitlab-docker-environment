#!/bin/bash

set +e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

for cmd in curl git docker-compose; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo -e "${RED}Ошибка: команда '$cmd' не найдена. Установите её и повторите попытку.${NC}"
        exit 1
    fi
done

MODE="$1"

if [ -z "$MODE" ] || { [ "$MODE" != "export" ] && [ "$MODE" != "import" ]; }; then
    echo -e "${RED}Использование: $0 export|import${NC}"
    echo ""
    echo "  export  - выгрузить все репозитории из текущего GitLab в зеркальные клоны"
    echo "  import  - запушить зеркальные клоны обратно в текущий GitLab"
    exit 1
fi

# Определяем корень проекта (где лежит .env)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

if [ ! -f .env ]; then
    echo -e "${RED}Ошибка: файл .env не найден в ${PROJECT_ROOT}${NC}"
    exit 1
fi

source .env

if [ -z "$EXTERNAL_URL" ]; then
    echo -e "${RED}Ошибка: EXTERNAL_URL не задан в .env${NC}"
    exit 1
fi

if [ -z "$GITLAB_TOKEN" ]; then
    echo -e "${RED}Ошибка: GITLAB_TOKEN не задан (нужны права api, read_repository, write_repository)${NC}"
    echo "Задайте его в .env или через переменную окружения GITLAB_TOKEN."
    exit 1
fi

GITLAB_PORT="${HTTP_PORT:-80}"
GITLAB_URL="${EXTERNAL_URL%/}"

# Если EXTERNAL_URL без порта и порт нестандартный — добавим его
if [[ ! "$EXTERNAL_URL" =~ :[0-9]+(/|$) ]] && [ "$GITLAB_PORT" != "80" ] && [ "$GITLAB_PORT" != "443" ]; then
    GITLAB_URL="${GITLAB_URL}:${GITLAB_PORT}"
fi

GITLAB_API_URL="$GITLAB_URL"

BASE_DIR="${PROJECT_ROOT}/.gitlab/repositories"

echo -e "${GREEN}GitLab импорт/экспорт репозиториев${NC}"
echo "  Режим:      $MODE"
echo "  GitLab URL: $GITLAB_API_URL"
echo "  Базовая директория зеркал: $BASE_DIR"
echo ""

urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

ENCODED_GITLAB_TOKEN="$(urlencode "${GITLAB_TOKEN}")"

if [ "$MODE" = "export" ]; then
    mkdir -p "$BASE_DIR"

    echo -e "${YELLOW}Экспорт репозиториев из GitLab...${NC}"

    PAGE=1
    TOTAL=0

    while :; do
        RESP=$(curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            "${GITLAB_API_URL}/api/v4/projects?simple=true&membership=true&per_page=100&page=${PAGE}" 2>/dev/null)

        # Пустой массив или ошибка
        if [ -z "$RESP" ] || [ "$RESP" = "[]" ]; then
            break
        fi

        if command -v jq > /dev/null 2>&1; then
            COUNT=$(echo "$RESP" | jq 'length' 2>/dev/null || echo "0")
        else
            COUNT=$(echo "$RESP" | grep -o '"id"' | wc -l)
        fi

        if [ "$COUNT" -eq 0 ]; then
            break
        fi

        echo "Страница $PAGE, проектов: $COUNT"

        if command -v jq > /dev/null 2>&1; then
            echo "$RESP" | jq -r '.[] | [.path_with_namespace, .http_url_to_repo] | @tsv' | while IFS=$'\t' read -r PATH_NS HTTP_URL; do
                [ -z "$PATH_NS" ] && continue
                TARGET_DIR="${BASE_DIR}/${PATH_NS}.git"
                AUTH_URL="$HTTP_URL"
                if [[ "$AUTH_URL" =~ ^https?:// ]]; then
                    AUTH_URL=$(echo "$AUTH_URL" | sed "s|://|://oauth2:${ENCODED_GITLAB_TOKEN}@|")
                fi

                echo -e "${YELLOW}Экспорт: ${PATH_NS}${NC}"
                mkdir -p "$(dirname "$TARGET_DIR")"
                if [ -d "$TARGET_DIR" ]; then
                    echo "  Обновление существующего зеркала..."
                    git -C "$TARGET_DIR" remote set-url origin "$AUTH_URL" 2>/dev/null
                    git -C "$TARGET_DIR" fetch --prune 2>/dev/null
                else
                    echo "  Клонирование (mirror)..."
                    git clone --mirror "$AUTH_URL" "$TARGET_DIR" 2>/dev/null
                fi
                TOTAL=$((TOTAL+1))
            done
        else
            echo "$RESP" | grep -o '"path_with_namespace":"[^"]*' | cut -d'"' -f4 | while read -r PATH_NS; do
                [ -z "$PATH_NS" ] && continue
                # Без jq не достанем корректно http_url_to_repo, поэтому пропустим
                echo -e "${YELLOW}Пропуск ${PATH_NS} (нет jq для получения URL)${NC}"
            done
        fi

        PAGE=$((PAGE+1))
    done

    echo ""
    echo -e "${GREEN}Экспорт завершён. Всего обработано: ${TOTAL} репозиториев.${NC}"
    echo "Зеркала лежат в: $BASE_DIR"
    exit 0
fi

if [ "$MODE" = "import" ]; then
    if [ ! -d "$BASE_DIR" ]; then
        echo -e "${RED}Директория с зеркалами не найдена: $BASE_DIR${NC}"
        echo "Сначала выполните: $0 export"
        exit 1
    fi

    echo -e "${YELLOW}Импорт (push) зеркальных репозиториев в GitLab...${NC}"

    TOTAL=0

    find "$BASE_DIR" -type d -name "*.git" | sort | while read -r REPO_DIR; do
        REL_PATH="${REPO_DIR#$BASE_DIR/}"
        PATH_NS="${REL_PATH%.git}"
        REPO_NAME="$(basename "$PATH_NS")"

        echo -e "${YELLOW}Обработка: ${PATH_NS}${NC}"

        URL_ENC=$(echo "$PATH_NS" | sed 's,/,%2F,g')

        PROJECT_GET=$(curl -s -w "\n%{http_code}" --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            "${GITLAB_API_URL}/api/v4/projects/${URL_ENC}" 2>/dev/null)
        PROJECT_GET_CODE=$(echo "$PROJECT_GET" | tail -n1)
        PROJECT_GET_BODY=$(echo "$PROJECT_GET" | sed '$d')

        if [ "$PROJECT_GET_CODE" = "200" ]; then
            if command -v jq > /dev/null 2>&1; then
                GITLAB_REPO_URL=$(echo "$PROJECT_GET_BODY" | jq -r '.http_url_to_repo' 2>/dev/null || echo "")
            else
                GITLAB_REPO_URL=$(echo "$PROJECT_GET_BODY" | grep -o '"http_url_to_repo":"[^"]*' | cut -d'"' -f4)
            fi
            echo "  Проект существует, обновление..."
        elif [ "$PROJECT_GET_CODE" = "404" ]; then
            echo "  Проект не найден, создание в namespace пользователя токена..."
            PROJECT_CREATE=$(curl -s -w "\n%{http_code}" --request POST \
                --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
                --header "Content-Type: application/json" \
                --data "{\"name\":\"${REPO_NAME}\",\"path\":\"${REPO_NAME}\",\"visibility\":\"private\"}" \
                "${GITLAB_API_URL}/api/v4/projects" 2>/dev/null)
            PROJECT_CREATE_CODE=$(echo "$PROJECT_CREATE" | tail -n1)
            PROJECT_CREATE_BODY=$(echo "$PROJECT_CREATE" | sed '$d')

            if [ "$PROJECT_CREATE_CODE" != "201" ] && [ "$PROJECT_CREATE_CODE" != "200" ]; then
                echo -e "  ${RED}✗ Ошибка создания проекта (HTTP ${PROJECT_CREATE_CODE})${NC}"
                echo "$PROJECT_CREATE_BODY" | head -3 | sed 's/^/    /'
                echo ""
                return
            fi

            if command -v jq > /dev/null 2>&1; then
                GITLAB_REPO_URL=$(echo "$PROJECT_CREATE_BODY" | jq -r '.http_url_to_repo' 2>/dev/null || echo "")
            else
                GITLAB_REPO_URL=$(echo "$PROJECT_CREATE_BODY" | grep -o '"http_url_to_repo":"[^"]*' | cut -d'"' -f4)
            fi

            echo -e "  ${GREEN}✓ Проект создан${NC}"
        else
            echo -e "  ${RED}✗ Ошибка запроса к GitLab (HTTP ${PROJECT_GET_CODE})${NC}"
            echo "$PROJECT_GET_BODY" | head -3 | sed 's/^/    /'
            echo ""
            return
        fi

        if [ -z "$GITLAB_REPO_URL" ] || [ "$GITLAB_REPO_URL" = "null" ]; then
            echo -e "  ${RED}✗ Не удалось получить URL репозитория${NC}"
            echo ""
            return
        fi

        # Добавляем токен в URL
        AUTH_URL="$GITLAB_REPO_URL"
        if [[ "$AUTH_URL" =~ ^https?:// ]]; then
            AUTH_URL=$(echo "$AUTH_URL" | sed "s|://|://oauth2:${ENCODED_GITLAB_TOKEN}@|")
        fi

        echo "  Push в GitLab..."
        (
            cd "$REPO_DIR" || exit 1
            git remote set-url origin "$AUTH_URL" 2>/dev/null
            git push --mirror origin 2>/dev/null
        )

        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ Успешно отправлено${NC}"
        else
            echo -e "  ${YELLOW}⚠ Ошибка отправки (подробности см. вывод git)${NC}"
        fi

        echo ""
        TOTAL=$((TOTAL+1))
    done

    echo -e "${GREEN}Импорт завершён. Обработано зеркал: ${TOTAL}.${NC}"
    exit 0
fi

