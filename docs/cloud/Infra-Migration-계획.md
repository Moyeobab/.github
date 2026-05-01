# moyeobab 인프라 마이그레이션 계획서

> **V1 -> V2 무중단 전환**
>
> 핵심 목표: Canary 방식의 점진적 전환으로 **24시간 서비스 가용성**을 유지하며 인프라를 마이그레이션한다.

---

## 1. 개요

### 1.1 현재 아키텍처

단일 EC2 인스턴스에 모든 컴포넌트가 배포되어 있다.

- Nginx (Reverse Proxy / Static Files)
- Spring Boot Application Server
- PostgreSQL (Primary Database)
- Redis (사용자 세션/상태 정보 저장)

### 1.2 목표 아키텍처

| 컴포넌트 | 마이그레이션 전략 | 설명 |
|----------|------------------|------|
| Traffic Routing | ALB → Route 53 Weighted | Route 53 Weighted Routing을 활용한 Canary 배포로 Old/New 인프라 간 트래픽 비율 조정 |
| Application | Docker + Multi-Instance | Spring Boot 컨테이너화 및 ALB 기반 멀티 인스턴스 배포 |

> **참고:** 이 문서는 인프라(네트워크, 컴퓨팅, 트래픽 라우팅) 마이그레이션만 다룬다. 데이터베이스(PostgreSQL, Redis) 마이그레이션은 별도 문서에서 다룬다.

### 1.3 마이그레이션 단계 요약

| Phase | 이름 | 핵심 활동 | 서비스 영향 |
|-------|------|----------|------------|
| 1 | 기초 인프라 구성 | New 인프라 프로비저닝 및 기본 설정 | 없음 (Old 인프라 그대로 운영) |
| 2 | 모니터링 연결 | 로그/메트릭 수집 및 Canary 검증 준비 | 없음 |
| 3 | Canary 트래픽 전환 | Route 53 Weighted로 점진적 트래픽 이동 | 없음 (무중단) |
| 4 | 인프라 확장 | 멀티 인스턴스 + Auto Scaling 완성 | 없음 |

---

## 2. Phase 1: 기초 인프라 구성

**목표:** New 환경의 기본 인프라를 프로비저닝하고, 애플리케이션이 정상 구동하는지 검증한다. Old 인프라는 그대로 100% 트래픽을 처리하므로 서비스에 영향 없다.

### 2.1 Network & VPC

1. VPC 및 Subnet 구성 (Public/Private Subnet 분리)
2. Security Group 설정 (ALB, Application 계층별 분리)
3. NAT Gateway 설정 (Private Subnet의 외부 통신용)
4. Old 인스턴스와 New VPC 간 네트워크 연결 확인 (New 인프라가 Old DB를 바라볼 수 있어야 함)

### 2.2 Application Layer

1. Spring Boot 애플리케이션 Docker 이미지 빌드 및 ECR Push
2. ALB(Application Load Balancer) 생성 및 Target Group 설정
3. EC2 인스턴스에 컨테이너 배포
4. Health Check Endpoint 구성 (`/actuator/health`)
5. New 애플리케이션 → Old 인스턴스의 PostgreSQL/Redis 연결 확인

### 2.3 DNS 준비

1. Route 53 Hosted Zone 확인 및 Weighted Record 생성 준비
2. 초기 설정: **Old 인프라 100% / New 인프라 0%** (트래픽은 아직 Old로만)
3. TTL을 60초로 설정 (빠른 Rollback을 위해)

### 2.4 완료 기준

- New 인스턴스에서 Spring Boot 애플리케이션 정상 기동 확인 (Health Check Pass)
- ALB Target Group Healthy 상태 확인
- New 애플리케이션에서 Old DB(PostgreSQL/Redis) 정상 연결 확인
- 서비스 중단 없이 Old 인프라 100% 운영 유지 중

---

## 3. Phase 2: 모니터링 연결

**목표:** Canary 배포 전환 전에 이상 징후를 빠르게 감지할 수 있는 모니터링 파이프라인을 구성한다. Canary 전환 중 문제를 실시간으로 잡아내는 것이 24시간 가용성 유지의 핵심이다.

### 3.1 Logging

1. Application 로그 수집 구성 (CloudWatch Agent 또는 Promtail → Loki)
2. ALB Access Log 활성화 (S3 저장)
3. Nginx Access/Error Log 수집

### 3.2 Metrics & Dashboard

1. Prometheus 설치 및 Spring Boot Actuator Metrics Scraping
2. Grafana Dashboard 구성 — **Old/New 인프라 메트릭을 나란히 비교할 수 있는 구조**로 설계
3. Node Exporter 연동 (CPU, Memory, Disk, Network)
4. 핵심 메트릭 패널 구성:
   - Request Rate (Old vs New)
   - Error Rate (Old vs New)
   - Response Time P50/P95/P99 (Old vs New)
   - ALB Healthy Host Count

### 3.3 Alerting

1. Alertmanager 구성 (Slack/Discord Webhook 연동)
2. 핵심 Alert Rule 설정:
   - Error Rate > 1% (5분 이동평균)
   - Response Time P95 > 500ms
   - CPU/Memory 사용률 > 80%
   - ALB Unhealthy Host Count > 0
   - Health Check 연속 실패

> **Alert은 Canary 전환 중 자동 Rollback 판단의 근거가 된다.** Alert 발생 시 즉시 이전 Weight로 복귀한다.

### 3.4 완료 기준

- Grafana 대시보드에서 Old/New 인프라 메트릭 동시 비교 가능
- Alert 발송 테스트 완료 (Slack/Discord에 정상 수신)
- Application Log에서 에러 없이 정상 요청 처리 확인

---

## 4. Phase 3: Canary 트래픽 전환

**목표:** Route 53 Weighted Routing을 활용하여 New 인프라로 트래픽을 점진적으로 전환하며, 모니터링을 통해 이상 여부를 실시간 검증한다. **전 과정에서 서비스 중단 없이 24시간 가용성을 유지한다.**

> 이 단계에서는 Old/New 인프라가 모두 **기존 데이터베이스(Old 인스턴스의 PostgreSQL/Redis)를 바라보는 상태**에서 트래픽만 분산한다.

### 4.1 Traffic Weight Schedule

| Step | Old (%) | New (%) | 관찰 기간 | Rollback Trigger | 비고 |
|------|---------|---------|-----------|-----------------|------|
| 1 | 95% | 5% | 24h | Error Rate > 1% | 최소 트래픽으로 기본 동작 검증 |
| 2 | 80% | 20% | 24h | P95 Latency > 500ms | 부하 증가에 따른 성능 확인 |
| 3 | 50% | 50% | 24~48h | Error Rate > 0.5% | 동등 분배 상태에서 안정성 확인 |
| 4 | 20% | 80% | 24h | Any anomaly | New 인프라 주력 운영 검증 |
| 5 | 0% | 100% | 48h 안정화 | Any anomaly | 완전 전환 및 안정화 |

### 4.2 Weight 변경 절차

각 Step 전환 시 아래 절차를 따른다:

1. 전환 전 현재 메트릭 스냅샷 기록 (비교 기준선)
2. Route 53 Weighted Record의 Weight 값 변경 (AWS CLI 또는 Console)
3. DNS TTL 만료 대기 (60초)
4. Grafana 대시보드에서 트래픽 분배 비율 확인
5. Old/New 메트릭 비교 확인 (Error Rate, Latency, Status Code)
6. 최소 관찰 기간 동안 모니터링 유지
7. Alert 발생 시 → **즉시 이전 단계로 Rollback**
8. 이상 없으면 → 다음 Step으로 진행

### 4.3 검증 항목 (각 단계별)

- HTTP Status Code 분포 (2xx/4xx/5xx 비율)
- API Response Time (P50, P95, P99)
- Application Error Log 발생 빈도
- DB Connection Pool 사용률 및 Query 응답 시간
- Redis Hit/Miss Rate 및 Latency
- 사용자 세션 정상 유지 여부 (로그인 상태 유지)

### 4.4 Rollback Plan

**Rollback은 Route 53 Weight 변경만으로 즉시 수행 가능하다.** 이것이 Canary 방식의 핵심 장점이며, 24시간 가용성을 보장하는 안전장치다.

1. Route 53 Weight 변경: New → 0%, Old → 100%
2. DNS TTL 만료 대기 (60초)
3. Old 인프라가 100% 트래픽을 다시 처리하는지 확인
4. New 인프라의 에러 원인 분석
5. 수정 후 재배포 및 해당 Step 재시작

### 4.5 완료 기준

- New 인프라 100% 트래픽 상태에서 **48시간 이상** 안정 운영
- Error Rate < 0.1%, P95 Latency 기존 대비 유사 또는 개선
- 사용자 세션 유지 정상 확인
- Team 전체 Sign-off

---

## 5. Phase 4: 인프라 확장

**목표:** 멀티 인스턴스 구성을 통해 단일 장애점을 제거하고, 24시간 지속 가용한 인프라를 완성한다.

### 5.1 Application Multi-Instance

1. ALB Target Group에 추가 인스턴스 등록 (Minimum 2개 인스턴스, 가용영역 분리)
2. Auto Scaling Policy 구성 (CPU/Memory 기반)
3. Rolling Update 배포 전략 설정 (배포 중에도 서비스 중단 없도록)
4. Session Affinity 확인 (Redis 기반 세션이므로 Sticky Session 불필요)

### 5.2 고가용성 검증

1. 단일 인스턴스 종료 시 ALB가 정상 인스턴스로 트래픽 분배하는지 확인
2. Auto Scaling에 의한 인스턴스 자동 복구 확인
3. 가용영역 장애 시뮬레이션 (하나의 AZ 인스턴스 종료)
4. Rolling Update 중 서비스 중단 없는지 확인

### 5.3 Load Test

1. k6 부하 테스트 실행 (멀티 인스턴스 환경 검증)
2. 부하 증가 시 Auto Scaling 동작 확인
3. 인스턴스 장애 주입 테스트 (Chaos Engineering)
4. 최대 동시 접속자 수 기준선 확립

### 5.4 Old 인프라 정리

1. Old 인스턴스의 Nginx/Spring Boot 서비스 중지
2. Route 53에서 Old 레코드 제거
3. Old 인프라 리소스 정리 (단, DB는 별도 마이그레이션 완료 후 정리)

### 5.5 완료 기준

- Multi-Instance 환경에서 k6 부하 테스트 통과
- 단일 인스턴스 장애 시 **서비스 중단 없이** 자동 복구 확인
- Auto Scaling 정상 동작 확인
- Rolling Update 시 무중단 배포 확인

---

## 6. Rollback 전략

### 6.1 Phase별 Rollback 방법

| Phase | Rollback 방법 | 소요 시간 | 서비스 영향 |
|-------|--------------|----------|------------|
| Phase 1 | 인프라 삭제 (Old 그대로 운영 중) | N/A | 없음 |
| Phase 2 | 모니터링 에이전트 제거 | N/A | 없음 |
| Phase 3 | Route 53 Weight → Old 100% | ~60초 (TTL) | 없음 |
| Phase 4 | 인스턴스 수 축소 / 이전 구성 복원 | ~10분 | 없음 |

> **전 Phase에서 서비스 중단이 발생하지 않는다.** Phase 1~2는 Old 인프라가 그대로 운영되고, Phase 3은 DNS Weight 변경만으로 즉시 복귀 가능하며, Phase 4는 이미 전환 완료된 상태에서의 스케일 조정이다.

### 6.2 Risk Matrix

| 위험 | 완화 방안 |
|------|----------|
| DNS 캐싱으로 인한 트래픽 지연 전환 | Route 53 TTL을 60초로 설정, 전환 전 TTL 만료 확인 |
| New 인프라에서 Old DB 연결 불안정 | Security Group 및 네트워크 경로 사전 검증, Connection Pool 튜닝 |
| Canary 전환 중 세션 불일치 | 동일 DB를 바라보므로 세션 공유됨, 문제 없음 |
| ALB Health Check 오탐 | Health Check 간격/임계값 적절히 설정 |
| 멀티 인스턴스 배포 시 세션 불일치 | Redis 기반 세션으로 Sticky Session 불필요 |

---