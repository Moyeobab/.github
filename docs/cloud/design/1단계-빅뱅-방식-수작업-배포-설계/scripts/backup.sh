#!/bin/bash
set -e

BACKUP_DIR="/app/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="your_db_name"

echo "===== 배포 전 백업 시작: $TIMESTAMP ====="

mkdir -p $BACKUP_DIR

# 1. 데이터베이스 백업
echo "[1/3] DB 백업 중..."
pg_dump -U postgres -d $DB_NAME > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
echo "✓ DB 백업 완료"

# 2. Backend jar 백업
echo "[2/3] Backend 백업 중..."
[ -f /app/backend/app.jar ] && cp /app/backend/app.jar "$BACKUP_DIR/app.jar.bak"
echo "✓ Backend 백업 완료"

# 3. Frontend 빌드 결과 백업
echo "[3/3] Frontend 백업 중..."
[ -d /app/frontend/.next ] && cp -r /app/frontend/.next "$BACKUP_DIR/.next.bak"
echo "✓ Frontend 백업 완료"

echo "===== 백업 완료! ====="
