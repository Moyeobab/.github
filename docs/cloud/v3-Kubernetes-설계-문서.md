> 문서 상태: **설계 진행중 (미완)**
>
> 이 문서는 v3 1단계 전환을 위한 **현재까지의 1차 기준선**을 정리한 문서이며, 모니터링 / Secret / Helm / CI/CD / worker sizing 등은 아직 후속 설계가 남아 있다.

## 1. 문서 목적

이 문서는 v3 전환 시점의 Kubernetes 아키텍처 결정을 한 장으로 정리한 상위 설계 문서다.

현재 기준:

- v3 1단계는 **application layer 우선 클러스터화**
- `backend`, `recommend`를 먼저 Kubernetes로 이전
- data layer와 monitoring 저장/시각화 계층은 당장 전부 클러스터 안으로 넣지 않음

즉, 이번 설계의 목표는 **지금 필요한 application layer 기준선과 운영 표준화를 먼저 만들고, 이후 모니터링 및 배포 운영 구조를 점진적으로 보완할 수 있는 기준선을 잡는 것**이다.

---

## 2. 현재 범위

### 2.1. 클러스터 안

- `backend`
- `recommend`
- 현재 내부 호출도 대부분 `backend -> recommend` 정도로 제한적

### 2.2. 클러스터 밖

- `PostgreSQL`
- `Redis`
- `Qdrant`
- `Kafka`(후속)

### 2.3. 미정

- 모니터링 스택(`Prometheus`, `Promtail`, `Grafana`, `Loki`) 배치 구조

즉 현재는 **애플리케이션만 우선 클러스터 안으로 들이는 단계**이며, 데이터 계층은 클러스터 밖에 둔다. 또한 현재 애플리케이션 구조는 복잡한 서비스 메시형이 아니라, 외부는 `backend` 중심으로 받고 내부는 제한적인 서비스 간 호출만 있는 상태다. 모니터링 스택의 배치 구조는 `2.3 미정` 항목으로 분리해 후속 설계 항목으로 남긴다.

---

## 3. 상위 설계 원칙

이번 설계는 아래 원칙을 따른다.

### 3.1. 레이어별로 “요구사항을 만족하는 최소 복잡도”를 선택한다

무조건 가장 가벼운 구성이나, 무조건 가장 강력한 구성을 택하지 않는다.

- 게이트웨이 계층: 지금 필요한 north-south inbound 진입점을 가장 덜 부담스럽게 운영
- 네트워크 계층: 필요한 private egress / 정책 통제를 실제로 강제
- 데이터 계층: 현재는 외부 EC2를 유지하고 애플리케이션 접근 경로만 명확히 정의

즉, 각 레이어마다 필요한 복잡도만 도입한다.

### 3.2. 현재 단순성을 우선하되, 추후 확장 여지는 남긴다

현재는:

- 외부 공개 진입점 거의 하나
- application layer 중심
- 운영 인원 2명

이므로, 과도한 HA / 과도한 분리 / 과도한 플랫폼화를 피한다.

다만 추후:

- monitoring UI in-cluster
- public/internal 경계 분리

가 필요해질 때 구조가 깨지지 않도록 설계한다.

### 3.3. 인프라 레벨 제어와 워크로드 레벨 제어를 분리한다

- 인프라 레벨: AWS `Security Group`, subnet, LB
- 워크로드 레벨: Kubernetes `Service`, `Gateway API`, `NetworkPolicy`

즉, AWS와 Kubernetes가 각각 잘하는 역할을 나눠서 사용한다.

---

## 4. 주요 설계 결정

### 4.1. 컨트롤 플레인: `single control plane`

현재 단계에서는 `single control plane`을 채택한다.

핵심 이유:

- 현재 규모에서 control plane HA의 주된 이점은 성능보다 **장애 자동 흡수**
- 하지만 `3대 control plane + etcd quorum + LB` 운영 복잡도가 현재 단계에 비해 큼
- control plane 일시 중단은 곧바로 서비스 중단이 아니며, 현재는 수동 복구 가능한 운영 모델을 허용

즉, 현재는 **자동 복구보다 운영 단순성**을 우선한다.

### 4.2. CNI: `Calico`

CNI는 `Flannel`, `Cilium`이 아니라 `Calico`를 채택한다.

핵심 이유:

- 단순 Pod 연결성만 필요한 구조가 아님
- `backend`와 `recommend`의 **private egress를 네트워크 레벨에서 분리**해야 함
- `default deny` 성향의 정책 모델이 필요함

현재 접근 정책의 핵심은:

- `backend` -> `PostgreSQL`, `Redis`, `Kafka`
- `recommend` -> `Qdrant`
- 그 외는 최대한 차단

즉 `Flannel`은 “가벼운 선택”이 아니라, 현재 요구사항에선 **정책 기능 부족으로 미충족**이다.

### 4.3. 진입점 API: `Gateway API`

외부 inbound 진입점 모델은 `Ingress`가 아니라 `Gateway API`를 사용한다.

핵심 이유:

- 현재 요구가 단순하더라도 `Gateway API`도 최소 구성으로 충분히 단순하게 시작 가능
- `Gateway`와 `HTTPRoute`로 입구와 라우팅 책임 경계를 더 명확히 나눌 수 있음
- 특정 Ingress 컨트롤러 annotation 모델에 빨리 종속될 필요가 없음

즉, 현재 단순성을 해치지 않으면서 장기 방향성을 확보하는 선택이다.

### 4.4. Gateway 구현체: `Traefik`

`Gateway API` 구현체는 현재 단계에서 `Traefik`을 우선 채택한다.

핵심 이유:

- 현재 외부 공개 진입점이 거의 `api -> backend` 하나
- 지금 필요한 north-south inbound 진입점을 가장 덜 부담스럽게 운영 가능
- 벤더 중립적인 형태로 시작 가능
- `Envoy` / `NGINX` 계열처럼 지금부터 게이트웨이 데이터플레인 구조를 깊게 의식하지 않아도 됨

즉, 현재 단계에선 “가장 강력한 구현체”보다 **가볍게 시작하기 좋은 구현체**가 더 중요하다.

### 4.5. 클러스터 앞단 LB: `public NLB` 우선

현재 외부 inbound 진입 구조는 **`public NLB`를 앞단 LB 기본안**으로 본다.

기본 흐름:

`Client -> public NLB -> private worker node(NodePort) -> Traefik -> backend Service -> backend Pod`

선정 이유:

- `Gateway API + Traefik`가 이미 L7을 담당
- 앞단 LB는 L4 전달만 하는 편이 역할 분리가 더 명확함
- worker node를 public으로 직접 노출하지 않고, public LB + private node 구조를 유지할 수 있음

즉 `ALB`보다 `NLB`가 현재 구조와 더 일관적이다.

---

## 5. 네트워크 및 통신 설계

## 5.1. 외부 inbound 트래픽

현재 외부 공개 트래픽은 사실상 아래 한 축이다.

- `api.example.com -> backend`

초기 운영안:

- `Gateway` 1개
- `HTTPRoute` 1개(또는 소수)
- public/internal 분리는 지금 당장 하지 않음

public/internal 분리는 아래 시점에 재검토한다.

- `Grafana`
- `Argo CD`
- 기타 운영자용 UI

가 클러스터 안으로 들어올 때

## 5.2. 내부 서비스 통신

같은 클러스터 내부 통신은 Kubernetes `Service`로 처리한다.

예:

`backend Pod -> recommend Service(ClusterIP) -> recommend Pod`

즉, 내부 서비스 간 로드밸런싱을 위해 별도 internal ALB를 두지 않는다.

## 5.3. Pod -> EC2 data layer 통신

현재 단계에서는 외부 데이터 계층을 Kubernetes 리소스로 감싸지 않고, **기존 Route 53 private DNS를 공식 엔드포인트로 사용**한다.

예:

- `postgres.internal`
- `redis.internal`
- `qdrant.internal`

현재 기본 구조:

`Pod -> CoreDNS -> Route 53 private DNS -> EC2 private endpoint`

보안 모델:

- 인프라 레벨 허용: 해당 클러스터의 `worker node SG`
- 워크로드 레벨 허용: `Calico NetworkPolicy`

즉:

- 데이터 영역은 해당 클러스터의 worker node SG만 허용
- Pod별 접근 허용은 NetworkPolicy로 제한

현재 접근 원칙:

- `backend`: `PostgreSQL`, `Redis`, `Kafka`
- `recommend`: `Qdrant`
- 그 외: 기본 차단

## 5.4. 클러스터 분리 전제

`dev`와 `prod`는 같은 클러스터 안의 환경 분리가 아니라, **서로 다른 클러스터**로 운영한다.

즉 현재 설계는:

- `dev` 클러스터에서 먼저 구조를 검증
- 이후 `prod` 클러스터에 동일한 원칙을 별도 적용

하는 전제를 둔다.

따라서 DNS, SG, NetworkPolicy도 “한 클러스터 안에서 dev/prod를 나누는 구조”가 아니라, **각 클러스터가 자기 데이터 영역만 바라보는 구조**로 가져간다.

---

## 6. 추가 설계 예정 영역 (**이하 항목은 현재 미확정**)

아래 내용은 **현재 기준 설계(1~5장)** 에 포함되는 확정 사항이 아니라,  
이번 기준선 확정 이후 별도 이슈로 순차 설계할 후속 항목이다.

즉 이 문서는 **전체 설계 완료본이 아니라, 현재까지 확정된 부분과 미확정 부분을 분리해 보여주는 진행중 문서**다.

즉 PL 관점에서는:

- `1~5장`: 현재 기준선으로 승인/검토
- `6장 이하`: 추가 설계 예정 범위로 추후 확정

### 6.1. 모니터링 전환: 별도 설계 이슈에서 확정

모니터링 스택의 구체적인 배치와 수집 경로는 이번 문서에서 확정하지 않고, **별도 모니터링 전환 설계 이슈에서 확정**한다.

현재 후속 설계 범위:

- `Prometheus`를 클러스터 안/밖 중 어디에 둘지
- `Promtail`을 `DaemonSet`으로 둘지
- `Grafana` / `Loki`를 기존 monitoring EC2에 둘지, 일부 또는 전부를 클러스터 안으로 옮길지
- 메트릭 수집 경로를 직접 조회로 둘지, `remote_write` 계열로 둘지
- 수집기 고가용성(`replicas`, `shards`)을 지금부터 고려할지

다만 현재 기준으로 분명한 점은 아래뿐이다.

- `backend`와 `recommend`는 Pod별 메트릭 엔드포인트를 가진다
- Kubernetes 전환 이후에는 Pod 단위 디스커버리를 고려한 수집 방식이 필요하다
- 모니터링은 “현재 설계에 포함되지 않음”이 아니라, 별도 전환 설계에서 이어서 확정하는 항목이다

### 6.2. 추가 설계 예정 항목 (상태 포함)

PL 관점에서 현재 추가 설계가 필요한 항목과 상태는 아래와 같다.

| 항목 | 상태 | 비고 |
| --- | --- | --- |
| 모니터링 전환 방안 | 진행중 | `Prometheus` / `Promtail` / `Grafana` / `Loki` 배치와 수집 경로 확정 필요 |
| Secret 관리 방식 | 예정 | `K8s Secret` vs `SSM` 기본안 결정 필요 |
| Helm 차트 구조 | 예정 | chart 분리 단위와 values 구조 표준화 필요 |
| CI/CD 파이프라인 설계 | 예정 | 이미지 빌드/배포 흐름과 Helm 연계 방식 정의 필요 |
| 워커 노드 정확한 sizing | 예정 | K8s 기준 실측 후 확정 |
| Kafka 상세 네트워킹 | 예정 | broker 경로 / advertised listeners 별도 설계 필요 |

### 6.3. 현재 남아 있는 후속 설계 항목

현재 일부 항목은 의도적으로 확정하지 않았다.

#### 6.3.1. 워커 노드 정확한 sizing

- 인스턴스 타입
- 노드 수

는 K8s 환경에서 측정 후 확정

#### 6.3.2. Kafka 상세 네트워킹

- bootstrap 외 broker 연결
- advertised listeners
- 내부/외부 경로 분리

는 별도 예외 항목으로 후속 설계

#### 6.3.3. 모니터링 스택 배치 구조

- `Prometheus`
- `Promtail`
- `Grafana`
- `Loki`

의 배치와 연결 경로는 모니터링 전환 이슈에서 별도 확정

#### 6.3.4. Secret 관리 방식

- `K8s Secret`
- `SSM` 연동

중 어떤 방식을 기본으로 둘지

#### 6.3.5. Helm 차트 구조

- 앱별 chart 분리
- 공통 values 구조
- 환경별 override 방식

을 어떻게 가져갈지

#### 6.3.6. CI/CD 파이프라인 설계

- 이미지 빌드/배포 흐름
- Helm 배포 연계 방식
- 배포 환경(dev -> prod) 전개 순서

를 어떻게 표준화할지

### 6.4. 추후 확장 및 후속 설계 시 재검토 체크리스트

#### 6.4.1. 모니터링 구조를 확정할 때

아래를 다시 검토한다.

- `Prometheus`, `Promtail`, `Grafana`, `Loki`의 배치 위치
- Pod 단위 메트릭 수집 경로와 서비스 디스커버리 방식
- 메트릭 저장 구조(직접 조회 / `remote_write` / 장기 저장 계층)
- 로그 수집 경로와 `Loki` 저장 구조
- monitoring 전용 `namespace` 필요 여부
- internal Gateway / VPN 전용 접근 정책
- RBAC / 인증
- `Prometheus` HA / `replicas` / `shards` / dedup 계층

#### 6.4.2. Secret / Helm / CI/CD를 확정할 때

아래를 다시 검토한다.

- `K8s Secret`과 `SSM`의 책임 경계
- 런타임 시크릿 주입 방식
- Helm chart의 공통 템플릿과 앱별 분리 기준
- values 파일의 환경별 분리 방식
- CI/CD에서 이미지 태깅 / values 주입 / 배포 승인 흐름
- `dev` 클러스터 검증 후 `prod` 클러스터 반영 절차

#### 6.4.3. 모니터링 구조를 확정할 때 함께 봐야 할 운영 경계

아래를 공통으로 다시 검토한다.

- `app` / `monitoring` 네임스페이스 경계
- namespace 간 `NetworkPolicy`
- internal/public 분리
- 전용 node pool 필요 여부
- 리소스 경쟁 격리
- 백업/복구와 모니터링 의존성

즉, 이후 확장 시점에는 단순히 컴포넌트를 안으로 옮기는 것이 아니라, **레이어 경계와 운영 책임을 다시 설계**해야 한다.

---

## 7. 현재까지 확정된 1차 기준선 요약 (**설계 미완**)

현재 v3 1단계의 기준 설계는 아래와 같다.

1. 컨트롤 플레인은 `single control plane`
2. CNI는 `Calico`
3. 진입점 API는 `Gateway API`
4. 구현체는 `Traefik`
5. 앞단 LB는 `public NLB` 우선
6. 외부 data layer 접근은 `Route 53 private DNS + worker node SG + NetworkPolicy`
7. 워커 sizing, Kafka 상세 네트워킹, 모니터링 전환, Secret, Helm, CI/CD는 후속 설계 항목으로 남긴다

### 7.1. 현재 판단 문장

> 현재 v3 1단계 Kubernetes 설계는 application layer를 우선 클러스터화하는 것을 기준으로 하며, 운영 복잡도를 과도하게 키우지 않는 범위에서 필요한 제어면과 네트워크 정책을 확보하는 방향으로 구성한다. 따라서 `single control plane + Calico + Gateway API + Traefik + public NLB`를 현재 기준선으로 두고, 외부 data layer는 `private DNS + worker node SG + NetworkPolicy`로 연동한다. worker sizing, Kafka 세부 네트워킹, 모니터링 전환 방안, 그리고 `K8s Secret/SSM`, Helm, CI/CD 표준화는 후속 설계 항목으로 남기며, 모니터링 구조 확정 시점과 배포 표준화 시점에 다시 확정한다.
