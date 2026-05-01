# 애플리케이션 의존성 설치 및 환경 구성 (Big Bang 배포 기준)

이 문서는 컨테이너 없이 단일 EC2에 배포하는 Big Bang 기준으로, **모든 설치/구성을 수동으로 진행한 절차**를 정리합니다.
AWS 콘솔/SSH에서 하나씩 수행한 작업을 기준으로 작성했습니다.

## 범위/전제

- OS: Ubuntu (apt 기반)
- 실행 사용자: `ubuntu` (필요 시 `sudo`)
- 배포 방식: 빌드 산출물(JAR, dist) 전달 후 systemd 재시작
- 네트워크/보안 그룹 설정은 별도 문서에서 관리

## 디렉토리/루트 기준

| 용도               | 경로                              | 비고                        |
| ------------------ | --------------------------------- | --------------------------- |
| 백엔드 앱 디렉토리 | `/home/ubuntu/app`                | `app.jar`, `env.conf`       |
| AI 서비스 레포     | `/home/ubuntu/13-team-project-ai` | recommend 서비스            |
| AI venv            | `/home/ubuntu/.venvs/recommend`   | Python 3.11                 |
| 프론트 배포 경로   | `/var/www/html`                   | 정적 서빙                   |
| Nginx 설정         | `/etc/nginx/conf.d/nginx.conf`    | 운영 설정                   |
| systemd 유닛       | `/etc/systemd/system/*.service`   | `moyeobab-api`, `recommend` |

## 설치/구성 순서 (요약)

1. 기본 패키지 설치 → 2) Java/Python 런타임 → 3) 백엔드 서비스 등록 → 4) AI 서비스 등록 → 5) 프론트 배포 → 6) Nginx/HTTPS

## 1. 기본 패키지 설치

```bash
sudo apt-get update -y
sudo apt-get install -y nginx postgresql redis-server rsync
sudo systemctl enable --now nginx
sudo systemctl enable --now postgresql
sudo systemctl enable --now redis-server
```

## 2. 런타임 설치

### Java 21 (Backend)

```bash
sudo apt-get install -y openjdk-21-jdk
java -version
```

### Python 3.11 (AI)

apt에서 3.11이 제공되면:

```bash
sudo apt-get install -y python3.11 python3.11-venv
```

apt에 3.11이 없으면(pyenv 사용):

```bash
sudo apt-get install -y \
  build-essential \
  ca-certificates \
  curl \
  git \
  libbz2-dev \
  libffi-dev \
  liblzma-dev \
  libncursesw5-dev \
  libreadline-dev \
  libsqlite3-dev \
  libssl-dev \
  libxml2-dev \
  libxmlsec1-dev \
  tk-dev \
  xz-utils \
  zlib1g-dev

sudo git clone https://github.com/pyenv/pyenv.git /opt/pyenv
export PYENV_ROOT=/opt/pyenv
export PATH="${PYENV_ROOT}/bin:${PATH}"
sudo /opt/pyenv/bin/pyenv install -s 3.11.9
sudo /opt/pyenv/bin/pyenv global 3.11.9
sudo ln -sf /opt/pyenv/versions/3.11.9/bin/python3.11 /usr/local/bin/python3.11
sudo ln -sf /opt/pyenv/versions/3.11.9/bin/pip3.11 /usr/local/bin/pip3.11
```

## 3. 백엔드 서비스 등록 (systemd)

1. 앱 디렉토리 준비 및 산출물 배치

```bash
sudo mkdir -p /home/ubuntu/app
sudo chown ubuntu:ubuntu /home/ubuntu/app
# /home/ubuntu/app/app.jar
# /home/ubuntu/app/env.conf (환경변수 파일)
```

2. systemd 유닛 생성

```bash
sudo tee /etc/systemd/system/moyeobab-api.service > /dev/null <<'EOF'
[Unit]
Description=Moyeobab API Server
After=network.target postgresql.service redis-server.service

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu/app
EnvironmentFile=-/home/ubuntu/app/env.conf
ExecStart=/usr/bin/java -jar /home/ubuntu/app/app.jar
SuccessExitStatus=143
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=moyeobab-api

[Install]
WantedBy=multi-user.target
EOF
```

3. 등록/시작

```bash
sudo systemctl daemon-reload
sudo systemctl enable moyeobab-api
sudo systemctl restart moyeobab-api
```

환경파일 예시(형식만 참고):

```text
SPRING_PROFILES_ACTIVE=prod
DB_HOST=127.0.0.1
DB_PORT=5432
```

권한 권장:

```bash
sudo chmod 600 /home/ubuntu/app/env.conf
```

## 4. AI 추천 서비스 설치/등록

1. 레포지토리 동기화

```bash
sudo apt-get install -y git curl ca-certificates
sudo -u ubuntu git clone --branch main <AI_REPO_URL> /home/ubuntu/13-team-project-ai
```

이미 디렉토리가 있다면:

```bash
sudo -u ubuntu git -C /home/ubuntu/13-team-project-ai fetch origin
sudo -u ubuntu git -C /home/ubuntu/13-team-project-ai checkout main
sudo -u ubuntu git -C /home/ubuntu/13-team-project-ai reset --hard origin/main
```

2. venv 생성 및 의존성 설치

```bash
PY_BIN="/usr/local/bin/python3.11"
if [[ ! -x "${PY_BIN}" ]]; then PY_BIN="/usr/bin/python3.11"; fi
sudo -u ubuntu "${PY_BIN}" -m venv /home/ubuntu/.venvs/recommend
sudo -u ubuntu /home/ubuntu/.venvs/recommend/bin/pip install -U pip
sudo -u ubuntu /home/ubuntu/.venvs/recommend/bin/pip install -r \
  /home/ubuntu/13-team-project-ai/services/recommend/requirements.txt
```

3. systemd 유닛 생성 및 시작

```bash
sudo tee /etc/systemd/system/recommend.service > /dev/null <<'EOF'
[Unit]
Description=Recommend API
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu/13-team-project-ai/services/recommend
Environment="PATH=/home/ubuntu/.venvs/recommend/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/home/ubuntu/.venvs/recommend/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable recommend
sudo systemctl restart recommend
```

## 5. 프론트 정적 파일 배포

1. 빌드 산출물(dist) 업로드

```bash
scp -i key.pem -r dist/ ubuntu@<SERVER_IP>:/home/ubuntu/dist
```

2. 배포 및 권한 설정

```bash
if [[ -d /var/www/html && -n "$(ls -A /var/www/html 2>/dev/null)" ]]; then
  sudo mkdir -p /var/www/html-backup
  sudo rsync -az --delete /var/www/html/ /var/www/html-backup/
fi

sudo rsync -az --delete \
  --chown=www-data:www-data \
  --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
  /home/ubuntu/dist/ /var/www/html/

sudo systemctl reload nginx
```

## 6. Nginx + HTTPS 설정

도메인이 서버 IP를 가리키고 80/443 포트가 열려 있어야 합니다.

1. 기본 설정 정리

```bash
sudo rm -f /etc/nginx/sites-enabled/default
```

2. HTTP 설정 적용 (인증서 발급 전)

```bash
sudo tee /etc/nginx/conf.d/nginx.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name moyeobab.com;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}

server {
    listen 80;
    server_name api.moyeobab.com;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sudo nginx -t
sudo systemctl reload nginx
```

3. 인증서 발급

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d moyeobab.com -d api.moyeobab.com \
  --agree-tos --email <ADMIN_EMAIL>
```

옵션:

- `--redirect` : HTTP → HTTPS 리다이렉트
- `--staging` : 스테이징 환경 사용

4. HTTPS 설정 적용

```bash
sudo tee /etc/nginx/conf.d/nginx.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name moyeobab.com;
    return 301 https://$host$request_uri;
}

server {
    listen 80;
    server_name api.moyeobab.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name moyeobab.com;

    ssl_certificate     /etc/letsencrypt/live/moyeobab.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/moyeobab.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}

server {
    listen 443 ssl http2;
    server_name api.moyeobab.com;

    ssl_certificate     /etc/letsencrypt/live/moyeobab.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/moyeobab.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sudo nginx -t
sudo systemctl reload nginx
```

## 7. 보안/설정 메모

- `env.conf`는 민감정보 포함 가능 → 권한 `chmod 600` 권장
- Redis 비밀번호 설정(선택):
  1. `sudoedit /etc/redis/redis.conf`
  2. `requirepass <STRONG_PASSWORD>` 추가
  3. `sudo systemctl restart redis-server`
  4. `redis-cli -a '<STRONG_PASSWORD>' ping`

## 8. 서비스/포트 요약

| 서비스                 | 포트    | 비고                     |
| ---------------------- | ------- | ------------------------ |
| Nginx                  | 80, 443 | 프론트 정적 + API 프록시 |
| Backend (moyeobab-api) | 8080    | Spring Boot              |
| AI (recommend)         | 8000    | FastAPI(Uvicorn)         |
| PostgreSQL             | 5432    | 기본 포트                |
| Redis                  | 6379    | 기본 포트                |

## 9. 결정 사항 요약

- Systemd 채택: 백엔드/AI 모두 systemd로 관리, `Restart=always` 사용
- 서비스명 통일: 백엔드 서비스명은 `moyeobab-api`로 고정
- 환경변수 파일 사용: `/home/ubuntu/app/env.conf` 기반 주입
- Java 21 사용: Gradle toolchain 요구사항 충족 목적
- Nginx 구성: 프론트 정적 서빙 + API 리버스 프록시 기본
- HTTPS 발급 흐름 단순화: `certbot --nginx` 기반으로 구성