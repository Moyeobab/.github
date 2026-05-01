## 1. 실험 개요

| 항목 | 내용 |
|------|------|
| 시나리오 | ap-northeast-2a AZ 서브넷 격리 후 Multi-AZ 자동 재라우팅 검증 |
| 실험 도구 | AWS FIS + k6 |
| FIS Action | `aws:network:disrupt-connectivity` |
| 타겟 서브넷 | `subnet-02cbc0c8d2b840bc8` (private-app-1), `subnet-024db6a6842a6ce45` (private-data-1) |
| Scope | all (인/아웃바운드 전체 차단) |
| Duration | PT5M |
| Stop Condition | moyeobab-fis-stop-condition |

---

## 2. 가설

ap-northeast-2a AZ가 격리되더라도 ALB와 ASG의 Multi-AZ 구성으로 나머지 AZ에서 트래픽을 처리하며, SLO를 위반하지 않는다.

---

## 3. 실험 전 인프라 상태

| 서비스 | 인스턴스 IP | AZ | 격리 여부 |
|--------|-----------|-----|---------|
| Backend | 10.0.1.223 | **2a** | ✅ 격리됨 |
| Backend | 10.0.6.33 | 2b | 정상 |
| PostgreSQL Primary | 10.0.7.10 | 2b | 정상 |
| PostgreSQL Standby | 10.0.2.174 | **2a** | ✅ 격리됨 |
| Redis Primary | 10.0.1.94 | **2a** | ✅ 격리됨 |
| Redis Standby | 10.0.2.x | 2b | 정상 |

---

## 4. FIS가 차단한 것

`aws:network:disrupt-connectivity`는 지정한 서브넷의 **인바운드/아웃바운드 트래픽을 모두 차단**한다. 인스턴스 OS나 프로세스는 살아있으나, 해당 서브넷으로의 모든 네트워크 통신이 불가능한 상태가 된다.

이번 실험에서 차단된 서브넷:

| 서브넷 | ID | 배치된 서비스 |
|--------|-----|------------|
| private-app-1 | subnet-02cbc0c8d2b840bc8 | Backend (10.0.1.223), Recommend |
| private-data-1 | subnet-024db6a6842a6ce45 | PostgreSQL Standby (10.0.2.174), Redis Primary (10.0.1.94) |

**차단으로 인해 불가능해진 통신:**

| 출발 | 도착 | 영향 |
|------|------|------|
| ALB | 10.0.1.223 (2a Backend) | ALB → Backend 요청 차단 → Health check 실패 |
| 10.0.1.223 | PostgreSQL Primary (10.0.7.10, 2b) | Backend DB 쿼리 불가 → HikariCP 커넥션 끊김 |
| 10.0.1.223 | Redis Primary (10.0.1.94, 2a) | Backend Redis 접근 불가 |
| Redis Sentinel | Redis Primary (10.0.1.94, 2a) | Primary 응답 없음 → Sentinel 페일오버 트리거 |

**차단되지 않은 통신 (서비스 유지의 핵심):**

| 출발 | 도착 | 상태 |
|------|------|------|
| ALB | 10.0.6.33 (2b Backend) | ✅ 정상 — 이 인스턴스가 격리 중 서비스 유지 |
| 10.0.6.33 | PostgreSQL Primary (10.0.7.10, 2b) | ✅ 정상 |
| 10.0.6.33 | Redis Standby → 승격된 Primary (2b) | ✅ Sentinel 페일오버 후 정상 |

---

## 5. 실험 타임라인

| 시각 (KST) | 이벤트 |
|-----------|--------|
| 15:25:19 | FIS 실험 시작 — 2a 서브넷 인/아웃바운드 전체 차단 |
| 15:25:38 ~ 15:26:03 | `10.0.1.223` 백엔드 로그: HikariCP DB 커넥션 끊김 WARN 연속 발생 |
| 15:26:03 | `10.0.1.223` 로그: `Connection is not available, request timed out after 30034ms` ERROR |
| 15:26:37 | k6: `request timeout` 에러 발생 시작 |
| 15:27:52 | ASG: `10.0.1.94` (2a) 신규 인스턴스 자동 생성 (unhealthy 대체) |
| 15:30경 | FIS 종료 — 2a 네트워크 복구 |
| 15:30경 | Redis Primary(2a) Commands 급감 → Sentinel 페일오버 → Redis Standby(2b) 승격 |
| 15:33:58 | ASG: `10.0.1.223` ELB health check 실패로 terminate |
| 15:44:36 | k6: `connection reset by peer` 대량 발생 — 전체 에러의 99% 집중 |

---

## 6. k6 실험 결과

| 지표 | 결과 | 비고 |
|------|------|------|
| 전체 Check 수 | 59,629회 | - |
| 성공률 | **90.38%** (53,894/59,629) | SLO 0.5% → **9.61% 위반** |
| 실패율 | **9.61%** (5,735/59,629) | - |
| [모임 목록] 성공률 | 90% (17,978/19,876) | - |
| [모임 상세] 성공률 | 90% (17,963/19,876) | - |
| [채팅 조회] 성공률 | 90% (17,952/19,876) | - |
| http_req_duration avg | 178.89ms | 정상 응답만: 55.69ms |
| http_req_duration p(95) | 201.53ms | SLO 500ms 이내 ✅ |
| http_req_duration max | 1m0s | timeout 포함 |
| k6 실제 실행시간 | 21분 41초 | 설정 15분 — 격리 중 VU stuck |

---

## 7. 에러 패턴 분석

에러는 두 구간에 집중됐다.

**1구간 (15:26 — 소규모)**
- 에러 유형: `request timeout`
- 원인: FIS 격리 직후 2a Backend(`10.0.1.223`)로 향하는 요청이 차단됨
- 규모: 약 9건 (전체 에러의 약 0.2%)

**2구간 (15:44 — 대규모)**
- 에러 유형: `connection reset by peer`
- 원인: ASG가 `10.0.1.223`을 terminate하는 과정에서 ALB가 해당 인스턴스로 계속 트래픽을 라우팅
- 규모: 약 5,726건 (전체 에러의 99.8%)

---

## 8. 근본 원인 분석

### 10.0.1.223이 왜 terminate됐나

백엔드 코드의 ALB health check endpoint는 `/api/ping`이며, 단순히 "pong"을 반환하는 구조다. DB나 Redis 상태를 전혀 체크하지 않는다.

```java
@GetMapping("/api/ping")
public ResponseEntity<String> ping() {
    return ResponseEntity.ok("pong");
}
```

그럼에도 health check가 실패한 이유는 **`/api/ping` 응답의 문제가 아니라, ALB가 `10.0.1.223`에 아예 접근하지 못했기 때문**이다.

`aws:network:disrupt-connectivity`는 서브넷의 **인바운드까지 차단**한다. ALB에서 `10.0.1.223:8080`으로 보내는 health check 요청 자체가 도달하지 못했고, ALB는 응답 없음 → timeout → Unhealthy로 판정했다.

```
ALB → 10.0.1.223:8080/api/ping
        ↑
    인바운드 차단 (FIS)
    → 요청 도달 불가 → timeout → Unhealthy
        ↓
ASG terminate
```

Loki 로그에서 확인된 HikariCP 에러는 health check 실패의 원인이 아니라, **격리로 인해 DB 연결도 동시에 끊어진 별개의 현상**이다.

```
15:25:38 ~ 15:26:03  WARN  HikariPool-1 - Failed to validate connection
                           (This connection has been closed.)
15:26:03             ERROR Connection is not available, request timed out
                           after 30034ms
```

**FIS 종료(15:30) 이후에도 terminate된 이유:**

ALB는 Unhealthy threshold(연속 2회 실패)에 도달하면 ASG에 terminate 신호를 보내고, ASG가 실제로 terminate를 완료하기까지 시간이 걸린다. FIS가 15:30에 종료됐지만 ASG terminate 결정은 이미 내려진 상태였고, 15:33:58에 terminate가 완료됐다.

### ASG 신규 인스턴스(10.0.1.94)가 동작한 이유

ASG가 15:27:52에 `10.0.1.94`(2a)를 생성했으나, 이 인스턴스가 ALB에 등록될 시점(15:30 이후)에는 이미 FIS가 종료되어 네트워크가 복구된 상태였다. 타이밍상 격리 해제 후에 서비스에 투입된 것이다.

### 격리 중 서비스를 유지한 것

격리 중에도 서비스가 완전히 중단되지 않은 것은 **2b AZ의 `10.0.6.33` 인스턴스가 계속 트래픽을 처리**했기 때문이다.

---

## 9. 검증 항목 체크리스트

| # | 검증 항목 | 결과 | 비고 |
|---|---------|------|------|
| 1 | ALB가 2a 격리 인스턴스를 Unhealthy 처리 | ✅ | 인바운드 차단으로 health check 응답 불가 |
| 2 | 나머지 AZ(2b) 인스턴스로 트래픽 재라우팅 | ✅ | 10.0.6.33이 트래픽 유지 |
| 3 | Backend Error Rate SLO(0.5%) 이내 | ❌ | 실제 9.61% |
| 4 | Redis Sentinel 페일오버 동작 | ✅ | Redis Standby(2b) 자동 승격 확인 |
| 5 | Latency P95 SLO(500ms) 이내 | ✅ | 정상 응답 기준 162ms |

---

## 10. 개선 방향

이번 실험에서 SLO를 크게 위반한 원인은 **불필요한 terminate로 인한 connection reset 대량 발생**이다.

ALB는 인바운드가 차단된 상황에서 인스턴스 자체 장애와 네트워크 일시 차단을 구분할 수 없다. 두 경우 모두 health check 응답을 받지 못하기 때문이다. 이는 현재 구조의 구조적 한계이며, `/api/ping`을 아무리 단순하게 만들어도 해결되지 않는다.

현실적인 개선 방향은 **terminate 발생 시 connection reset을 최소화하는 것**이다.

| 방향 | 내용 |
|------|------|
| Spring Boot graceful shutdown | 종료 전 in-flight 요청을 완료하도록 설정 |
| Deregistration delay 단축 | terminate 시 ALB가 빠르게 인스턴스를 제외하도록 설정 단축 |

AZ 수준의 네트워크 격리에서 불필요한 terminate 자체를 막으려면 Route 53 AZ Affinity나 ALB Cross-Zone Load Balancing 정책 조정이 필요하나 인프라 규모의 비용을 함께 고려해야한다.

---

## 11. 결론

ap-northeast-2a AZ 격리 시 2b AZ의 Backend(10.0.6.33)가 트래픽을 유지하며 Multi-AZ 구성이 동작함을 확인했다. Redis Sentinel 페일오버도 정상 동작했다.
그러나 Error Rate 9.61%로 SLO를 대폭 위반했다. **에러의 99%는 FIS 격리 자체가 아니라, 기존 2a AZ의 Backend가 terminate 과정에서 발생한 connection reset이 원인**이었다.

ALB의 health check endpoint(/api/ping)는 DB/Redis를 체크하지 않는 단순한 구조임에도 불구하고, FIS가 인바운드까지 차단하면서 **ALB가 응답 자체를 받지 못해 Unhealthy로 판정**했다. ALB는 인스턴스 자체 장애와 네트워크 일시 차단을 구분할 수 없다.

구체적으로, Graceful Shutdown이 적용되지 않아 ASG terminate 신호 시 JVM이 즉시 종료됐고, deregistration delay 중 처리되어야 할 **in-flight 요청이 강제 중단되면서 connection reset이 대량 발생**했다. Graceful Shutdown을 적용하면 terminate 시 in-flight 요청을 완료한 후 종료되어 connection reset을 방지할 수 있다.