## 1. 실험 개요

| 항목 | 내용 |
|------|------|
| 시나리오 | PostgreSQL Primary EC2 네트워크 인터페이스에 지연 주입 |
| 실험 도구 | AWS FIS + k6 |
| FIS Action | `aws:ssm:send-command/AWSFIS-Run-Network-Latency` |
| 타겟 EC2 | i-0590e1c99611aedde |
| 네트워크 인터페이스 | ens5 |
| 지연 설정 | 200ms |
| 실험 지속 시간 | 3분 |
| Stop Condition | moyeobab-fis-stop-condition (5xx > 5%, 1분) |

---

## 2. 가설

Backend와 PostgreSQL 사이 네트워크에 지연이 발생하면 Backend Latency P95가 SLO(500ms)를 위반하며, 높은 트래픽 환경에서는 HikariCP 커넥션 대기가 쌓인다.

---

## 3. 실험 설정

### 3-1. k6 배경 트래픽

| 항목 | 1차 실험 | 2차·3차 실험 |
|------|---------|------------|
| VU | 10명 | 100명 |
| Duration | 10분 | 10분 |
| 트래픽 패턴 | 모임 목록 → 모임 상세 → 채팅 조회 | 동일 |

> **1차 실험(10 VU)** — HikariCP Pending 및 에러 발생 여부 확인 목적  
> **2차·3차 실험(100 VU)** — 커넥션 풀 압박 및 Alert 발동 여부 검증 목적

---

## 4. Steady State

| 지표 | 기준값 |
|------|------|
| Backend Latency P95 | < 500ms |
| Backend Error Rate | < 0.5% |
| HikariCP Pending Connections | 0 |

---

## 5. 실험 결과

### 5-1. k6 결과 비교

| 지표 | 1차 (10 VU) | 2차·3차 (100 VU) |
|------|------------|----------------|
| 전체 Check 수 | 2,197회 | 38,242회 |
| 성공률 | 100% | 100% |
| 에러율 | 0% | 0% |
| http_req_duration avg | - | 240ms |
| http_req_duration p(95) | ~1.62s | 1.62s |
| http_req_duration max | ~2s | 3.76s |
| iteration_duration p(95) | ~7.5s | 7.7s |

### 5-2. Grafana 관측 결과 (100 VU 기준)

| 지표 | 장애 주입 중 | 복구 후 |
|------|-----------|--------|
| Latency P95 | 최대 **3초** (SLO 500ms 위반) | 0ms 수준으로 즉시 회복 |
| HikariCP Pending | 최대 **30개** | 0 |
| Request Rate | ~40 req/s → ~20 req/s (처리량 저하) | ~37 req/s 정상 복구 |
| Error Rate | 0% | 0% |
| Backend Health | 1 (정상) | 1 (정상) |

> **HikariCP 초반 spike 원인**: 지연 주입 시작 순간 100 VU가 동시에 DB 커넥션을 요청하면서 순간적으로 풀 고갈 직전까지 대기가 몰린 후, 요청 처리 속도가 느려지면서 안정화됨.

<img width="650" height="400" alt="스크린샷 2026-03-16 오전 10 29 19" src="https://github.com/user-attachments/assets/8720498e-ab5a-41d9-9133-599ff2c7b749" />

<img width="650" height="400" alt="스크린샷 2026-03-16 오전 11 11 13" src="https://github.com/user-attachments/assets/0bfb4986-0a6e-4269-ba22-5886fa202104" />

---

## 6. 1차 실험 vs 2차 실험 비교

| 항목 | 1차 (10 VU) | 2차 (100 VU) |
|------|------------|-------------|
| Latency P95 | ~2초 | ~3초 |
| HikariCP Pending 최대 | 18개 | 30개 |
| 에러 발생 | 없음 | 없음 |
| Alert 발동 | 없음 (임계값 미달) | 있음 (개선 후) |

> 10 VU에서는 커넥션 풀 압박이 적어 Pending이 낮게 유지됐으나, 100 VU에서는 최대 30개까지 쌓이며 실질적인 부하를 재현할 수 있었다.

---

## 7. Alert 개선 전/후 비교

실험 과정에서 기존 Alert rule의 두 가지 문제를 발견하고 수정했다.

| 항목 | 개선 전 | 개선 후 |
|------|--------|--------|
| 메트릭 | `http_request_duration_seconds_bucket` (Recommend 서버 기준) | `http_server_requests_seconds_bucket{job="prod-backend"}` (Backend 서버 기준) |
| HighResponseTime 임계값 | P95 > 2초 | P95 > **0.5초** (SLO 기준) |
| CriticalResponseTime 임계값 | P95 > 5초 | P95 > **2초** |
| Pending period | 5분 | **1분** |
| Backend Alert 발동 | ❌ (메트릭 불일치로 감지 불가) | ✅ Discord 수신 확인 |

**개선 전**: Alert rule이 Recommend 서버의 메트릭을 참조하고 있어 Backend 응답 지연은 감지되지 않았다. 임계값도 P95 > 2초로 높아 SLO(500ms) 위반 상황에서 알림이 오지 않는 구조였다.

**개선 후**: Backend 전용 메트릭으로 수정하고 임계값을 SLO 기준(500ms)으로 조정했다. 3차 실험에서 FIS 주입 약 1분 후 Discord에 `[WARNING] HighResponseTime` 알림 정상 수신을 확인했다.

---

## 8. 검증 항목 체크리스트

| # | 검증 항목 | 결과 | 비고 |
|---|---------|------|------|
| 1 | Latency P95 SLO(500ms) 위반 확인 | ✅ | 최대 3초 도달 |
| 2 | HikariCP Pending 증가 확인 | ✅ | 최대 30개 (100 VU) |
| 3 | 에러율 0% 유지 | ✅ | Spring Boot 타임아웃(30s) 내 처리 완료 |
| 4 | FIS 종료 후 즉시 정상 회복 | ✅ | Latency/Pending 모두 즉시 0 복귀 |
| 5 | HighResponseTime Alert 발동 | ✅ | Discord 10:54 수신 확인 |
| 6 | Backend 전용 Alert 메트릭 수정 | ✅ | `http_server_requests_seconds_bucket` 적용 |

---

## 9. 분석 및 개선사항

### 9-1. 핵심 관찰

- **200ms 네트워크 지연 → P95 3초**로 증폭됨. 쿼리당 왕복 지연이 누적되어 API 전체 응답 시간이 급격히 늘어나는 구조.
- **HikariCP Pending 최대 30개** — 커넥션이 느린 쿼리에 묶이면서 대기 요청이 쌓임. 실제 수십만 MAU 규모에서는 풀 고갈로 이어질 수 있음.
- **에러율 0%** — 현재 트래픽(100 VU) 수준에서는 Spring Boot 기본 타임아웃(30초) 이내 처리 완료. 고트래픽 환경에서는 Pending 누적 → 타임아웃 폭발로 이어질 수 있음.
- **Alert 메트릭 불일치** — 기존 rule이 Recommend 서버 메트릭을 참조하여 Backend 응답 지연을 감지하지 못하는 문제가 이번 실험을 통해 발견됨.

### 9-2. 개선 방향

| # | 문제 | 개선 방향 |
|---|------|---------|
| 1 | Alert 메트릭 불일치 (완료) | Backend 전용 메트릭으로 수정 및 임계값 SLO 기준 정렬 |
| 2 | DB 읽기 부하 집중 | Read Replica 도입으로 읽기 쿼리 분산 (V3 백로그) |
| 3 | 지연 지속 시 커넥션 풀 고갈 위험 | HikariCP Pending Alert 추가 및 connectionTimeout 튜닝 검토 |

---

## 10. 결론

PostgreSQL 네트워크 지연 200ms 주입 시 Backend Latency P95가 최대 3초까지 상승하며 SLO(500ms)를 위반했다. HikariCP Pending이 최대 30개까지 쌓였으나 현재 트래픽 수준에서는 에러 없이 처리됐다. 수십만 MAU 규모로 확장될 경우 커넥션 풀 고갈로 이어질 수 있는 구조적 위험을 확인했다.

장애 대응 관점에서의 핵심 개선은 **Alert 감지 체계 정비**였다. 기존 HighResponseTime rule의 임계값(P95 > 2초, Pending 5분)은 SLO 위반 상황에서도 알림이 오지 않는 구조였다. 임계값을 SLO 기준(500ms)으로 낮추고 Pending period를 1분으로 단축한 결과, 동일한 장애 상황에서 **FIS 주입 후 약 1분 내 Discord Alert 수신**을 확인했다. 이는 운영자가 장애를 인지하고 대응을 시작하기까지의 시간(MTTD)을 실질적으로 단축한다.

네트워크 지연 장애는 서비스가 완전히 다운되지 않아 감지가 늦어지기 쉬운 유형이다. 이번 실험은 "느려지고 있다"는 신호를 얼마나 빨리 포착하느냐가 장애 대응의 시작임을 확인한 과정이었다.