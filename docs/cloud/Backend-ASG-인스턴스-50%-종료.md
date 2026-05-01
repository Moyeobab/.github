## 1. 실험 개요

| 항목 | 내용 |
|------|------|
| 시나리오 | Backend ASG 인스턴스 50% terminate 후 자동 복구 검증 |
| 실험 도구 | AWS FIS + k6 |
| FIS Action | `aws:ec2:terminate-instances` |
| 타겟 | `moyeobab-v2-backend-prod-asg` (태그: `Service=backend`) |
| 선택 모드 | PERCENT(50) — 2대 중 1대 종료 |
| Stop Condition | moyeobab-fis-stop-condition (5xx > 5%, 1분) |

---

## 2. 가설

ASG 인스턴스가 50% 종료되더라도 ALB Health Check와 ASG 자동 복구로 SLO(Error Rate < 0.5%)를 위반하지 않는다.

---

## 3. 실험 설정

### 3-1. 초기 인스턴스 상태

| 인스턴스 | IP | 상태 |
|---------|-----|------|
| i-08e119d390ecd2f81 | 10.0.1.xxx | InService (Healthy) |
| i-0ce25da493953abf6 | 10.0.6.xx | InService (Healthy) |

### 3-2. k6 배경 트래픽

| 항목 | 값 |
|------|-----|
| VU | 100명 |
| Duration | 15분 |
| 트래픽 패턴 | 모임 목록 → 모임 상세 → 채팅 조회 |

---

## 4. 실험 타임라인

| 시각 (KST) | 이벤트 |
|-----------|--------|
| 13:22경 | FIS 실험 시작, `10.0.6.57` terminate |
| 13:22 ~ 13:24 | ALB deregistration 진행 중, 일부 요청 실패 발생 (**에러 구간 약 2분**) |
| 13:24경 | `10.0.6.57` ALB 제외 완료, 에러 0% 복구 — `10.0.1.223` 단독 운영 시작 |
| 13:24 ~ 13:30 | ASG 자동 복구 — 신규 인스턴스 `10.0.6.33` 기동 및 헬스체크 통과 대기 |
| 13:30경 | `10.0.6.33` ALB Target Group 등록 완료, 트래픽 분산 재개 (**2대 정상 운영 복구, terminate로부터 약 8분**) |
| 13:30경 | Prometheus Service Discovery — 신규 인스턴스 자동 감지 확인 |

---

## 5. k6 실험 결과

| 지표 | 결과 | 비고 |
|------|------|------|
| 전체 Check 수 | 65,125회 | - |
| 성공률 | **98.95%** (64,444/65,125) | SLO 0.5% → **1.04% 위반** |
| 실패율 | **1.04%** (681/65,125) | ALB deregistration delay 구간 |
| [모임 목록] 성공률 | 99.1% (21,513/21,708) | - |
| [모임 상세] 성공률 | 98.9% (21,466/21,708) | - |
| [채팅 조회] 성공률 | 98.9% (21,464/21,708) | - |
| http_req_duration avg | 51.78ms | 정상 응답만: 21.77ms |
| http_req_duration p(95) | 38.54ms | SLO 500ms 이내 ✅ |
| http_req_duration max | 10.05s | 실패 요청 포함 |

---

## 6. Grafana 관측 결과

| 지표 | 관측 결과 |
|------|---------|
| Latency P95 | terminate 순간 최대 **150ms** spike → 즉시 정상 복구 |
| Request Rate | `10.0.6.57` 제외 후 `10.0.1.223`으로 집중 → `10.0.6.33` 등록 후 분산 |
| Backend Health | `10.0.6.57` → 0, `10.0.6.33` → 1 (자동 복구 확인) |
| HikariCP Pending | 0 유지 (DB 커넥션 영향 없음) |
| Error Rate | Grafana 기준 임계값 미만 (순간적 실패로 1분 지속 미달) |

<img width="700" height="500" alt="스크린샷 2026-03-16 오후 1 39 17" src="https://github.com/user-attachments/assets/49edbe67-a59c-4d6c-a466-188547331357" />

---

## 7. 검증 항목 체크리스트

| # | 검증 항목 | 결과 | 비고 |
|---|---------|------|------|
| 1 | ALB가 종료된 인스턴스를 제외 | ✅ | deregistration delay 존재 |
| 2 | ASG가 새 인스턴스 자동 생성 | ✅ | `10.0.6.33` 자동 기동 |
| 3 | 새 인스턴스 ALB Target Group 정상 등록 | ✅ | 약 6분 소요 |
| 4 | Prometheus Service Discovery 자동 감지 | ✅ | 태그 기반 자동 감지 확인 |
| 5 | Error Rate SLO(0.5%) 이내 | ❌ | 실제 1.04% (0.54%p 초과) |
| 6 | Latency P95 SLO(500ms) 이내 | ✅ | 최대 150ms |

---

## 8. 분석 및 개선사항

### 8-1. SLO 위반 원인

ALB는 인스턴스 terminate를 즉시 감지하지 못한다. **Deregistration delay(기본 300초)** 동안 ALB는 해당 인스턴스로 요청을 계속 라우팅하며, 이미 terminate된 인스턴스에 도달한 요청이 실패로 처리된다. 실험에서 약 2분간 발생한 681건의 실패가 이 구간에 집중됐다.

### 8-2. 개선 방향

| # | 문제 | 개선 방향 |
|---|------|---------|
| 1 | ALB Health Check 감지 지연 | Health Check 간격 단축으로 dead 인스턴스 빠른 제외 |
| 2 | ASG 인스턴스 교체까지 약 8분 소요 | AMI 최적화로 인스턴스 기동 시간 단축 검토 |
| 3 | terminate 시 in-flight 요청 실패 불가피 | 애플리케이션 레벨 graceful shutdown 설정 (scale-in 시나리오에서 유효) |

---

## 9. 결론

Backend ASG 인스턴스 50% 종료 시 **ASG 자동 복구, ALB 재라우팅, Prometheus Service Discovery** 모두 정상 동작했다.

복구 타임라인은 두 단계로 나뉜다. ALB가 종료된 인스턴스를 제외하기까지 **약 2분간 에러(1.04%)가 발생**했고, 이후 1대로 서비스가 유지됐다. ASG가 신규 인스턴스를 생성하고 ALB에 등록하기까지는 **약 8분**이 소요되어 2대 정상 운영으로 완전히 복구됐다.

SLO(Error Rate 0.5%) 위반은 ALB deregistration delay 구간에 집중됐다. terminate는 OS 레벨 강제 종료라 graceful shutdown이 동작하지 않고, ALB가 감지하기까지 수초~수십초가 소요되어 이미 죽은 인스턴스에 일부 요청이 도달한 것이 원인이다. Health Check 간격을 줄여도 이 감지 지연을 완전히 없앨 수 없어 **극단적인 인스턴스 장애 시 일부 요청 실패는 현재 구조에서 구조적으로 불가피**하다. 이는 현재 인프라의 한계로 수용하며, graceful shutdown이 적용되는 정상 배포·scale-in 시나리오에서는 SLO를 만족할 수 있다.