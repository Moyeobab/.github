## 실험 개요

| 항목 | 내용 |
| --- | --- |
| 시나리오 | Redis Primary 장애 및 Sentinel 자동 페일오버 |
| 실험 일시 | 2026-03-10 16:51:46 (KST) |
| 실험 도구 | AWS FIS + k6 |
| FIS 실험 ID | EXPFTYpmaNtazVQNiE (최종 성공) |
| 대상 환경 | prod |
| 대상 인스턴스 | moyeobab-prod-v2-redis-primary (10.0.2.20) |

---

## 가설

Redis Primary가 다운되더라도 Redis Sentinel이 30초 이내에 Standby를 자동 승격하며, Backend 서비스의 Error Rate는 SLO(99.5%) 위반 없이 정상 복구된다.

---

## 실험 설정

### FIS 실험 템플릿

| 항목 | 설정값 |
| --- | --- |
| 작업 유형 | `aws:ssm:send-command` |
| SSM Document | `AWS-RunShellScript` |
| 실행 명령 | `docker stop redis-redis-1` |
| 실험 지속 시간 | 2분 (PT2M) |
| Stop Condition | `moyeobab-fis-stop-condition` (5xx > 5, 1분) |

### k6 배경 트래픽

| 항목 | 설정값 |
| --- | --- |
| VU | 10명 |
| 지속 시간 | 10분 |
| 트래픽 패턴 | 모임 목록 조회 → 모임 상세 조회 → 채팅 메시지 조회 |
| 인증 방식 | Cookie 기반 (refresh_token으로 access_token 갱신) |

---

## 실험 타임라인

| 시각 (KST) | 이벤트 |
| --- | --- |
| 16:51:46 | FIS 실험 시작 / Redis Primary 컨테이너 종료 |
| 16:51:46 ~ 16:52:00 | Sentinel 장애 감지 (down-after-milliseconds: 5000ms) |
| 16:52:00 ~ 16:52:30 | Sentinel Failover 실행 / Standby → Primary 승격 |
| 17:02:20 | k6 connection reset 10건 발생 (약 1초 구간) |
| 17:02:21 | 정상 복구, 이후 요청 100% 성공 |

> 참고: 17:02:20 에러는 FIS 실험(16:51:46) 이후 약 10분 뒤 발생한 별도 이벤트로, Redis Sentinel 페일오버와 직접 연관 없음. Grafana 기준 Redis 다운 및 복구 구간은 16:51 ~ 16:52 사이에 완료됨.
> 

---

## 관찰 결과

### k6 최종 결과

| 지표 | 값 |
| --- | --- |
| 총 요청 수 | 4,442건 |
| 요청 성공률 | 99.78% (4,432/4,442) |
| 요청 실패율 | **0.22%** (10/4,442) |
| checks_succeeded | **99.77%** (4,431/4,441) |
| checks_failed | **0.22%** (10/4,441) |
| http_req_duration avg | 23.37ms |
| http_req_duration p95 | 47.54ms |
| iteration_duration avg | 4.07s |

### 엔드포인트별 결과

| 엔드포인트 | 성공 | 실패 | 성공률 |
| --- | --- | --- | --- |
| 모임 목록 조회 (`GET /api/v1/meetings`) | 1,470 | **10** | 99.32% |
| 모임 상세 조회 | 1,480 | 0 | **100%** |
| 채팅 메시지 조회 | 1,480 | 0 | **100%** |

### Grafana Golden Signals 관찰

| 지표 | 실험 전 | 실험 중 | 실험 후 |
| --- | --- | --- | --- |
| Request Rate | ~3.5 req/s | ~1 req/s (순간 급감) | ~3.8 req/s |
| Error Rate | 0% | 0% | 0% |
| Latency P95 | ~9ms | ~20ms (일시 상승) | ~9ms |
| Backend Health | 1 | 1 | 1 |

### Redis 대시보드 관찰 (Primary)

| 지표 | 관찰 내용 |
| --- | --- |
| Clients | 13 → N/A (다운) → 복구 |
| Memory Usage | 정상 → 0B (다운) → 복구 |
| Total Commands/sec | 정상 → 0 (다운) → 복구 |
| Total Items (db0) | 89 → N/A → 복구 |

<img width="900" height="500" alt="image" src="https://github.com/user-attachments/assets/6e6e827f-9bde-4e7e-889a-5bb74ef7506c" />


### Redis 대시보드 관찰 (Standby → 승격된 Primary)

| 지표 | 관찰 내용 |
| --- | --- |
| Total Commands/sec | 낮음 → **급증** (Primary 역할 승계) |
| Total Items (db0) | 96 → 98 → **100** (데이터 동기화 완료) |
| Network I/O | 낮음 → **증가** (쓰기 트래픽 처리 시작) |
| Clients | 13 유지 (Backend 자동 재연결) |

<img width="600" height="400" alt="image" src="https://github.com/user-attachments/assets/bef044a4-9eb7-4d03-9567-3b76d5f2cfda" />

---

## RTO 측정

| 항목 | 시각 / 값 |
| --- | --- |
| 장애 시작 | 16:51:46 |
| Sentinel 감지 완료 | 16:51:51 (약 5초, down-after-milliseconds 기준) |
| Standby 승격 완료 | 16:52:00 ~ 16:52:30 |
| **실질적 RTO** | **약 20 ~ 40초** |

SLO 기준 RTO 30초와 비교 시 경계선 수준이나, 실제 Error Rate 영향은 k6 기준 단일 구간(1초 미만)에 10건으로 제한됨.

---

## 가설 검증 결과

| 검증 항목 | 결과 |
| --- | --- |
| Sentinel 자동 페일오버 | 정상 동작 |
| RTO 30초 이내 | (경계)30초 내외 |
| Error Rate SLO 99.5% 유지 | 99.78% 달성 |
| Backend 자동 재연결 | 수동 개입 없이 복구 |
| 데이터 유실 없음 | db0 키 수 정상 유지 |

**최종 판정: 가설 검증 성공**

Redis Sentinel 페일오버는 정상 동작하며, Backend 서비스는 SLO 위반 없이 자동 복구된다.

---

## 발견된 이슈 및 개선 사항

### 이슈 1: SSM Document 파라미터 오류 (실험 준비 중)

**증상**
FIS 실험 시작 시 `ConfigurationFailure` 발생.

**원인**`AWSFIS-Run-Kill-Process` Document의 파라미터가 Docker 컨테이너 내부 프로세스에 직접 접근 불가.

**해결**
Document를 `AWS-RunShellScript`로 변경하고 `docker stop redis-redis-1` 명령 직접 실행.

---

### 이슈 2: RTO 30초 경계선

**관찰**
Grafana 기준 복구 완료 시점이 16:52:00 ~ 16:52:30으로 최대 40초 소요 가능.

**원인 분석**

- Sentinel `down-after-milliseconds: 5000ms` (5초 감지)
- Failover 실행 및 Standby 승격 과정: 10 ~ 25초
- Backend Lettuce 클라이언트 재연결: 일부 추가 지연

**개선 방안**

- `down-after-milliseconds`를 3000ms로 단축 검토
- Lettuce 클라이언트 `reconnectDelay` 설정 튜닝 검토
- SLO RTO 기준을 실측값 기반으로 60초로 재조정 검토

---

## 결론

Redis Sentinel 기반 HA 구성이 실제 장애 상황에서 정상 동작함을 확인. 단일 Primary 장애에 대해 자동 페일오버 및 Backend 자동 재연결이 수동 개입 없이 완료되었으며, SLO Error Rate 기준(99.5%)을 준수함.(RTO는 경계선 수준으로 후속 튜닝이 고려됨)