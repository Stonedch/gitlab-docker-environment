#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODE="$1"

if [ -z "$MODE" ] || { [ "$MODE" != "backup" ] && [ "$MODE" != "restore" ]; }; then
    echo -e "${RED}Использование: $0 backup|restore [BACKUP_ID]${NC}"
    echo ""
    echo "  backup           — создать полный бэкап (данные + конфиг-файлы) и сохранить в ./backups"
    echo "  restore [ID]     — восстановить из бэкапа (если ID не указан — берётся последний)"
    echo "                     ID — это часть имени файла до _gitlab_backup.tar"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [ ! -f docker-compose.yml ]; then
    echo -e "${RED}Не найден docker-compose.yml в ${PROJECT_ROOT}${NC}"
    exit 1
fi

if [ ! -f .env ]; then
    echo -e "${RED}Не найден .env в ${PROJECT_ROOT}${NC}"
    echo "Создайте его из .env.example и настройте перед использованием."
    exit 1
fi

source .env

BACKUPS_DIR="${PROJECT_ROOT}/backups"
HOST_BACKUPS_DIR="${PROJECT_ROOT}/gitlab/data/backups"
HOST_CONFIG_DIR="${PROJECT_ROOT}/gitlab/config"

mkdir -p "${BACKUPS_DIR}"

timestamp() {
    date +%Y-%m-%d_%H-%M-%S
}

find_latest_backup_tar() {
    if [ -d "${HOST_BACKUPS_DIR}" ]; then
        ls -1t "${HOST_BACKUPS_DIR}"/*_gitlab_backup.tar 2>/dev/null | head -n1 || true
    fi
}

if [ "$MODE" = "backup" ]; then
    echo -e "${YELLOW}Создание полного бэкапа GitLab...${NC}"
    echo "Запуск gitlab-backup create внутри контейнера."

    docker-compose exec -T gitlab gitlab-backup create

    LATEST_TAR="$(find_latest_backup_tar)"
    if [ -z "$LATEST_TAR" ]; then
        echo -e "${RED}Не удалось найти созданный бэкап в ${HOST_BACKUPS_DIR}${NC}"
        exit 1
    fi

    BASENAME="$(basename "$LATEST_TAR")"
    BACKUP_ID="${BASENAME%%_gitlab_backup.tar}"

    TS="$(timestamp)"
    TARGET_DIR="${BACKUPS_DIR}/${TS}_${BACKUP_ID}"
    mkdir -p "${TARGET_DIR}"

    echo "Копирование бэкапа:"
    echo "  из: $LATEST_TAR"
    echo "  в:  ${TARGET_DIR}/${BASENAME}"
    cp "$LATEST_TAR" "${TARGET_DIR}/${BASENAME}"

    if [ -f "${HOST_CONFIG_DIR}/gitlab.rb" ]; then
        cp "${HOST_CONFIG_DIR}/gitlab.rb" "${TARGET_DIR}/gitlab.rb"
    fi

    if [ -f "${HOST_CONFIG_DIR}/gitlab-secrets.json" ]; then
        cp "${HOST_CONFIG_DIR}/gitlab-secrets.json" "${TARGET_DIR}/gitlab-secrets.json"
    fi

    echo ""
    echo -e "${GREEN}Бэкап завершён.${NC}"
    echo "Каталог бэкапа: ${TARGET_DIR}"
    echo "Файл данных:    ${BASENAME}"
    echo "Конфиги (если были): gitlab.rb, gitlab-secrets.json"
    exit 0
fi

if [ "$MODE" = "restore" ]; then
    REQ_ID="$2"

    SELECTED_TAR=""
    SELECTED_ID=""

    if [ -n "$REQ_ID" ]; then
        CANDIDATE="$(ls -1 "${BACKUPS_DIR}"/**/"${REQ_ID}"_gitlab_backup.tar 2>/dev/null | head -n1 || true)"
        if [ -z "$CANDIDATE" ] && [ -d "${HOST_BACKUPS_DIR}" ]; then
            CANDIDATE="$(ls -1 "${HOST_BACKUPS_DIR}/${REQ_ID}"_gitlab_backup.tar 2>/dev/null | head -n1 || true)"
        fi

        if [ -z "$CANDIDATE" ]; then
            echo -e "${RED}Не найден бэкап для ID=${REQ_ID}${NC}"
            exit 1
        fi
        SELECTED_TAR="$CANDIDATE"
        SELECTED_ID="$REQ_ID"
    else
        LATEST_TAR="$(find_latest_backup_tar)"
        if [ -z "$LATEST_TAR" ]; then
            CANDIDATE="$(ls -1t "${BACKUPS_DIR}"/**/*_gitlab_backup.tar 2>/dev/null | head -n1 || true)"
            if [ -z "$CANDIDATE" ]; then
                echo -e "${RED}Не найдено ни одного бэкапа ни в ${HOST_BACKUPS_DIR}, ни в ${BACKUPS_DIR}${NC}"
                exit 1
            fi
            SELECTED_TAR="$CANDIDATE"
        else
            SELECTED_TAR="$LATEST_TAR"
        fi

        BASENAME="$(basename "$SELECTED_TAR")"
        SELECTED_ID="${BASENAME%%_gitlab_backup.tar}"
    fi

    echo -e "${YELLOW}Восстановление из бэкапа...${NC}"
    echo "Файл бэкапа: $SELECTED_TAR"
    echo "ID бэкапа:   $SELECTED_ID"
    echo ""
    echo -e "${YELLOW}ВНИМАНИЕ: текущее состояние GitLab будет перезаписано.${NC}"
    read -r -p "Продолжить? [yes/NO]: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Отменено."
        exit 0
    fi

    mkdir -p "${HOST_BACKUPS_DIR}"
    TARGET_TAR="${HOST_BACKUPS_DIR}/${SELECTED_ID}_gitlab_backup.tar"

    if [ "$SELECTED_TAR" != "$TARGET_TAR" ]; then
        echo "Копирование бэкапа в ${HOST_BACKUPS_DIR}..."
        cp "$SELECTED_TAR" "$TARGET_TAR"
    fi

    echo "Выставление прав внутри контейнера..."
    docker-compose exec -T gitlab chown git:git "/var/opt/gitlab/backups/${SELECTED_ID}_gitlab_backup.tar"

    echo "Запуск gitlab-backup restore BACKUP=${SELECTED_ID}..."
    docker-compose exec -T gitlab gitlab-backup restore "BACKUP=${SELECTED_ID}"

    echo ""
    echo -e "${GREEN}Восстановление данных завершено.${NC}"
    echo ""
    echo "Напоминание: файлы gitlab.rb и gitlab-secrets.json в стандартный бэкап не входят."
    echo "Если вы сохраняли их в каталоге ./backups, при необходимости восстановите их вручную:"
    echo "  cp ./backups/<каталог_бэкапа>/gitlab.rb gitlab/config/gitlab.rb"
    echo "  cp ./backups/<каталог_бэкапа>/gitlab-secrets.json gitlab/config/gitlab-secrets.json"
    echo "и затем выполните:"
    echo "  docker-compose exec gitlab gitlab-ctl reconfigure"
    exit 0
fi

