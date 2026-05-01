## 1. 실험 개요

| 항목 | 내용 |
| --- | --- |
| 시나리오 | PostgreSQL Primary EC2 종료 후 Standby 수동 승격 |
| 실험 도구 | AWS FIS + k6 |
| FIS Action | `aws:ec2:terminate-instances` |
| Primary EC2 | i-0f96093d5b75a4e4e |
| Standby EC2 | i-0590e1c99611aedde |
| Stop Condition | moyeobab-fis-stop-condition (Error Rate > 5%, 1분) |
| IAM Role | moyeobab-fis-role |

---

## 2. 가설

PostgreSQL Primary EC2가 종료되더라도 수동 승격 절차(`pg-failover.sh`)를 통해 RTO 5분 이내에 복구되며, 복구 후 서비스 에러율이 정상 수준으로 회복된다.

---

## 3. 실험 설정

### 3-1. 수동 승격 스크립트 (pg-failover.sh)

| 단계 | 내용 |
| --- | --- |
| Step 1 | SSM SendCommand → `pg_ctl promote` (Standby EC2) |
| Step 2 | `pg_is_in_recovery() = f` 확인 (Primary 승격 검증) |
| Step 3 | Parameter Store DB_URL: `기존 Primary DB` → `기존 Standby DB` 변경 |
| Step 4 | ASG Backend 인스턴스 컨테이너 재시작 (`docker compose restart app`) |

### 3-2. k6 배경 트래픽

| 항목 | 설정값 |
| --- | --- |
| VU | 10명 |
| Duration | 10분 |
| 트래픽 패턴 | 모임 목록 조회 → 모임 상세 조회 → 채팅 메시지 조회 |

---

## 4. 실험 타임라인

| 시각 (KST) | 이벤트 |
| --- | --- |
| 09:47:00 | FIS 실험 시작 / Primary EC2 terminate |
| 09:47:00 | Discord Alert 수신 (`[CRITICAL] InstanceDown` - prod-postgresql) |
| 09:47 ~ | k6 에러 발생 시작 (DB 연결 불가, 30s 타임아웃) |
| 09:50:27 | pg-failover.sh 실행 시작 (**감지 후 약 3분 경과 - 수동 대응 준비 시간**) |
| 09:50:32 | Standby → Primary 승격 완료 (`server promoted`, 소요: 5초) |
| 09:50:42 | Parameter Store DB_URL 변경 완료 |
| 09:50:47 | Backend 컨테이너 재시작 명령 전송 (2 instances) |
| 09:52:17 | 스크립트 완료 |
| 09:51경 | Grafana 기준 에러율 0% 복구 확인 |

> **비고**: 장애 감지(09:47) → 스크립트 실행(09:50:27) 사이 약 3분은 상황 파악 및 대응 준비 시간이다. 이 구간이 RTO의 실질적 병목이었다.
> 

---

## 5. 복구 시간 측정 (RTO)

| 구간 | 시작 (KST) | 완료 (KST) | 소요 시간 |
| --- | --- | --- | --- |
| 장애 발생 ~ Discord Alert 수신 | 09:47:00 | 09:47:00 | ~0초 |
| Alert 수신 ~ 스크립트 실행 | 09:47:00 | 09:50:27 | **약 3분 (수동 대응 준비)** |
| pg_ctl promote 실행 | 09:50:27 | 09:50:32 | 5초 |
| Parameter Store 변경 | 09:50:41 | 09:50:42 | 1초 |
| Backend 컨테이너 재시작 | 09:50:44 | 09:52:17 | 약 90초 |
| **전체 RTO (장애 ~ 복구 완료)** | **09:47:00** | **09:52:17** | **약 5분 17초** |

### RTO 목표 달성 여부

- **목표**: 5분
- **실제**: 약 5분 17초
- **결과**: ❌ 미달성 (17초 초과)

> **분석**: `pg_ctl promote` 자체(5초)와 Parameter Store 변경(1초)은 빠르게 완료됐다. RTO 초과의 원인은 **Alert 수신 후 스크립트 실행까지의 수동 대응 준비 시간(약 3분)**이다. 절차가 완전히 숙달된 상태라면 이 구간을 1분 이내로 단축 가능하며, RTO 5분 달성이 가능하다.
> 

---

## 6. k6 실험 결과

| 지표 | 결과 | 비고 |
| --- | --- | --- |
| 전체 Check 수 | 2,197회 | - |
| 성공률 | 85.75% (1,884/2,197) | SLO 99.5% 위반 |
| 실패율 | 14.24% (313/2,197) | DB 연결 불가 구간 |
| [모임 목록] 성공률 | 85.9% (629/732) | - |
| [모임 상세] 성공률 | 86.3% (632/732) | - |
| [채팅 조회] 성공률 | 84.9% (622/732) | - |
| http_req_duration p95 | 419.51ms (장애 중) | 정상 시: 122ms |
| iteration_duration p95 | 34.3s | 정상 시: ~4.3s |

---

## 7. Grafana 모니터링 관측

| 항목 | 관측 결과 |
| --- | --- |
| 응답 시간 (P95) | 09:47경부터 30s 상한 도달 → 09:51경 정상 회복 |
| 에러율 | 장애 구간 40~80% → 복구 후 0% |
| Backend Health | 복구 후 모든 인스턴스 `1` (정상) |
| 인스턴스별 복구 시점 | 10.0.1.223 먼저 회복 → 10.0.6.57 직후 회복 (재시작 완료 시점 차이) |
| Discord Alert | 09:47 수신 확인 (`[CRITICAL] InstanceDown` - prod-postgresql) |

<img width="800" height="500" alt="image" src="https://github.com/user-attachments/assets/063bac57-971d-41cf-add2-0e11d682b6d3" />

---

## 8. 검증 항목 체크리스트

| # | 검증 항목 | 결과 | 비고 |
| --- | --- | --- | --- |
| 1 | pg_ctl promote 정상 실행 | 통과 | 5초 소요 |
| 2 | Parameter Store DB_URL 변경 반영 | 통과 | - |
| 3 | Backend 재시작 후 신규 DB 연결 | 통과 | - |
| 4 | 복구 후 에러율 0% 회복 | 통과 | - |
| 5 | Discord Alert 발동 | 통과 | 09:47 수신 |
| 6 | 수동 승격 RTO 5분 이내 달성 | 미통과 | 5분 17초 (17초 초과) |
| 7 | 복구 구간 SLO 99.5% 유지 | 미통과 | 에러율 14.24% |

---

## 9. 분석 및 개선사항

### 9-1. 핵심 관찰

- *Alert → 스크립트 실행 지연(3분)**이 RTO 초과의 직접 원인. 기술적 절차 자체는 2분 내 완료됨.
- `pg_ctl promote`(5초)와 Parameter Store 변경(1초)은 충분히 빠르다. 병목은 **사람의 대응 속도**.
- Backend 인스턴스 2개의 재시작 완료 시점이 달라 에러율 패턴이 들쭉날쭉하게 관측됨.
- Step 2(`pg_is_in_recovery` 확인) 결과가 출력되지 않았으나 Step 1에서 `server promoted` 확인됐으므로 승격은 정상 완료.

### 9-2. 개선 방향

| # | 문제 | 개선 방향 |
| --- | --- | --- |
| 1 | Alert → 스크립트 실행 대응 준비 시간(3분) | Runbook 숙달 및 팀 전체 공유. 알림 수신 즉시 스크립트 실행 절차 내재화 |
| 2 | Backend 재시작 90초 하드코딩 대기 | 헬스체크 폴링으로 실제 재시작 완료 감지 후 진행하도록 스크립트 개선 |
| 3 | Step 2 승격 확인 결과 미출력 | SSM wait 타임아웃 증가 또는 `docker exec` 직접 확인으로 대체 |
| 4 | 자동 페일오버 없어 SLO 위반 불가피 | V3 EKS 전환 시 Patroni 또는 RDS Multi-AZ 도입 검토 |

---

## 10. 결론

PostgreSQL Primary EC2 종료 시나리오에서 수동 승격 절차(`pg-failover.sh`)의 기술적 수행은 성공했으나, **Alert 수신 후 대응 준비 시간(약 3분)으로 인해 RTO 목표(5분)를 17초 초과**하였다.

절차 자체(pg_ctl promote → Parameter Store 변경 → Backend 재시작)는 약 2분으로 충분히 빠르다. 팀 내 Runbook 숙달과 대응 절차 내재화를 통해 RTO 5분 달성이 가능하다.

장애 구간 SLO(99.5%) 위반은 자동 페일오버가 없는 현재 인프라 구조의 한계이며, 수용 가능한 수준으로 판단한다.