#!/bin/bash
set -e

BACKUP_DIR="/app/backup"

echo "===== 롤백 시작: $(date) ====="

# 1. 서비스 중단
echo "[1/4] 서비스 중단 중..."
sudo systemctl stop spring-boot || true
pm2 stop nextjs || true

# 2. 백업본 복원
echo "[2/4] 백업본 복원 중..."
[ -f "$BACKUP_DIR/app.jar.bak" ] && cp "$BACKUP_DIR/app.jar.bak" /app/backend/app.jar
[ -d "$BACKUP_DIR/.next.bak" ] && rm -rf /app/frontend/.next && cp -r "$BACKUP_DIR/.next.bak" /app/frontend/.next
echo "✓ 복원 완료"

# 3. 서비스 재시작
echo "[3/4] 서비스 재시작 중..."
sudo systemctl restart spring-boot
pm2 restart nextjs
sleep 5

# 4. Health Check
echo "[4/4] Health Check 중..."
sleep 10  # 애플리케이션 초기화 대기

BE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health || echo "000")
FE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || echo "000")

[ "$BE_STATUS" == "200" ] && echo "✓ Backend OK" || echo "✗ Backend 실패 ($BE_STATUS)"
[ "$FE_STATUS" == "200" ] && echo "✓ Frontend OK" || echo "✗ Frontend 실패 ($FE_STATUS)"

echo "===== 롤백 완료: $(date) ====="
