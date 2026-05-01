## 개요

인프라는 살아있는 상태에서 **애플리케이션 프로세스 레이어**에 직접 장애를 주입하여 애플리케이션 코드의 장애 대응 능력(Fallback, Timeout, 자원 고갈 처리)을 검증하는 카오스 엔지니어링 시나리오다.

**Application Fault Injection의 범위**는 다음과 같다.
- CPU/메모리 스트레스 주입 → 자원 고갈 시 애플리케이션 동작 검증 (`AWSFIS-Run-CPU-Stress`, `AWSFIS-Run-Memory-Stress`)
- 네트워크 레이턴시 주입 (프로세스 레벨) → Timeout/Fallback 처리 검증 (`AWSFIS-Run-Network-Latency`)
- 특정 포트 차단 → 서비스 간 통신 두절 시 애플리케이션 동작 검증 (`AWSFIS-Run-Network-Blackhole-Port`)

인프라 장애(EC2 종료, 네트워크 인프라 레이어 장애)와 구분되며, 두 문서는 독립적으로 관리한다.

각 시나리오는 정상 상태 기준선(Steady State)을 기준으로 "장애 주입 후 SLO를 위반했는가", 그리고 "애플리케이션이 의도한 대로 대응했는가"를 판단한다.

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
장애 주입 (SSM Document 실행)
  → Grafana Alert 발동 (Latency P95 임계값 초과, Error Rate > 0.5%)
  → Discord 알림 수신
  → Grafana 대시보드에서 이상 시점 확인
  → Data Link 클릭 → Loki에서 해당 시간대 ERROR 로그 드릴다운
  → traceId로 특정 요청 전체 흐름 추적
```

---

## 시나리오 실행 순서

| 순서 | 시나리오 | 영향 범위 | Critical Path 영향 구간 | FIS Document |
|------|---------|----------|----------------------|-------------|
| 1 | Recommend 서버 응답 지연 | 추천 기능 | 투표 후보 조회 | `AWSFIS-Run-Network-Latency` |
| 2 | Backend CPU 스트레스 | 서비스 전체 | Critical Path 전 구간 | `AWSFIS-Run-CPU-Stress` |
| 3 | Backend 메모리 스트레스 | 서비스 전체 | Critical Path 전 구간 | `AWSFIS-Run-Memory-Stress` |
| 4 | Backend → Redis 포트 차단 | 세션/채팅 | 로그인, 채팅 | `AWSFIS-Run-Network-Blackhole-Port` |

---

## 시나리오 1: Recommend 서버 응답 지연

### 가설

Recommend 서버 응답이 지연되면 Backend 타임아웃(5초) 후 투표 후보 조회가 `AI_RECOMMENDATION_FAILED` 에러를 반환하며, Backend Error Rate가 SLO(0.5%)를 위반한다.

> **참고**: Qdrant 장애 시에는 Recommend 서버 내부에서 CF Fallback으로 흡수되어 정상 응답이 반환된다. 본 시나리오는 Recommend 서버 자체의 응답 지연이 Backend Timeout 처리 로직을 올바르게 트리거하는지 검증한다.

### Application Fault Injection으로 분류하는 이유

`AWSFIS-Run-Network-Latency`는 EC2 내부 네트워크 인터페이스에 SSM Agent를 통해 프로세스 레벨 지연을 주입한다. EC2 자체와 Recommend 프로세스는 살아있는 상태에서 응답만 느려진다. → **Backend의 Timeout 처리 로직 검증**이 목적이므로 Application FI에 해당한다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| `GET /api/v1/meetings/{meetingId}/votes/{voteId}/candidates` | 투표 후보 조회 지연 | 타임아웃 후 `AI_RECOMMENDATION_FAILED` |
| `GET /api/v1/quick-meetings/{meetingId}/votes/{voteId}/candidates` | 퀵 모임 후보 조회 지연 | 타임아웃 후 `AI_RECOMMENDATION_FAILED` |

### Steady State

| 지표 | 기준 |
|------|------|
| Recommend 가용성 | `up{job=~"recommend\|prod-recommend"}` = 1 |
| Recommend Latency P95 | < 1s |
| Backend Error Rate | < 0.5% |
| Backend Latency P95 | < 500ms |

### AWS FIS 실험 구성

```
Action        : aws:ssm:send-command
Target        : Recommend EC2 (태그: Role=recommend)
Document      : AWSFIS-Run-Network-Latency
Parameters    : {"DelayMilliseconds": ["3000"], "DurationSeconds": ["180"]}
Duration      : PT3M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> `AWSFIS-Run-Network-Latency`는 SSM Agent를 통해 EC2 내부에서 `tc netem`을 실행한다. 실험 종료 시 자동으로 롤백되므로 수동 복구 명령 불필요.

### 검증 항목

- [ ] Recommend Latency P95가 SLO(1s)를 초과하는가 (의도된 결과)
- [ ] Backend가 타임아웃(5초) 후 `AI_RECOMMENDATION_FAILED` 에러를 반환하는가
- [ ] Backend Error Rate가 SLO(0.5%)를 위반하는가 (Fallback 미구현 확인)
- [ ] Grafana Alert가 발동되는가 (Error Rate > 0.5%)
- [ ] Discord 알림이 발송되는가
- [ ] Loki에서 타임아웃 로그가 확인되는가

### 모니터링 포인트

- Grafana: Recommend Latency P95 패널, Backend Error Rate 패널
- Loki: `{container="recommend-app-1"} |= "timeout"`

### 주의사항

- **현재 Recommend ASG가 1대로 운영 중임을 전제로 한다.** Scale-out으로 2대 이상이 되면 ALB가 다른 인스턴스로 트래픽을 분산하여 지연 주입이 무의미해지므로 시나리오 재설계 필요
- 피크 타임 외 시간대에 실행할 것

---

## 시나리오 2: Backend CPU 스트레스

### 가설

Backend CPU 사용률이 급증하면 응답 지연으로 인해 Latency P95가 SLO(500ms)를 위반하며, 요청 처리 지연이 ALB 타임아웃을 유발할 수 있다.

### Application Fault Injection으로 분류하는 이유

`AWSFIS-Run-CPU-Stress`는 EC2 내부에서 SSM Agent를 통해 CPU 스트레스 프로세스를 실행한다. 인프라(EC2)는 살아있는 상태에서 애플리케이션이 자원 고갈 상황에서 어떻게 동작하는지 검증한다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| Critical Path 전 구간 | Thread 처리 지연으로 응답 시간 상승 | Latency P95 SLO 위반 가능 |
| `POST /api/v1/meetings/{meetingId}/votes/{voteId}/submissions` | 투표 제출 지연 | 타임아웃 가능 |

### Steady State

| 지표 | 기준 |
|------|------|
| Backend CPU 사용률 | < 70% |
| Backend Latency P95 | < 500ms |
| Backend Error Rate | < 0.5% |

### AWS FIS 실험 구성

```
Action        : aws:ssm:send-command
Target        : Backend EC2 (태그: Role=backend, 선택 모드: PERCENT(50))
Document      : AWSFIS-Run-CPU-Stress
Parameters    : {"CPU": ["80"], "DurationSeconds": ["180"]}
Duration      : PT3M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> `CPU: 80` — CPU 사용률을 80%까지 강제 상승. `PERCENT(50)`으로 절반 인스턴스에만 주입하여 전체 서비스 중단 방지.

### 검증 항목

- [ ] CPU 사용률이 80% 이상으로 상승하는가
- [ ] Backend Latency P95가 SLO(500ms)를 초과하는가
- [ ] ALB가 지연 인스턴스를 Unhealthy로 처리하고 다른 인스턴스로 트래픽을 분산하는가
- [ ] Grafana Alert가 발동되는가 (Latency P95 임계값 초과)
- [ ] Discord 알림이 발송되는가
- [ ] 실험 종료 후 CPU 정상화 및 Latency P95 복구되는가

### 모니터링 포인트

- Grafana: Backend CPU 사용률 패널, Latency P95 패널, Error Rate 패널
- Loki: `{container="backend-app"} |= "timeout"`

### 주의사항

- 인스턴스가 2대 이상인 상태에서 실행할 것 (PERCENT(50) 적용 시 최소 1대는 정상 유지)
- 피크 타임 외 시간대에 실행할 것

---

## 시나리오 3: Backend 메모리 스트레스

### 가설

Backend 메모리 사용률이 급증하면 JVM GC 부하로 인해 응답 지연이 발생하며, OOM 발생 시 컨테이너가 재시작된다. 재시작 중 ALB가 해당 인스턴스를 Unhealthy로 처리하여 트래픽이 다른 인스턴스로 분산된다.

### Application Fault Injection으로 분류하는 이유

`AWSFIS-Run-Memory-Stress`는 EC2 내부에서 SSM Agent를 통해 메모리 할당 프로세스를 실행한다. 인프라(EC2)는 살아있는 상태에서 JVM 메모리 고갈 시 애플리케이션 동작을 검증한다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| Critical Path 전 구간 | GC 부하로 응답 지연 | Latency P95 상승 |
| 전체 API | OOM 시 컨테이너 재시작 | ALB가 다른 인스턴스로 재라우팅 |

### Steady State

| 지표 | 기준 |
|------|------|
| Backend 메모리 사용률 | < 80% |
| Backend Latency P95 | < 500ms |
| Backend Error Rate | < 0.5% |

### AWS FIS 실험 구성

```
Action        : aws:ssm:send-command
Target        : Backend EC2 (태그: Role=backend, 선택 모드: PERCENT(50))
Document      : AWSFIS-Run-Memory-Stress
Parameters    : {"Percent": ["80"], "DurationSeconds": ["180"]}
Duration      : PT3M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> `Percent: 80` — 전체 메모리의 80%를 강제 점유. JVM Heap과 별개로 OS 레벨 메모리를 점유하므로 JVM OOM과는 다른 형태의 압박.

### 검증 항목

- [ ] 메모리 사용률이 80% 이상으로 상승하는가
- [ ] JVM GC 빈도가 증가하는가 (Grafana JVM 메트릭 확인)
- [ ] Backend Latency P95가 SLO(500ms)를 초과하는가
- [ ] OOM 발생 시 컨테이너가 자동 재시작되는가 (`docker ps` 재시작 횟수 확인)
- [ ] 재시작 중 ALB가 해당 인스턴스를 Unhealthy로 처리하는가
- [ ] 실험 종료 후 메모리 정상화 및 Latency P95 복구되는가

### 모니터링 포인트

- Grafana: Backend 메모리 사용률 패널, JVM GC 패널, Latency P95 패널
- Loki: `{container="backend-app"} |= "OutOfMemoryError"`

### 주의사항

- 인스턴스가 2대 이상인 상태에서 실행할 것
- 피크 타임 외 시간대에 실행할 것
- OOM으로 컨테이너가 재시작되면 실험 종료 후에도 재시작 이력이 남음. 이상 없음으로 처리 가능

---

## 시나리오 4: Backend → Redis 포트 차단

### 가설

Backend EC2에서 Redis 포트(6379, 26379)가 차단되면 세션 조회 및 채팅 API가 실패하며, Backend Error Rate가 SLO(0.5%)를 위반한다.

### Application Fault Injection으로 분류하는 이유

`AWSFIS-Run-Network-Blackhole-Port`는 EC2 내부에서 SSM Agent를 통해 특정 포트로의 트래픽을 차단한다. Redis EC2와 Backend EC2는 모두 살아있는 상태에서 네트워크 통신만 두절된다. → **Backend의 Redis 연결 실패 시 에러 처리 로직**을 검증하는 Application FI에 해당한다.

### Critical Path 영향 구간

| API | 영향 | 예상 동작 |
|-----|------|----------|
| `POST /api/v1/auth/refresh` | 세션 토큰 조회 실패 | `RedisConnectionException` → 5xx |
| `GET /api/v2/meetings/{meetingId}/messages` | 채팅 조회 실패 | 5xx |
| `POST /api/v2/meetings/{meetingId}/read-pointer` | 읽음 처리 실패 | 5xx |
| `GET /api/v1/meetings` | 영향 없음 (DB 의존) | 정상 |

### Steady State

| 지표 | 기준 |
|------|------|
| Redis 가용성 | `redis_up` = 1 |
| Backend Error Rate | < 0.5% |
| Backend Latency P95 | < 500ms |

### AWS FIS 실험 구성

```
Action        : aws:ssm:send-command
Target        : Backend EC2 (태그: Role=backend)
Document      : AWSFIS-Run-Network-Blackhole-Port
Parameters    : {
                  "Port": ["6379"],
                  "Protocol": ["tcp"],
                  "TrafficType": ["egress"],
                  "DurationSeconds": ["180"]
                }
Duration      : PT3M
Stop Condition: moyeobab-fis-stop-condition (5xx > 5, 1분)
```

> Sentinel 포트(26379)도 차단이 필요한 경우 별도 action으로 추가하거나 스크립트로 두 포트 동시 차단.

### 검증 항목

- [ ] Redis 의존 API(세션, 채팅)에서 `RedisConnectionException`이 발생하는가
- [ ] Backend Error Rate가 SLO(0.5%)를 위반하는가 (의도된 결과)
- [ ] DB 의존 API(모임 목록 등)는 정상 응답하는가 (Redis와 DB 장애 격리 확인)
- [ ] Grafana Alert가 발동되는가
- [ ] Discord 알림이 발송되는가
- [ ] 실험 종료 후 포트 차단 해제 및 Redis 재연결이 자동으로 이루어지는가

### 모니터링 포인트

- Grafana: Backend Error Rate 패널, Redis 가용성 패널
- Loki: `{container="backend-app"} |= "RedisConnectionException"`

### 주의사항

- 실험 종료 후 `AWSFIS-Run-Network-Blackhole-Port`는 자동으로 iptables 규칙을 제거하므로 수동 복구 불필요
- Stop Condition이 트리거되어 실험이 자동 중단된 경우에도 포트 차단 규칙이 잔존할 수 있으므로 실험 후 Backend EC2에서 확인 권장
  ```bash
  sudo iptables -L OUTPUT -n | grep 6379
  ```