#!/bin/bash
set -e

APP_JAR="app.jar"
BACKUP_JAR="backup/app.jar.backup"

echo "롤백 시작..."

# 현재 프로세스 종료
PID=$(pgrep -f "$APP_JAR" || true)
if [ -n "$PID" ]; then
    echo "프로세스 종료 중... (PID: $PID)"
    kill -9 $PID
    sleep 2
fi

# 백업 확인
if [ ! -f "$BACKUP_JAR" ]; then
    echo "백업 파일 없음"
    exit 1
fi

# 복원
cp $BACKUP_JAR $APP_JAR
echo "백업 복원 완료"

# 재시작
nohup java -jar -Dspring.profiles.active=prod $APP_JAR > logs/app.log 2>&1 &
sleep 10

# Health Check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health)
if [ "$HTTP_CODE" = "200" ]; then
    echo "롤백 성공"
else
    echo "롤백 후 Health Check 실패"
    exit 1
fi
