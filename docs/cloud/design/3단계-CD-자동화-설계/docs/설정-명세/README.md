# CD 설정 명세

## 환경 변수

CD 파이프라인 내부 (yml 파일)에 저장되는 민감하지 않은 값입니다.

| 변수명 | 용도 | 예시 |
| --- | --- | --- |
| `JAR_NAME` | JAR 파일명 | `app.jar` |
| `DEPLOY_PATH` | 배포 경로 | `/home/ubuntu/app` |
| `BACKUP_PATH` | 백업 경로 | `/home/ubuntu/app/backup` |

## 시크릿 관리 도구 선택

**GitHub Secrets**는 GitHub에서 제공하는 암호화된 저장소입니다. GitHub Actions와 바로 연동되고 별도 설정 없이 사용할 수 있습니다. 무료이고 로그에 자동으로 마스킹돼서 보안도 괜찮습니다. GitHub에 의존적인 특징이 있습니다.

**AWS Secrets Manager**는 AWS에서 제공하는 관리형 비밀 저장소입니다. 버전 관리가 되고 비밀번호 자동 로테이션 기능이 있습니다. 사용량에 따라 비용이 발생하고 설정이 복잡하다는 특징이 있습니다.

**AWS Parameter Store**는 AWS에서 제공하는 파라미터 저장 서비스입니다. 무료 티어가 있어서 비용 부담을 줄일 수 있습니다. Secrets Manager보다 기능이 적고 자동 로테이션이 안 된다는 특징이 있습니다.

**HashiCorp Vault**는 오픈소스 비밀 관리 도구입니다. 보안이 강력하고 멀티클라우드 환경에서 쓸 수 있습니다. 직접 서버를 운영해야 해서 관리 부담의 특징이 있습니다.

**.env 파일**은 서버에 직접 파일로 저장하는 방식입니다. 가장 단순하지만 보안에 취약하고 여러 서버에서 관리하기 어렵다는 특징이 있습니다.

### 저희 팀은 GitHub를 사용하고 있으며 Github Actions와 바로 연동된다는 특성을 고려하여 Github Secrets를 사용했습니다.

## GitHub Secrets

### BE

| Secret명 | 용도 | 예시 |
| --- | --- | --- |
| `EC2_HOST` | EC2 퍼블릭 IP | `13.124.xxx.xxx` |
| `EC2_USER` | SSH 사용자명 | `ubuntu` |
| `EC2_SSH_KEY` | SSH 프라이빗 키 | `-----BEGIN RSA...` |
| `DISCORD_WEBHOOK_URL` | Discord 알림 Webhook | `https://discord.com/api/webhooks/...` |

### FE

| Secret명 | 용도 | 예시 |
| --- | --- | --- |
| `EC2_HOST` | EC2 퍼블릭 IP | `13.124.xxx.xxx` |
| `EC2_USER` | SSH 사용자명 | `ubuntu` |
| `EC2_SSH_KEY` | SSH 프라이빗 키 | `-----BEGIN RSA...` |
| `DISCORD_WEBHOOK_URL` | Discord 알림 Webhook | `https://discord.com/api/webhooks/...` |

### AI

| Secret명 | 용도 | 예시 |
| --- | --- | --- |
| `RUNPOD_HOST` | RunPod 호스트 | `xxx.runpod.io` |
| `RUNPOD_USER` | SSH 사용자명 | `root` |
| `RUNPOD_SSH_KEY` | SSH 프라이빗 키 | `-----BEGIN RSA...` |
| `RUNPOD_SSH_PORT` | SSH 포트 | `22222` |
| `DISCORD_WEBHOOK_URL` | Discord 알림 Webhook | `https://discord.com/api/webhooks/...` |

## 서버 디렉토리 구조

### BE (EC2)

```
/home/ubuntu/app/
├── app.jar                 # 현재 실행 중인 JAR
├── backup/
│   └── app.jar.backup      # 롤백용 백업
├── logs/
│   └── app.log             # 애플리케이션 로그
└── rollback.sh             # 수동 롤백 스크립트

```

### FE (EC2)

```
/var/www/
├── frontend/               # 현재 서비스 중인 빌드
│   ├── index.html
│   └── assets/
├── frontend-backup/        # 롤백용 백업
└── rollback.sh             # 수동 롤백 스크립트

```

### AI (RunPod)

```
/home/runpod/
├── app/                    # 현재 실행 중인 앱
│   ├── main.py
│   ├── requirements.txt
│   ├── .venv/
│   └── logs/
│       └── app.log
├── app-backup/             # 롤백용 백업
└── rollback.sh             # 수동 롤백 스크립트

```

## Smoke Test 설정 값

| 구분 | BE (Spring Boot) | FE (Nginx/SPA) | AI (FastAPI) |
| --- | --- | --- | --- |
| 최대 재시도 | 10회 | 10회 | 10회 |
| 재시도 간격 | 5초 | 3초 | 5초 |
| 타임아웃 | 10초 | 10초 | 10초 |
| 총 대기 시간 | 최대 50초 | 최대 30초 | 최대 50초 |
| Health Check 경로 | `/actuator/health` | `/` | `/health` |
| API 테스트 경로 | `/api/ping` | `-` | `/api/ping` |
| 설정 근거 | JVM 기동 및 DB 커넥션 풀 생성 시간(20~40초 예상) 고려 | 정적 파일 서빙으로 기동이 빠름 | 모델 로드 및 Cold Start 가능성 반영 |

## 포트 설정

| 서비스 | 포트 | 용도 |
| --- | --- | --- |
| Nginx | 80 | HTTP (FE 정적 파일 서빙) |
| Nginx | 443 | HTTPS (선택) |
| Spring Boot | 8080 | BE API |
| FastAPI | 8000 | AI API |
| Prometheus | 9090 | 메트릭 수집 |
| Grafana | 3000 | 대시보드 |

## 수동 롤백 스크립트

서버에 배치되는 수동 롤백 스크립트는 [`scripts/`](../../scripts/) 폴더에 분리되어 있습니다.

| 파일 | 서버 배치 경로 | 용도 |
| --- | --- | --- |
| [`be-rollback.sh`](../../scripts/be-rollback.sh) | `/home/ubuntu/app/rollback.sh` | BE 수동 롤백 |
| [`fe-rollback.sh`](../../scripts/fe-rollback.sh) | `/var/www/rollback.sh` | FE 수동 롤백 |
| [`ai-rollback.sh`](../../scripts/ai-rollback.sh) | `/home/runpod/rollback.sh` | AI 수동 롤백 |

---

# 체크리스트

## 배포 전 체크리스트

- [ ]  GitHub Secrets 설정 완료
- [ ]  EC2/RunPod SSH 접속 테스트
- [ ]  서버 디렉토리 구조 생성
- [ ]  롤백 스크립트 배치 및 실행 권한 부여 (`chmod +x rollback.sh`)
- [ ]  Nginx 설정 완료 (FE)
- [ ]  Spring Boot Actuator 설정 (BE)
- [ ]  Health Check 엔드포인트 구현
- [ ]  Discord Webhook 생성

## 배포 후 체크리스트

- [ ]  Smoke Test 통과 확인
- [ ]  Discord 알림 수신 확인
- [ ]  Grafana 메트릭 확인
