#!/bin/bash
set -e

echo "===== 배포 시작: $(date) ====="

# 1. 파일 확인
echo "[1/4] 배포 파일 확인 중..."
[ ! -f /app/backend/app.jar ] && echo "✗ Backend jar 없음!" && exit 1
[ ! -d /app/frontend/.next ] && echo "✗ Frontend .next 없음!" && exit 1
echo "✓ 배포 파일 확인 완료"

# 2. Backend 재시작 (systemd)
echo "[2/4] Backend 재시작 중..."
sudo systemctl restart spring-boot
echo "✓ Backend 재시작 완료 - 다운타임 시작"

# 3. Frontend 재시작 (pm2)
echo "[3/4] Frontend 재시작 중..."
pm2 restart nextjs
sleep 5
echo "✓ Frontend 재시작 완료 - 다운타임 종료"

# 4. Health Check
echo "[4/4] Health Check 중..."
sleep 10  # 애플리케이션 초기화 대기

BE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health || echo "000")
FE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || echo "000")

[ "$BE_STATUS" == "200" ] && echo "✓ Backend OK" || echo "✗ Backend 실패 ($BE_STATUS)"
[ "$FE_STATUS" == "200" ] && echo "✓ Frontend OK" || echo "✗ Frontend 실패 ($FE_STATUS)"

echo "===== 배포 완료: $(date) ====="
