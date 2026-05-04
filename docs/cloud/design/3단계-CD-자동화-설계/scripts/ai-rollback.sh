#!/bin/bash
set -e

DEPLOY_PATH="/home/runpod/app"
BACKUP_PATH="/home/runpod/app-backup"

echo "롤백 시작..."

# 현재 프로세스 종료
PID=$(pgrep -f "uvicorn.*main:app" || true)
if [ -n "$PID" ]; then
    echo "프로세스 종료 중... (PID: $PID)"
    kill -9 $PID
    sleep 2
fi

# 백업 확인
if [ ! -d "$BACKUP_PATH" ] || [ -z "$(ls -A $BACKUP_PATH)" ]; then
    echo "백업 파일 없음"
    exit 1
fi

# 복원
rm -rf $DEPLOY_PATH
cp -r $BACKUP_PATH $DEPLOY_PATH

# 재시작
cd $DEPLOY_PATH
source .venv/bin/activate
nohup uvicorn main:app --host 0.0.0.0 --port 8000 > logs/app.log 2>&1 &
sleep 10

# Health Check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health)
if [ "$HTTP_CODE" = "200" ]; then
    echo "롤백 성공"
else
    echo "롤백 후 Health Check 실패"
    exit 1
fi
