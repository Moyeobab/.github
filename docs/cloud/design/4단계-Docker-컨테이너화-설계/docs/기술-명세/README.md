# 기술 구성 명세

## 컨테이너별 기술 스택

| **항목** | **Spring Boot Backend** | **FastAPI AI** | **Frontend (React+Vite)** |
| --- | --- | --- | --- |
| **베이스 이미지** | eclipse-temurin:21-jre-alpine | python:3.11-slim | nginx:alpine |
| **빌드 도구** | Gradle | requirements.txt | npm (Vite) |
| **노출 포트** | 8080 | 8000 | 80 |
| **헬스체크** | /actuator/health | /health | nginx health |
| **실행 사용자** | appuser (non-root) | appuser (non-root) | nginx (non-root) |

---

## Dockerfile Best Practices 적용

| **원칙** | **적용 내용** |
| --- | --- |
| **캐시 최적화** | 의존성 파일 먼저 복사 → 소스 코드 나중에 복사 |
| **멀티스테이지 빌드** | 빌드 환경과 실행 환경 분리 (JDK/JRE, node/nginx) |
| **최소 이미지** | alpine, slim 기반 이미지 사용 |
| **RUN 통합** | 패키지 설치 + 캐시 정리를 하나의 RUN으로 |
| **비루트 사용자** | USER 명령어로 권한 없는 사용자로 전환 |
| **ENTRYPOINT vs CMD** | ENTRYPOINT로 고정 실행 파일, CMD로 기본 인자 |

---

## Dockerfile 파일

서비스별 Dockerfile은 [`dockerfiles/`](../../dockerfiles/) 폴더에 분리되어 있습니다.

| 파일 | 대상 |
| --- | --- |
| [`Dockerfile.spring-backend`](../../dockerfiles/Dockerfile.spring-backend) | Spring Boot Backend |
| [`Dockerfile.fastapi-ai`](../../dockerfiles/Dockerfile.fastapi-ai) | FastAPI AI |
| [`Dockerfile.frontend`](../../dockerfiles/Dockerfile.frontend) | Frontend (React + Vite + Nginx) |

---

## .dockerignore 예시

### Spring Boot

```
# Git
.git
.gitignore

# Build
build/
.gradle/

# IDE
.idea/
*.iml

# Logs
*.log

# Secrets
.env
*.key
application-local.yml
```

### FastAPI

```
# Git
.git
.gitignore

# Python
__pycache__/
*.pyc
.venv/
venv/

# IDE
.idea/
.vscode/

# Secrets
.env
*.key
```

### Frontend (React + Vite)

```
# Git
.git
.gitignore

# Dependencies
node_modules/

# Build output
dist/

# Logs
*.log
npm-debug.log*

# IDE
.idea/
.vscode/

# Secrets
.env
.env.local
```

---

## Docker Compose

환경별 Docker Compose 파일은 [`compose/`](../../compose/) 폴더에 분리되어 있습니다.

### 환경별 구성 차이

| **항목** | **개발 (dev)** | **운영 (prod)** |
| --- | --- | --- |
| **목적** | 로컬 개발 환경 구성 | EC2 서버 배포 |
| **PostgreSQL** | 컨테이너 (편의성) | 호스트 설치 (external) |
| **Redis** | 컨테이너 (편의성) | 호스트 설치 (external) |
| **이미지 소스** | 로컬 빌드 (build context) | ECR Pull |
| **환경변수** | .env.dev 파일 | .env.prod 파일 |
| **네트워크** | Docker 내부 네트워크 | 호스트 네트워크 (host) |
| **재시작 정책** | no (수동) | unless-stopped (자동 복구) |

### Compose 파일

| 파일 | 환경 |
| --- | --- |
| [`docker-compose.dev.yml`](../../compose/docker-compose.dev.yml) | 개발 (dev) — 로컬 빌드, PG/Redis 컨테이너 포함 |
| [`docker-compose.prod.yml`](../../compose/docker-compose.prod.yml) | 운영 (prod) — ECR Pull, PG/Redis 호스트 외부 참조 |

### 환경변수 파일

#### .env.dev (개발 환경)

```
# Database
DB_USERNAME=tastecompass
DB_PASSWORD=dev_password_change_me

# 개발 환경에서는 Docker 내부 네트워크 사용
```

#### .env.prod (운영 환경)

```
# ECR
ECR_REGISTRY=
```

### 실행 명령어

#### 개발 환경

```bash
# 시작
docker compose -f
```

#### 운영 환경

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 시작 (특정 태그로 배포)
IMAGE_TAG=sha-a1b2c3d docker compose -f
```

### Docker Compose 요약

| **항목** | **개발 (dev)** | **운영 (prod)** |
| --- | --- | --- |
| **파일** | docker-compose.dev.yml | docker-compose.prod.yml |
| **환경변수** | .env.dev | .env.prod |
| **이미지** | 로컬 빌드 | ECR Pull (sha-xxxx) |
| **DB/Redis** | 컨테이너 | 호스트 (Private IP) |
| **재시작** | 수동 | unless-stopped |
