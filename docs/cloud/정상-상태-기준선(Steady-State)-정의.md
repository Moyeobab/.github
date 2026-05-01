## 개요

### 용어 정의

- **SLI (Service Level Indicator)**: 서비스 품질을 측정하는 지표
- **SLO (Service Level Objective)**: SLI의 내부 목표값. 팀이 달성하고자 하는 기준
- **SLA (Service Level Agreement)**: 외부(사용자)에 약속하는 수준. SLO보다 낮게 설정하여 운영 여유를 확보

### SLO/SLA 설정 기준

1. **사용자 경험**: 점심, 저녁 피크 타임에 빠른 식당 결정이 필요한 서비스 특성 반영. 500ms 초과 시 사용자가 기다림을 인지하기 시작
2. **비즈니스 임팩트 및 기능별 특징 고려**: 핵심 기능(조회/추천) > 부가 기능(OCR) 순으로 엄격하게 설정
3. **운영 현실**: 팀 6명, 99.9%보다 현실적으로 설정
4. **SLA는 SLO 대비 장애허용시간 10~20% 여유**: 예상치 못한 외부 요인 대비

---

## Backend API

> 식당 조회/추천 핵심 API. 피크 타임 중단 시 서비스 전체 마비로 직결되어 가장 엄격하게 관리.
> 

| SLI | 측정 방법 | SLO | SLA | 근거 |
| --- | --- | --- | --- | --- |
| 가용성 | `up{job=~"backend|prod-backend"}` | 99.5% | 99% | Multi-AZ ASG 구성이나 PostgreSQL 수동 페일오버 등 운영 현실 반영. 99.9%는 배포 시 다운타임도 허용 안 되는 수준으로 과도함. 월 3.6시간 허용 |
| Error Rate | 5xx 비율 | < 1% | < 1.5% | 수십만 MAU 기준 1% 초과 시 수천 명 동시 영향. 피크 타임 집중 고려 |
| Latency P95 | `http_server_requests_seconds` | < 500ms | < 600ms | 점심/저녁 빠른 의사결정 필요. 500ms 초과 시 사용자 이탈 시작. SLA는 20% 여유 |

---

## Recommend 서버

> LightGBM 추론 + Qdrant 벡터 검색 포함. Qdrant 장애 시 CF 피처를 0으로 대체하여 추천 기능을 유지하나, Recommend 서버 자체 장애 시 Fallback 없이 투표 후보 조회 전체 중단.
> 

| SLI | 측정 방법 | SLO | SLA | 근거 |
| --- | --- | --- | --- | --- |
| 가용성 | `up{job=~"recommend|prod-recommend"}` | 99.5% | 99% | 추천이 모여밥의 핵심 가치. 서버 자체 장애 시 Fallback 없이 투표 후보 조회 전체 중단. Qdrant 장애는 CF Fallback으로 흡수 가능하나 서버 가용성과 별개 |
| Error Rate | 5xx 비율 | < 1% | < 1.5% | 추천 실패 = 서비스 핵심 가치 훼손. Backend와 동일 기준 적용 |
| Latency P95 | `http_request_duration_seconds` | < 1s | < 1.2s | LightGBM 추론 + Qdrant 벡터 검색 특성상 Backend보다 여유있게 설정. SLA는 20% 여유 |

---

## OCR 서버 (RunPod)

> 영수증 인식 부가 기능. 피크 타임과 직접 연관 낮고 외부 서비스(RunPod) 의존으로 가장 여유있게 설정.
> 

| SLI | 측정 방법 | SLO | SLA | 근거 |
| --- | --- | --- | --- | --- |
| 가용성 | LangSmith 성공률 | 98% | 97.5% | 부가 기능으로 장애 시 서비스 핵심 기능 영향 없음. 외부 GPU 서버 의존 특성 반영 |
| Latency P95 | LangSmith Latency | < 10s | < 12s | vLLM 이미지 추론 특성상 수 초 소요 불가피. 현재 측정값 4~8s 기준으로 여유 설정 |

---

## DB (PostgreSQL)

> 모든 식당/사용자 데이터 저장소. 장애 시 서비스 전체 중단으로 Backend와 동일 수준 관리.
> 

| SLI | 측정 방법 | SLO | SLA | 근거 |
| --- | --- | --- | --- | --- |
| 가용성 | `pg_up` | 99.5% | 99% | DB 장애 = 서비스 전체 중단. Backend와 동일 수준 |
| 페일오버 시간 (RTO) | 수동 측정 | < 5분 | < 7분 | 자동 페일오버 미설정으로 수동 승격 필요. Standby 승격 + Parameter Store 변경 + Backend 재시작 포함 |

---

## Redis

> 로그인 세션/채팅 저장소. Sentinel 자동 페일오버로 DB보다 빠른 복구 가능.
> 

| SLI | 측정 방법 | SLO | SLA | 근거 |
| --- | --- | --- | --- | --- |
| 가용성 | `redis_up` | 99.5% | 99% | 세션 장애 시 로그인 불가, 채팅 중단. DB와 동일 수준 |
| 페일오버 시간 | 수동 측정 | < 10s | < 15s | Sentinel 자동 페일오버로 DB보다 빠른 전환 가능. SLA는 50% 여유 |

---

## Error Budget

> Error Budget = 1 - SLO. 해당 기간 내 허용되는 장애 시간.
> 
> 
> Error Budget 소진 시 신규 기능 배포보다 안정성 개선을 우선시한다.
> 

| 서비스 | SLO | 월간 Error Budget |
| --- | --- | --- |
| Backend API | 99.5% | 3시간 36분 |
| Recommend 서버 | 99.5% | 3시간 36분 |
| OCR 서버 | 98% | 14시간 24분 |
| DB (PostgreSQL) | 99.5% | 3시간 36분 |
| Redis | 99.5% | 3시간 36분 |

---

## Grafana Alert 임계값

> SLO보다 타이트하게 설정하여 SLO 위반 전에 사전 감지.
> 

| 서비스 | 지표 | Alert 임계값 | 비고 |
| --- | --- | --- | --- |
| Backend | Error Rate | > 0.5% (5분 지속) | SLO 1%의 절반 수준에서 선제 감지 |
| Backend | Latency P95 | > 400ms (5분 지속) | SLO 500ms의 80% 수준 |
| Recommend | Error Rate | > 0.5% (5분 지속) | SLO 1%의 절반 수준에서 선제 감지 |
| Recommend | Latency P95 | > 800ms (5분 지속) | SLO 1s의 80% 수준 |
| DB | 가용성 | `pg_up` = 0 (1분 지속) | 즉시 감지 |
| Redis | 가용성 | `redis_up` = 0 (1분 지속) | 즉시 감지 |