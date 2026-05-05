# 이미지 관리 방안

## 컨테이너 레지스트리 선택: Amazon ECR Private

### 비교 대상

- **Docker Hub Private**: 외부 레지스트리 (Pro $7/월/사용자, Team $9/월/사용자)
- **ECR Private**: AWS 내부 레지스트리 (사용량 기반 과금)
- **ECR Public**: AWS 공개 레지스트리 (사용량 기반 과금)

---

## 1. 기본 요금 구조

| **항목** | **Docker Hub Private** | **ECR Private** | **ECR Public** |
| --- | --- | --- | --- |
| **기본 요금** | Pro $7/월/사용자, Team $9/월/사용자 | 무료 (사용량 기반) | 무료 (사용량 기반) |
| **스토리지** | 플랜에 포함 | $0.10/GB/월 | $0.10/GB/월 |
| **Pull 제한** | Pro: 5,000/일, Team: 무제한 | 무제한 | 무제한 |

---

## 2. 데이터 전송 비용 (핵심 차이)

| **시나리오** | **Docker Hub → EC2** | **ECR Private → EC2** | **ECR Public → EC2** |
| --- | --- | --- | --- |
| **같은 리전** | 인터넷 전송 + NAT GW 비용 | **무료** | **무료** |
| **다른 리전** | 인터넷 전송 + NAT GW 비용 | $0.09/GB | $0.09/GB (5TB 초과 시) |

---

## 3. 우리 서비스 기준 월 비용 시뮬레이션

### 가정

- 이미지 크기: Spring 300MB, FastAPI 500MB = 총 800MB
- 월 배포 횟수: 100회
- 총 Pull 용량: 800MB × 100회 = 80GB/월
- 스토리지: 100개 이미지 × 평균 400MB = 40GB
- **NAT GW는 외부 API 연동 등 다른 용도로 이미 사용 중** (기본 비용 제외)

| **항목** | **Docker Hub Pro (5명)** | **ECR Private (NAT GW 경유)** |
| --- | --- | --- |
| **기본 요금** | $35/월 (약 47,000원) | $0 |
| **스토리지** | 포함 | 40GB × $0.10 = $4 (약 5,400원) |
| **NAT GW 데이터 처리** | 80GB × $0.045 = $3.6 | 80GB × $0.045 = $3.6 |
| **합계** | **약 $38.6/월 (52,000원)** | **약 $7.6/월 (10,200원)** |

---

## 4. VPC Endpoint 도입 검토

VPC Endpoint를 사용하면 NAT GW를 경유하지 않고 AWS 내부 네트워크로 ECR에 접근할 수 있습니다.

| **항목** | **NAT GW 경유 (현재)** | **VPC Endpoint 사용** |
| --- | --- | --- |
| **ECR 스토리지** | $4/월 | $4/월 |
| **NAT GW 데이터 처리** | $3.6/월 | $0 (제거) |
| **VPC Endpoint 비용** | $0 | $0.01/시간 × 2개 × 720시간 = $14.4/월 |
| **VPC Endpoint 데이터 처리** | $0 | 80GB × $0.01 = $0.8/월 |
| **합계** | **$7.6/월** | **$19.2/월** |

**결론**: VPC Endpoint 도입 시 월 $11.6 추가 비용 발생. 보안상 인터넷 노출 최소화가 필수가 아니라면 **NAT GW 경유 유지**가 비용 효율적입니다.

---

## 5. 보안 관점

| **항목** | **Docker Hub Private** | **ECR Private** |
| --- | --- | --- |
| **접근 제어** | Docker 계정 기반 | IAM 기반 |
| **Public 노출 시 위험** | 무분별한 pull → 비용 폭증 | VPC 내부만 접근 가능 |
| **Pull 공격 방어** | Rate limit으로 일부 방어 | 네트워크 레벨에서 원천 차단 |

**Private 선택 이유**: Public으로 노출될 경우 외부에서 무분별하게 pull을 당기는 공격이 발생할 수 있으며, 이는 비용 폭증으로 이어집니다. ECR Private은 IAM 기반 접근 제어로 허가된 사용자/서비스만 접근할 수 있습니다.

---

## 6. 기타 비교

| **항목** | **Docker Hub** | **ECR Private** | **선택** |
| --- | --- | --- | --- |
| **권한 관리** | Docker Hub 계정 기반 | IAM 기반 세밀한 권한 제어 | ECR |
| **CI/CD 통합** | 별도 인증 설정 필요 | GitHub Actions | ECR |
| **Lifecycle 정책** | 제한적 | 세밀한 정책 설정 가능 | ECR |

---

## 7. 결론: ECR Private 선택 이유

1. **비용**: 월 약 50,000원 절감 (Docker Hub 대비)
2. **네트워크**: 같은 리전 내 AWS 서비스로 pull 시 **무료**
3. **보안**: IAM 기반 접근 제어로 허가된 사용자만 접근 가능
4. **통합**: GitHub Actions와 간편하게 연동

---

## ECR 리포지토리 구조

### 서비스별 분리 전략

```
tastecompass/spring-backend    # Spring Boot 백엔드
tastecompass/fastapi-ai        # FastAPI 모델 서빙
```

### 분리 이유

| **이점** | **설명** |
| --- | --- |
| **독립 배포** | Spring/FastAPI 빌드·배포 주기가 달라도 서로 영향 없음 |
| **Lifecycle 정책 분리** | 서비스별 이미지 보존 정책을 다르게 설정 가능 |
| **권한 분리** | 서비스 단위로 IAM 권한, 취약점 스캔, 이벤트 추적 가능 |
| **사고 대응** | 문제 발생 시 서비스 단위로 원인 추적 용이 |

---

## 태깅 전략

### 핵심 원칙: 불변(Immutable) 태그 기반

| **태그 유형** | **형식** | **용도** | **예시** |
| --- | --- | --- | --- |
| **불변 태그** (필수) | `sha-<gitsha>` | 특정 커밋 = 특정 이미지 식별 | `sha-a1b2c3d` |
| **환경 포인터** (선택) | `dev`, `prod` | 현재 환경이 가리키는 버전 | `prod` |

### 배포 환경

- **dev**: 개발/테스트 환경
- **prod**: 운영 환경

### 태깅 전략 선택 이유

| 비교 항목 | `latest`/`previous` 방식 | `sha-<gitsha>` 방식 |
| --- | --- | --- |
| **추적성** | 가변 태그라 어떤 커밋인지 불명확 | 커밋 = 이미지 1:1 매핑 |
| **롤백** | 동시 배포/핫픽스 시 꼬일 위험 | 언제든 특정 SHA로 확실한 롤백 |
| **자동화** | 수동 버전 관리 필요 | GitHub Actions에서 자동 태깅 |
| **안정성** | 가변 → 예측 불가능 | 불변 → 예측 가능 |

### GitHub Actions 태깅 예시

```yaml
- name: Build and Push
  env:
    IMAGE_TAG: sha-$ github.sha
  run: |
    docker build -t $ECR_REGISTRY/tastecompass/spring-backend:$IMAGE_TAG .
    docker push $ECR_REGISTRY/tastecompass/spring-backend:$IMAGE_TAG

    # 환경 포인터 태그 (선택)
    docker tag $ECR_REGISTRY/tastecompass/spring-backend:$IMAGE_TAG \
               $ECR_REGISTRY/tastecompass/spring-backend:prod
    docker push $ECR_REGISTRY/tastecompass/spring-backend:prod
```

---

## 롤백 전략

### "바로 이전 버전" 롤백 방법

`previous` 태그 대신 **배포 기록 기반 롤백**을 사용합니다.

| **방식** | **previous 태그** | **배포 기록 기반 (선택)** |
| --- | --- | --- |
| **안정성** | 동시 배포/핫픽스 시 꼬임 | SHA가 고정이라 확실 |
| **추적성** | "previous가 뭐였지?" | 배포 로그에서 즉시 확인 |
| **롤백 절차** | previous 태그 재배포 | 직전 sha-xxxx 지정 재배포 |

### 롤백 절차

1. GitHub Actions 배포 로그에서 직전 배포된 `sha-xxxx` 확인
2. 해당 SHA 태그로 재배포 트리거
3. 완료

---

## SemVer(v1.0.0)는 필요한가?

| 상황 | 필요 여부 |
| --- | --- |
| 현재 (내부 운영) | 불필요 (SHA가 더 정확) |
| 대외 릴리즈/체인지로그 필요 시 | 추가로 병행 가능 |

→ 필요해지면 `sha-xxxx`와 `v1.0.0`을 **동시에** 붙이면 됨 (대체 아님).

---

## 이미지 보존 정책 (ECR Lifecycle Policy)

### 정책 설정 이유

- dev 환경은 CI가 돌 때마다 이미지 생성 → 안 치우면 비용/용량 증가
- prod는 롤백 대응을 위해 충분한 버전 유지 필요

### 서비스별 Lifecycle Policy

| **대상** | **정책** | **이유** |
| --- | --- | --- |
| **prod 태그** | 삭제 제외 (또는 넉넉히 유지) | 장애/롤백 대응 보장 |
| **sha-*** (prod) | 최근 100개 유지 | 충분한 롤백 포인트 확보 |
| **sha-*** (dev) | 30일 초과 삭제 | 빌드 많으면 14일로 조정 가능 |
| **untagged** | 7일 초과 삭제 | 리태그 과정에서 생기는 잔여물 정리 |

---

## 이미지 관리 방안 요약

| **항목** | **결정** |
| --- | --- |
| **레지스트리** | Amazon ECR Private |
| **리포지토리 구조** | 서비스별 분리 (`tastecompass/spring-backend`, `tastecompass/fastapi-ai`) |
| **태깅 전략** | 불변 태그 `sha-<gitsha>` + 환경 포인터 `dev`/`prod` |
| **롤백 방식** | 배포 기록에서 직전 SHA 확인 → 재배포 |
| **보존 정책** | prod sha-* 100개 유지, dev 30일 초과 삭제, untagged 7일 삭제 |
| **빌드/배포** | 독립 배포 (서비스별 개별 배포 가능) |
