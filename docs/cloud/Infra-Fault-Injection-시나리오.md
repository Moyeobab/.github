## 개요

인프라 레이어(EC2 인스턴스, 컨테이너, 네트워크, 가용 영역)에 직접 장애를 주입하여 시스템의 자동 복구 능력과 RTO를 검증하는 카오스 엔지니어링 시나리오다.

**인프라 Fault Injection의 범위**는 다음과 같다.
- EC2 인스턴스 또는 컨테이너 종료
- 네트워크 레이턴시/패킷 손실 주입 (`aws:network:latency`)
- AZ 격리 (`aws:network:disrupt-connectivity`)

Application Fault Injection(애플리케이션 프로세스 레이어 장애)과 구분되며, 두 문서는 독립적으로 관리한다.

각 시나리오는 정상 상태 기준선(Steady State)을 기준으로 "장애 주입 후 SLO를 위반했는가"를 판단한다.

---

## AWS FIS 사용 이유

수동으로 인스턴스를 종료하거나 SSH로 직접 명령어를 실행하는 방식은 실수 위험이 있고 재현성이 낮다.

AWS FIS를 사용하는 이유는 다음과 같다.

- **안전한 실험 환경**: Stop Condition(CloudWatch Alarm)을 설정하면 SLO 임계값 초과 시 실험이 자동 중단됨
- **AWS 리소스와 네이티브 통합**: EC2, ASG, 네트워크 등 AWS 리소스를 직접 타겟으로 지정 가능. 별도 에이전트 불필요
- **재현 가능한 실험 템플릿**: 실험을 템플릿으로 저장하여 동일한 조건으로 반복 실행 가능
- **실험 범위(Blast Radius) 제어**: 태그 기반으로 타겟 리소스를 정밀하게 지정하여 의도치 않은 영향 최소화
- **실험 이력 관리**: 콘솔에서 실험 실행 이력, 결과, 중단 사유를 기록으로 남길 수 있음

---

## 모여밥 Critical Path

```
로그인(Kakao OAuth)
  → 모임 조회 (GET /api/v1/meetings)
  → 투표 후보 조회 (GET /api/v1/meetings/{meetingId}/votes/{voteId}/candidates)
  → 투표 제출 (POST /api/v1/meetings/{meetingId}/votes/{voteId}/submissions)
  → 최종 선택 (POST /api/v1/meetings/{meetingId}/votes/{voteId}/final-selection)
```

---

## 장애 감지 흐름

```
장애 주입 (AWS FIS 실험 시작)
  → Grafana Alert 발동 (Error Rate > 0.5%, Latency P95 임계값 초과)
  → Discord 알림 수신
  → Grafana 대시보드에서 이상 시점 확인
  → Data Link 클릭 → Loki에서 해당 시간대 ERROR 로그 드릴다운
  → traceId로 특정 요청 전체 흐름 추적
```

---

## 시나리오 실행 순서

영향 범위가 작고 격리된 것부터 시작하여 복합 영향 순으로 진행한다.

| 순서 | 시나리오 | 영향 범위 | Critical Path 영향 구간 | FIS Action |
|------|---------|----------|----------------------|------------|
| 1 | Redis Sentinel Primary 다운 | 세션/채팅 | 로그인, 채팅 | `aws:ssm:send-command` |
| 2 | PostgreSQL Primary EC2 종료 | 서비스 전체 | Critical Path 전 구간 | `aws:ec2:terminate-instances` |
| 3 | Backend → DB 구간 네트워크 지연 | 서비스 전체 | Critical Path 전 구간 | `aws:network:latency` |
| 4 | Backend ASG 인스턴스 종료 | 서비스 전체 | Critical Path 전 구간 | `aws:ec2:terminate-instances` |
| 5 | AZ 격리 (ap-northeast-2a) | 서비스 전체 | Critical Path 전 구간 | `aws:network:disrupt-connectivity` |
| 6 | RunPod OCR 서버 다운 | OCR 기능 | 정산(영수증 처리) | 수동 (FIS 미지원 외부 서비스) |

---

## 시나리오 1: Redis Sentinel Primary 다운

### 가설

Redis Primary 컨테이너가 다운되더라도 Sentinel 자동 페일오버로 60초 이내 복구되며, SLO(Error Rate 99.5%)를 위반하지 않는다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| `POST /api/v1/auth/refresh` | 세션 토큰 조회 실패 가능 | 페일오버 완료까지 일시 불가 |
| `GET /api/v2/meetings/{meetingId}/messages` | 채팅 메시지 조회 실패 가능 | 페일오버 완료까지 일시 중단 |
| `POST /api/v2/meetings/{meetingId}/read-pointer` | 읽음 처리 실패 가능 | 페일오버 완료까지 일시 중단 |

### Steady State

| 지표 | 기준 |
|------|------|
| Redis 가용성 | `redis_up` = 1 |
| RTO | < 60s |
| Backend Error Rate | < 0.5% |
| Backend Latency P95 | < 500ms |

### AWS FIS 실험 구성

```
Action        : aws:ssm:send-command
Target        : moyeobab-prod-v2-redis-primary (10.0.2.20)
Document      : AWS-RunShellScript
Command       : docker stop redis-redis-1
Duration      : PT2M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> 주의: `AWSFIS-Run-Kill-Process`는 Docker 컨테이너 내부 프로세스에 직접 접근 불가. `AWS-RunShellScript`로 `docker stop` 명령 실행.

### 검증 항목

- [ ] Sentinel이 Standby를 새 Primary로 자동 승격하는가
- [ ] RTO가 SLO(60s) 이내인가
- [ ] Backend Error Rate가 SLO(0.5%) 이내인가
- [ ] Backend가 새 Primary에 자동 재연결되는가
- [ ] Grafana `redis_up` 메트릭이 0으로 떨어졌다가 복구되는가
- [ ] Discord Alert가 발송되는가

### 모니터링 포인트

- Grafana: Redis 가용성 패널, Backend Error Rate 패널
- Loki: `{container="backend-app"} |= "RedisConnectionException"`

### 실험 완료 후 복구 절차

```bash
docker start redis-redis-1
docker exec redis-sentinel-redis-sentinel-1 redis-cli -p 26379 sentinel slaves mymaster
```

> 참고: 실험 후 Primary/Standby 역할이 바뀐 상태로 유지됨. 롤백 필요 시 `sentinel failover mymaster` 수동 실행.

---

## 시나리오 2: PostgreSQL Primary EC2 종료

### 가설

PostgreSQL Primary EC2가 종료되더라도 수동 승격 절차를 통해 RTO(5분) 이내에 복구되며, 복구 후 SLO를 위반하지 않는다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| `GET /api/v1/meetings` | 모임 목록 조회 실패 | 5xx |
| `GET /api/v1/meetings/{meetingId}/votes/{voteId}/candidates` | 투표 후보 조회 실패 | 5xx |
| `POST /api/v1/meetings/{meetingId}/votes/{voteId}/submissions` | 투표 제출 실패 | 5xx |
| `POST /api/v1/meetings/{meetingId}/settlement/ocr` | 정산 트리거 실패 | 5xx |

### Steady State

| 지표 | 기준 |
|------|------|
| DB 가용성 | `pg_up` = 1 |
| RTO | < 5분 (수동 승격 완료까지) |
| Backend Error Rate | 복구 후 < 0.5% |
| Backend Latency P95 | 복구 후 < 500ms |

### AWS FIS 실험 구성

```
Action        : aws:ec2:terminate-instances
Target        : moyeobab-prod-v2-postgresql-primary (인스턴스 ID 직접 지정)
Duration      : PT10M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

### 검증 항목

- [ ] Primary 종료 후 Backend에서 DB 연결 오류(5xx)가 발생하는가
- [ ] Grafana `pg_up` 메트릭이 0으로 감지되는가
- [ ] Discord Alert가 발송되는가
- [ ] 수동 승격 완료까지 RTO(5분) 이내인가
- [ ] 승격 후 Backend가 새 Primary(Standby EC2)에 자동 재연결되는가
- [ ] 복구 후 Backend Error Rate가 SLO(0.5%) 이내로 돌아오는가

### 모니터링 포인트

- Grafana: DB 가용성 패널, Backend Error Rate 패널, Latency P95 패널
- Loki: `{container="backend-app"} |= "could not connect to server"`

### 주의사항

- 자동 페일오버 미설정으로 **수동 승격 필요** (인프라 수동 승격 절차 참고)
- 피크 타임(점심/저녁) 외 시간대에 실행할 것
- 승격 후 기존 Primary EC2 복구 시 Split-Brain 방지를 위해 Standby로 재구성 필요
- 페일오버 중 진행 중인 트랜잭션은 롤백됨

---

## 시나리오 3: Backend → DB 구간 네트워크 지연

### 가설

Backend와 PostgreSQL 사이 네트워크에 지연이 발생하면 Backend Latency P95가 SLO(500ms)를 위반하며, HikariCP 커넥션 대기로 인해 일부 요청이 타임아웃된다.

### 인프라 Fault Injection으로 분류하는 이유

`aws:network:latency`는 EC2 인스턴스의 네트워크 인터페이스(ENI) 레이어에서 패킷 지연을 주입한다. 프로세스나 포트 개입 없이 네트워크 인프라 레이어 자체에 장애를 주입하는 방식이다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| `GET /api/v1/meetings` | DB 쿼리 지연 | Latency P95 상승 |
| `POST /api/v1/meetings/{meetingId}/votes/{voteId}/submissions` | DB 쓰기 지연 | Latency P95 상승 또는 타임아웃 |
| Critical Path 전 구간 | DB 의존 API 전체 지연 | HikariCP 커넥션 대기 시 5xx 가능 |

### Steady State

| 지표 | 기준 |
|------|------|
| Backend Latency P95 | < 500ms |
| Backend Error Rate | < 0.5% |
| HikariCP pending connections | 0 |

### AWS FIS 실험 구성

```
Action        : aws:network:latency
Target        : moyeobab-prod-v2-postgresql-primary (ENI 타겟)
Sources       : Backend EC2 서브넷 (10.0.0.0/16)
Latency       : 200ms
Jitter        : 50ms
Duration      : PT5M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> `aws:network:latency`는 타겟 ENI에 들어오거나 나가는 패킷에 지연을 주입한다. DB EC2를 타겟으로 지정하면 Backend → DB 구간 전체에 영향을 준다.

### 검증 항목

- [ ] Backend Latency P95가 SLO(500ms)를 초과하는가
- [ ] HikariCP 커넥션 대기(`hikaricp.connections.pending`) 지표가 상승하는가
- [ ] Grafana Alert가 발동되는가 (Latency P95 임계값 초과)
- [ ] Discord 알림이 발송되는가
- [ ] Loki에서 slow query 또는 connection timeout 로그가 확인되는가
- [ ] 실험 종료 후 Latency P95가 정상으로 복구되는가

### 모니터링 포인트

- Grafana: Backend Latency P95 패널, HikariCP 커넥션 패널
- Loki: `{container="backend-app"} |= "timeout"`

---

## 시나리오 4: Backend ASG 인스턴스 종료

### 가설

ASG 인스턴스가 종료되더라도 ALB Health Check와 ASG 자동 복구로 SLO를 위반하지 않는다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| Critical Path 전 구간 | 일부 요청 실패 가능 | ALB가 종료된 인스턴스 제외 후 나머지로 분산 |
| `POST /api/v1/meetings/{meetingId}/votes/{voteId}/submissions` | 인스턴스 교체 중 실패 가능 | ALB 재라우팅으로 복구 |

### Steady State

| 지표 | 기준 |
|------|------|
| Backend 가용성 | `up{job=~"backend\|prod-backend"}` = 1 |
| Backend Error Rate | < 0.5% |
| Backend Latency P95 | < 500ms |

### AWS FIS 실험 구성

```
Action        : aws:ec2:terminate-instances
Target        : Backend EC2 (태그: Role=backend, 선택 모드: PERCENT(50))
Duration      : PT5M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> `PERCENT(50)`: 전체 인스턴스 중 50%만 종료하여 완전한 서비스 중단 방지

### 검증 항목

- [ ] ALB가 종료된 인스턴스를 즉시 제외하는가
- [ ] ASG가 새 인스턴스를 자동으로 생성하는가
- [ ] 새 인스턴스가 ALB Target Group에 정상 등록되는가
- [ ] Prometheus EC2 태그 기반 서비스 디스커버리가 새 인스턴스를 자동 감지하는가
- [ ] 인스턴스 교체 중 Backend Error Rate가 SLO(0.5%) 이내인가

### 모니터링 포인트

- Grafana: Backend 가용성 패널, Traffic 패널, Error Rate 패널
- Loki: `{container="backend-app"} |= "ERROR"`

### 주의사항

- 인스턴스가 2대 이상인 상태에서 실행할 것
- 피크 타임 외 시간대에 실행할 것

---

## 시나리오 5: AZ 격리 (ap-northeast-2a)

### 가설

ap-northeast-2a AZ가 격리되더라도 ALB와 ASG의 Multi-AZ 구성으로 나머지 AZ에서 트래픽을 처리하며, SLO를 위반하지 않는다.

### 인프라 Fault Injection으로 분류하는 이유

AZ 격리는 네트워크 인프라 레이어에서 특정 AZ의 인/아웃바운드 트래픽을 차단하는 방식이다. 개별 프로세스나 포트가 아닌 가용 영역 단위의 인프라 장애를 재현한다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| Critical Path 전 구간 | 2a에 배치된 인스턴스로 향하는 요청 실패 | ALB가 다른 AZ 인스턴스로 재라우팅 |

### Steady State

| 지표 | 기준 |
|------|------|
| Backend 가용성 | `up{job=~"backend\|prod-backend"}` = 1 |
| Backend Error Rate | < 0.5% |
| Backend Latency P95 | < 500ms |

### AWS FIS 실험 구성

```
Action        : aws:network:disrupt-connectivity
Target        : ap-northeast-2a 서브넷 (Backend/Recommend 서브넷)
Scope         : 인/아웃바운드 전체 차단
Duration      : PT5M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> 실행 전 현재 각 AZ에 인스턴스가 몇 대 분산되어 있는지 확인 필요. 모든 인스턴스가 2a에 몰려있으면 전체 서비스 중단으로 이어질 수 있음.

### 검증 항목

- [ ] 2a 격리 후 ALB가 해당 AZ 인스턴스를 Unhealthy로 처리하는가
- [ ] 나머지 AZ(2b, 2c) 인스턴스로 트래픽이 자동 재라우팅되는가
- [ ] Backend Error Rate가 SLO(0.5%) 이내인가
- [ ] Grafana Alert가 발동되는가
- [ ] Discord 알림이 발송되는가
- [ ] 실험 종료 후 2a 인스턴스가 다시 Healthy로 등록되는가

### 모니터링 포인트

- Grafana: Backend 가용성 패널, Traffic 패널 (AZ별 분산 확인)
- Loki: `{container="backend-app"} |= "ERROR"`

### 주의사항

- **사전 확인 필수**: AZ별 인스턴스 분산 현황 파악 후 실행
  ```bash
  aws ec2 describe-instances --filters "Name=tag:Role,Values=backend" \
    --query "Reservations[*].Instances[*].[InstanceId,Placement.AvailabilityZone]" \
    --output table
  ```
- DB EC2가 격리 대상 AZ에 있을 경우 DB 접근 불가로 이어질 수 있으므로 DB AZ 확인 후 격리 대상 AZ 결정
- 피크 타임 외 시간대에 실행할 것

---

## 시나리오 6: RunPod OCR 서버 다운

### 가설

OCR 서버가 다운되더라도 Critical Path(투표/모임)에는 영향이 없으며, OCR 요청은 `OCR_FAILED` 상태로 전환된다. OCR SLO(가용성 98%)는 복구 전까지 위반한다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| `POST /api/v1/meetings/{meetingId}/settlement/ocr` | OCR 처리 실패 | `settlementStatus: OCR_FAILED` |
| `GET /api/v1/meetings/{meetingId}/settlement/progress` | 진행 상태 오류 반환 | `error` 필드에 실패 사유 |
| `GET /api/v1/meetings` | 영향 없음 | 정상 |
| `GET /api/v1/meetings/{meetingId}/votes/{voteId}/candidates` | 영향 없음 | 정상 |

### Steady State

| 지표 | 기준 |
|------|------|
| OCR 가용성 | LangSmith 성공률 ≥ 98% |
| OCR Latency P95 | < 10s |
| Backend Error Rate | < 0.5% |
| Backend Latency P95 | < 500ms |

### 장애 주입

RunPod는 AWS 외부 서비스로 FIS 미지원. 콘솔에서 수동 중지.

```
RunPod 콘솔 → Pod 선택 → Stop
```

### 검증 항목

- [ ] OCR 요청 실패 시 `settlementStatus: OCR_FAILED`로 상태가 전환되는가
- [ ] OCR 장애가 모임 조회/투표 API에 영향을 주지 않는가
- [ ] Backend Error Rate가 SLO(0.5%) 이내인가
- [ ] LangSmith에서 트레이스가 끊기는 시점이 확인되는가
- [ ] Discord Alert가 발송되는가

### 모니터링 포인트

- LangSmith: `moyeobab-ocr` 프로젝트 성공률 확인
- Grafana: Backend Error Rate 패널
- Loki: `{container="backend-app"} |= "OCR" |= "ERROR"`

### 복구

```
RunPod 콘솔 → Pod 선택 → Start
```