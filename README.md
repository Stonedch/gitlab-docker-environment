Password

```bash
$ docker-compose exec -t gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

Backup create

```bash
$ docker-compose exec -t gitlab gitlab-backup create
```

$ docker-compose exec -t gitlab chown git:git /var/opt/gitlab/backups/1762504061_2025_11_07_18.3.5-ee_gitlab_backup.tar

$ docker-compose exec -t gitlab gitlab-backup restore BACKUP=1762504061_2025_11_07_18.3.5-ee

2025-11-07 09:00:46 UTC -- Warning: Your gitlab.rb and gitlab-secrets.json files contain sensitive data 
and are not included in this backup. You will need to restore these files manually.

$ docker-compose exec -t gitlab gitlab-rake "gitlab:password:reset"
