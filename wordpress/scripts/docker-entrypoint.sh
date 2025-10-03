#!/bin/bash

if ! [ -f backup-cron ]
then
  echo "Creating cron entry to start backup at: $BACKUP_TIME"
  # Note: Must use tabs with indented 'here' scripts.
  cat <<-EOF >> backup-cron
MYSQL_ENV_MYSQL_HOST=$MYSQL_ENV_MYSQL_HOST
MYSQL_ENV_MYSQL_USER=$MYSQL_ENV_MYSQL_USER
MYSQL_ENV_MYSQL_DATABASE=$MYSQL_ENV_MYSQL_DATABASE
MYSQL_ENV_MYSQL_PASSWORD=$MYSQL_ENV_MYSQL_PASSWORD
EOF

  # optionally export retention vars into crontab so cron jobs see them
  if [[ $KEEP_DAILY ]]; then echo "KEEP_DAILY=$KEEP_DAILY" >> backup-cron; fi
  if [[ $KEEP_WEEKLY ]]; then echo "KEEP_WEEKLY=$KEEP_WEEKLY" >> backup-cron; fi
  if [[ $KEEP_MONTHLY ]]; then echo "KEEP_MONTHLY=$KEEP_MONTHLY" >> backup-cron; fi
  if [[ $MIN_AGE_MINUTES ]]; then echo "MIN_AGE_MINUTES=$MIN_AGE_MINUTES" >> backup-cron; fi

  if [[ $CLEANUP_OLDER_THAN ]]
  then
    echo "CLEANUP_OLDER_THAN=$CLEANUP_OLDER_THAN" >> backup-cron
  fi

  # Backup cron job
  echo "$BACKUP_TIME backup > /backup.log" >> backup-cron

  # Cleanup cron job at 4 AM
  echo "0 4 * * * /usr/local/bin/cleanup-backups.sh >> /var/log/cleanup.log 2>&1" >> backup-cron

  crontab backup-cron
fi

echo "Current crontab:"
crontab -l

exec "$@"
