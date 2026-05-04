#!/bin/bash
set -e

DEPLOY_PATH="/var/www/frontend"
BACKUP_PATH="/var/www/frontend-backup"

echo "롤백 시작..."

# 백업 확인
if [ ! -d "$BACKUP_PATH" ] || [ -z "$(ls -A $BACKUP_PATH)" ]; then
    echo "백업 파일 없음"
    exit 1
fi

# 복원
sudo rm -rf $DEPLOY_PATH/*
sudo cp -r $BACKUP_PATH/* $DEPLOY_PATH/
sudo chown -R www-data:www-data $DEPLOY_PATH
sudo chmod -R 755 $DEPLOY_PATH

echo "롤백 성공"
