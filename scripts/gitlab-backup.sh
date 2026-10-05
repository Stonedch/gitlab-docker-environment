#!/usr/bin/env bash
set -euo pipefail
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.."

usage() {
    echo "Использование: $0 backup | restore BACKUP_ID" >&2
    exit 1
}

case "${1:-}" in
    backup) [[ $# -eq 1 ]] || usage ;;
    restore) [[ $# -eq 2 && "$2" =~ ^[a-zA-Z0-9_-]+$ ]] || usage ;;
    *) usage ;;
esac

[[ -f .env ]] || { echo "Создайте .env из .env.example." >&2; exit 1; }
compose=(docker compose --project-directory "$PWD" -f "$PWD/docker-compose.yml")
"${compose[@]}" exec -T gitlab true

if [[ "$1" == backup ]]; then
    id="$(date -u +%Y%m%dT%H%M%SZ)_$$"
    dir="$PWD/backups/$id"
    mkdir -p "$dir"
    # Маркер не позволяет восстановить недокопированный бэкап.
    touch "$dir/.incomplete"
    "${compose[@]}" exec -T gitlab gitlab-backup create "BACKUP=$id"
    "${compose[@]}" cp "gitlab:/var/opt/gitlab/backups/${id}_gitlab_backup.tar" "$dir/"
    "${compose[@]}" cp gitlab:/etc/gitlab/gitlab.rb "$dir/"
    "${compose[@]}" cp gitlab:/etc/gitlab/gitlab-secrets.json "$dir/"
    cp .env docker-compose.yml "$dir/"
    rm "$dir/.incomplete"
    echo "Бэкап: $dir"
    echo "Восстановление: $0 restore $id"
    exit 0
fi

id="$2"
dir="$PWD/backups/$id"
archive="${id}_gitlab_backup.tar"
[[ -f "$dir/$archive" && ! -e "$dir/.incomplete" ]] || {
    echo "Готовый бэкап не найден: $dir" >&2
    exit 1
}

echo "Восстановление $id перезапишет текущие данные GitLab."
echo "Нужны та же версия/редакция GitLab и исходный gitlab-secrets.json."
read -r -p "Продолжить? [yes/NO]: " confirm
[[ "$confirm" == yes ]] || exit 0

"${compose[@]}" cp "$dir/$archive" "gitlab:/var/opt/gitlab/backups/$archive"
"${compose[@]}" exec -T gitlab chown git:git "/var/opt/gitlab/backups/$archive"

# Возвращаем сервисы в работу и при ошибке восстановления.
restart_services() {
    "${compose[@]}" exec -T gitlab gitlab-ctl start puma
    "${compose[@]}" exec -T gitlab gitlab-ctl start sidekiq
}
trap restart_services EXIT
"${compose[@]}" exec -T gitlab gitlab-ctl stop puma
"${compose[@]}" exec -T gitlab gitlab-ctl stop sidekiq
"${compose[@]}" exec -T gitlab gitlab-backup restore "BACKUP=$id" force=yes
restart_services
trap - EXIT
"${compose[@]}" exec -T gitlab gitlab-rake gitlab:check SANITIZE=true
echo "Восстановление завершено."
