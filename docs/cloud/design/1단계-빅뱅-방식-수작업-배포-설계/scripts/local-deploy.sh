#!/bin/bash
set -e

# ===== 설정 (환경에 맞게 수정) =====
SERVER_USER="ubuntu"
SERVER_HOST="your-server-ip"
SERVER_KEY="~/.ssh/your-key.pem"

BACKEND_DIR="./backend"
FRONTEND_DIR="./frontend"
REMOTE_BACKEND="/app/backend"
REMOTE_FRONTEND="/app/frontend"
# ==================================

echo "===== 로컬 빌드 및 배포 시작: $(date) ====="

# 1. Backend 빌드
echo "[1/4] Backend 빌드 중..."
cd $BACKEND_DIR
./gradlew clean build -x test
cd ..
echo "✓ Backend 빌드 완료"

# 2. Frontend 빌드
echo "[2/4] Frontend 빌드 중..."
cd $FRONTEND_DIR
npm install && npm run build
cd ..
echo "✓ Frontend 빌드 완료"

# 3. Backend jar 전송
echo "[3/4] Backend jar 전송 중..."
scp -i $SERVER_KEY $BACKEND_DIR/build/libs/*.jar \
    $SERVER_USER@$SERVER_HOST:$REMOTE_BACKEND/app.jar
echo "✓ Backend 전송 완료"

# 4. Frontend 빌드 결과 전송
echo "[4/4] Frontend 빌드 결과 전송 중..."
scp -i $SERVER_KEY -r $FRONTEND_DIR/.next \
    $SERVER_USER@$SERVER_HOST:$REMOTE_FRONTEND/
echo "✓ Frontend 전송 완료"

echo "===== 전송 완료! ====="
echo "서버에서 deploy.sh를 실행하세요."
