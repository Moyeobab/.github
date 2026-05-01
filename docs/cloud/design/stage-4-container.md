# 개요

본 문서는 MAU 100만 음식점 추천 서비스의 Docker 컨테이너화 설계를 종합 정리한 문서입니다.

| **항목** | **내용** |
| --- | --- |
| **서비스** | 취향 기반 맛집 추천 + 실시간 투표 서비스 |
| **MAU** | 100만 명 |
| **핵심 목표** | 피크 트래픽(100 RPS) 안정 처리 |

---

# 1. RPS 산정

## 기본 가정

| **항목** | **값** |
| --- | --- |
| **MAU** | 100만 명 |
| **DAU** | MAU의 30% = **30만 명** |
| **1인당 일일 평균 요청 수** | 10회 |
| **일일 총 요청 수** | 30만 × 10 = **300만 건** |

## 평시 RPS

**평시 RPS** = 3,000,000 ÷ 86,400 ≈ **35 RPS**

## 피크 RPS

- **피크 시간**: 점심(11:30 ~ 14:00), 저녁(17:30 ~ 20:00) → 총 **5시간**
- **피크 트래픽 비중**: 일일 트래픽의 약 **60%**

**피크 RPS** = (3,000,000 × 0.6) ÷ (5 × 3,600) = **100 RPS**

## 정리

| **구분** | **RPS** | **비고** |
| --- | --- | --- |
| **평시** | ~35 RPS |  |
| **피크 평균** | ~100 RPS | 평시 대비 약 3배 |
| **피크 최대** | 150~200 RPS | 순간 집중 시 |

---

# 2. Docker 도입 배경

## 서비스 개요

본 서비스는 유저의 취향을 분석하여 최적의 맛집을 제안하고, 실시간 투표를 통해 그룹 내 의사결정을 돕는 데이터 기반 음식점 추천 서비스입니다.

## 폭발적인 성장, 그리고 새로운 과제

서비스 출시 이후 폭발적인 성장을 거듭하여 MAU 100만을 달성하게 되었습니다.

하지만 성장과 함께 새로운 문제가 발생했습니다. 기존의 단일 인스턴스 구조로는 더 이상 트래픽을 감당할 수 없는 상황이 된 것입니다. 특히 음식점 추천 서비스 특성상 점심과 저녁 시간대에 트래픽이 집중되면서, 피크 타임에 서버가 한계에 도달하는 일이 빈번해졌습니다.

---

## 2.1. 피크 타임 대응을 위한 스케일 아웃

### 트래픽 특성

- **피크 시간**: 점심(11:30~14:00), 저녁(17:30~20:00)
- **피크 RPS**: 평시 대비 약 **3배** 증가 (순간 최대 5배 이상)
- **피크 시간 트래픽 비중**: 일일 트래픽의 약 60%

### 왜 스케일 아웃인가?

피크 시간이 명확하게 예측 가능하고, 나머지 시간대는 트래픽이 낮습니다. 따라서 **피크 시간에만 서버를 늘리고, 평시에는 줄이는 스케일 아웃 전략**이 비용 효율적입니다.

### 스케일 아웃을 어떻게 안정적으로 할 것인가?

| **방식** | **문제점** |
| --- | --- |
| 직접 수동 배포 | 명령어 실수, 포트 설정 오류 등 휴먼 에러 위험 |
| 쉘 스크립트 | 표준화되지 않음. 서버 환경에 따라 실패할 수 있음. 팀원마다 다르게 작성 가능 |
| **컨테이너** | 이식성과 표준화된 인터페이스로 해결 |

### 컨테이너의 이식성이 안정적인 스케일 아웃을 지원한다

컨테이너 이미지 = **애플리케이션 + 실행 환경 전체**를 하나로 패키징

**1. 일관성/재현 가능성**

- 쉘 스크립트: 서버 환경에 따라 실패할 수 있음 (버전 차이, 설치된 패키지 등)
- 컨테이너: 이미지 안에 환경이 다 들어있어서 **어디서든 동일하게 실행**

**2. 표준화**

- 쉘 스크립트: 팀원마다 다르게 작성 가능
- 컨테이너: Dockerfile이라는 표준 명세, `docker run`이라는 통일된 인터페이스

**3. 실패 위험 감소**

- 새 서버에서 "환경 문제로 안 돌아가는" 상황을 원천 차단

→ **이식성 덕분에 어디서든 동일하게, 안정적으로 서버 복제 가능**

---

## 2.2. 개발-배포 환경 일치

### 컨테이너화 대상

- **Spring Boot 애플리케이션**
- **FastAPI 모델 서빙**

### 문제 상황

여러 개발자가 협업하는데, 각자의 로컬 환경(OS, 라이브러리 버전)이 달라서 "내 컴퓨터에서는 되는데요" 문제가 발생합니다.

### 특히 까다로운 부분: FastAPI 모델 서빙

- CUDA, cuDNN, PyTorch 버전 조합이 정확해야 함
- 네이티브 레벨 의존성이 있어 버전 호환성이 매우 중요
- 조금만 틀어져도 모델이 로드되지 않거나 런타임 에러 발생

### 컨테이너 해결책

```
# Spring Boot
FROM eclipse-temurin:21-jre-alpine
COPY app.jar /app.jar
# 모든 환경에서 정확히 동일한 JDK 버전

# FastAPI 모델 서빙
FROM python:3.11-slim
RUN pip install fastapi==0.104.1 torch==2.1.0
COPY model/ /app/model/
```

### 효과

- 개발 환경 = 운영 환경
- 환경 차이로 인한 버그 제거
- 신입 개발자도 `docker` 명령어 한 줄로 환경 구축

---

## 2.3. 도입 배경 정리

| **도입 이유** | **컨테이너의 해결책** |
| --- | --- |
| **피크 타임 스케일 아웃** | 이식성 기반으로 어디서든 동일하게, 안정적으로 서버 복제 |
| **개발-배포 환경 일치** | 이미지로 환경 전체를 패키징, 어디서든 동일하게 실행 |
| **복잡한 의존성 관리** | CUDA/PyTorch 등 버전을 이미지에 고정 |

---

# 3. 컨테이너화 범위

우리 서비스는 Spring 백엔드, FastAPI AI, PostgreSQL, Redis, 프론트엔드로 구성되어 있습니다. 각 구성 요소의 특성에 따라 컨테이너화 여부를 결정했습니다.

## 컨테이너화 판단 기준 (Docker 도입 이유 기반)

1. 피크 타임 대응을 위한 스케일 아웃이 필요한가?
2. 복잡한 의존성 관리가 필요한가?

---

## 컨테이너화 범위 요약

| **구성 요소** | **컨테이너화** | **이유** |
| --- | --- | --- |
| **Spring 백엔드** | O | 스케일 아웃 대상, 이식성 필요 |
| **FastAPI AI** | O | CUDA/PyTorch 의존성 복잡, 환경 일치 필수 |
| **Redis** | X 호스트 | 스케일 아웃 대상 아님, 복잡한 의존성 없음 |
| **프론트엔드** | X Cloudfront + S3 | S3 정적 배포 (서버가 아님) |
| **PostgreSQL** | X 호스트 | 스케일 아웃 대상 아님, 복잡한 의존성 없음 |

---

## 3.1. 컨테이너화하는 것

### Spring

**이유**: 스케일 아웃 대상

- 피크 타임에 인스턴스를 늘려야 함
- 컨테이너 이식성으로 어디서든 동일하게, 안정적으로 서버 복제 가능
- 표준화된 배포 인터페이스 (`docker run`)

### FastAPI AI

**이유**: 복잡한 의존성 관리

- CUDA, cuDNN, PyTorch 버전 조합이 정확해야 함
- 네이티브 레벨 의존성이 있어 버전 호환성이 매우 중요
- 조금만 틀어져도 모델이 로드되지 않거나 런타임 에러 발생
- Dockerfile로 의존성 버전을 완전히 고정

```
FROM python:3.11-slim
RUN pip install fastapi==0.104.1 torch==2.1.0
COPY model/ /app/model/
# 의존성 버전 완전 고정

```

---

## 3.2. 컨테이너화하지 않는 것

### PostgreSQL - 호스트 직접 설치

**이유**: 컨테이너화할 이유가 없음, Steteful 워크로드라 볼륨 관리 복잡, 데이터 영속성 리스크

**1. 스케일 아웃이 필요한가?**

- PostgreSQL은 스케일 아웃 대상이 아님
- 수평 확장하지 않고 Primary-Replica 이중화로 운영

**2. 복잡한 의존성 관리가 필요한가?**

- PostgreSQL은 복잡한 의존성이 없음
- Spring/FastAPI처럼 CUDA, PyTorch 같은 네이티브 의존성 없음
- apt install로 설치하면 끝

**결론**: 컨테이너화의 핵심 이점(이식성으로 스케일 아웃, 의존성 고정)이 PostgreSQL에는 해당되지 않습니다. 굳이 컨테이너화할 필요가 없습니다.

### Redis - 호스트 직접 설치

**이유**: 컨테이너화할 이유가 없음

**1. 스케일 아웃이 필요한가?**

- Redis는 스케일 아웃 대상이 아님
- Master-Replica 이중화로 운영 (수평 확장 아님)

**2. 복잡한 의존성 관리가 필요한가?**

- Redis는 복잡한 의존성이 없음
- `apt install redis`로 설치하면 끝

**결론**: PostgreSQL과 동일한 논리. 컨테이너화의 핵심 이점이 Redis에도 해당되지 않습니다.

### 프론트엔드 - S3 정적 배포

**이유**: 서버가 아님

- React+Vite 빌드 결과물은 정적 파일 (HTML, JS, CSS)
- S3에 업로드하고 CloudFront로 배포하면 끝
- 실행되는 "서버"가 아니므로 컨테이너 불필요

---

## 3.3. 컨테이너화 범위 정리

| **구성 요소** | **결정** | **핵심 이유** |
| --- | --- | --- |
| **Spring 백엔드** | 컨테이너 | 스케일 아웃 대상 → 이식성 필요 |
| **FastAPI AI** | 컨테이너 | CUDA/PyTorch 복잡한 의존성 → 환경 고정 필요 |
| **Redis** | 호스트 | 스케일 아웃 안 함, 복잡한 의존성 없음 → 컨테이너화 이유 없음 |
| **프론트엔드** | S3 | 정적 파일, 서버 아님 |
| **PostgreSQL** | 호스트 | 스케일 아웃 안 함, 복잡한 의존성 없음 → 컨테이너화 이유 없음 |

**결론**: 우리가 세운 컨테이너화 기준(스케일 아웃 필요, 복잡한 의존성)에 해당하는 것만 컨테이너화합니다. Redis와 PostgreSQL은 둘 다 이 기준에 해당하지 않으므로 호스트에 직접 설치합니다.

---

# 4. 인프라 비용

## 핵심 목표

**MAU 100만 서비스를 최소 비용으로 운영**하면서, 피크 트래픽(100 RPS)을 안정적으로 처리하는 것이 목표였습니다.

---

## 최종 인프라 비용

| **항목** | **구성** | **월 예상 비용** |
| --- | --- | --- |
| **EC2 - PostgreSQL** | t4g.small × 2대 (Primary + Replica) | 약 43,000원 |
| **EC2 - Redis** | t4g.small × 2대 (Master + Replica) | 약 43,000원 |
| **EC2 - WAS 평시** | t4g.small × 2대 × 19h/일 | 약 34,000원 |
| **EC2 - WAS 피크** | t4g.small × 8대 × 5h/일 (Auto Scaling) | 약 36,000원 |
| **EBS (gp3)** | 30GB × 6대 | 약 27,000원 |
| **ALB** | 단일 AZ | 약 30,000원 |
| **NAT Gateway** | 1개 | 약 65,000원 |
| **S3 + CloudFront** | 프론트엔드 정적 파일 | 약 14,000원 |
| **데이터 전송** | 월 100GB 가정 | 약 17,000원 |
| **합계** |  | **약 309,000원** |

---

## Docker 도입으로 얻은 것

### 비용 외 핵심 이점

| **항목** | **기존** | **Docker 적용** |
| --- | --- | --- |
| **확장 시간** | 60분 | 10초 |
| **배포 시간** | 6-11분 | 10-30초 |

---

## Trade-off: 무엇을 포기했는가

### 단일 AZ 구성의 리스크

**Multi-AZ를 포기**하여 인프라 레벨 가용성은 낮지만, 애플리케이션 레벨에서 다중 인스턴스로 단일 인스턴스 장애는 대응 가능합니다.

- **AZ 장애 대응**: AZ 단위 장애는 재해 수준으로 간주하고 감수
- **데이터베이스**: RDS 대신 PostgreSQL 호스트 직접 운영 (운영 부담 증가)
- **캐시**: ElastiCache 대신 Redis 호스트 직접 운영 (운영 부담 증가)

---

## 결론

**Docker는 단순히 문제를 해결하는 도구가 아니라, MAU 100만 서비스를 최소 비용으로 운영하려는 우리의 목표를 달성하기 위한 최적의 선택이었습니다.**

### 핵심 의사결정 요약

| **목표** | **Docker 선택 이유** | **달성 결과** |
| --- | --- | --- |
| 예산 준수 | 관리형 서비스 대신 컨테이너 | 월 32만원 절감 |
| 피크 대응 | 10초 만에 컨테이너 확장 | 100 RPS 처리 가능 |
| 가용성 | Primary-Replica 이중화 | 99.5% 달성 |

### 컨테이너 구조 다이어그램

<img width="1168" height="630" alt="image" src="https://github.com/user-attachments/assets/d0b909f6-831f-485f-8ae4-e243ee14732a" />

---

# 5. 이미지 관리 방안

## 컨테이너 레지스트리 선택: Amazon ECR Private

### 비교 대상

- **Docker Hub Private**: 외부 레지스트리 (Pro $7/월/사용자, Team $9/월/사용자)
- **ECR Private**: AWS 내부 레지스트리 (사용량 기반 과금)
- **ECR Public**: AWS 공개 레지스트리 (사용량 기반 과금)

---

## 5.1. 기본 요금 구조

| **항목** | **Docker Hub Private** | **ECR Private** | **ECR Public** |
| --- | --- | --- | --- |
| **기본 요금** | Pro $7/월/사용자, Team $9/월/사용자 | 무료 (사용량 기반) | 무료 (사용량 기반) |
| **스토리지** | 플랜에 포함 | $0.10/GB/월 | $0.10/GB/월 |
| **Pull 제한** | Pro: 5,000/일, Team: 무제한 | 무제한 | 무제한 |

---

## 5.2. 데이터 전송 비용 (핵심 차이)

| **시나리오** | **Docker Hub → EC2** | **ECR Private → EC2** | **ECR Public → EC2** |
| --- | --- | --- | --- |
| **같은 리전** | 인터넷 전송 + NAT GW 비용 | **무료** | **무료** |
| **다른 리전** | 인터넷 전송 + NAT GW 비용 | $0.09/GB | $0.09/GB (5TB 초과 시) |

---

## 5.3. 우리 서비스 기준 월 비용 시뮬레이션

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

## 5.4. VPC Endpoint 도입 검토

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

## 5.5. 보안 관점

| **항목** | **Docker Hub Private** | **ECR Private** |
| --- | --- | --- |
| **접근 제어** | Docker 계정 기반 | IAM 기반 |
| **Public 노출 시 위험** | 무분별한 pull → 비용 폭증 | VPC 내부만 접근 가능 |
| **Pull 공격 방어** | Rate limit으로 일부 방어 | 네트워크 레벨에서 원천 차단 |

**Private 선택 이유**: Public으로 노출될 경우 외부에서 무분별하게 pull을 당기는 공격이 발생할 수 있으며, 이는 비용 폭증으로 이어집니다. ECR Private은 IAM 기반 접근 제어로 허가된 사용자/서비스만 접근할 수 있습니다.

---

## 5.6. 기타 비교

| **항목** | **Docker Hub** | **ECR Private** | **선택** |
| --- | --- | --- | --- |
| **권한 관리** | Docker Hub 계정 기반 | IAM 기반 세밀한 권한 제어 | ECR |
| **CI/CD 통합** | 별도 인증 설정 필요 | GitHub Actions | ECR |
| **Lifecycle 정책** | 제한적 | 세밀한 정책 설정 가능 | ECR |

---

## 5.7. 결론: ECR Private 선택 이유

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
| **불변 태그** (필수) | `sha-\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\<gitsha\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\>` | 특정 커밋 = 특정 이미지 식별 | `sha-a1b2c3d` |
| **환경 포인터** (선택) | `dev`, `prod` | 현재 환경이 가리키는 버전 | `prod` |

### 배포 환경

- **dev**: 개발/테스트 환경
- **prod**: 운영 환경

### 태깅 전략 선택 이유

| 비교 항목 | `latest`/`previous` 방식 | `sha-\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\<gitsha\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\>` 방식 |
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
| **태깅 전략** | 불변 태그 `sha-\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\<gitsha\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\>` + 환경 포인터 `dev`/`prod` |
| **롤백 방식** | 배포 기록에서 직전 SHA 확인 → 재배포 |
| **보존 정책** | prod sha-* 100개 유지, dev 30일 초과 삭제, untagged 7일 삭제 |
| **빌드/배포** | 독립 배포 (서비스별 개별 배포 가능) |

---

# 6. 기술 구성 명세

## 컨테이너별 기술 스택

| **항목** | **Spring Boot Backend** | **FastAPI AI** | **Frontend (React+Vite)** |
| --- | --- | --- | --- |
| **베이스 이미지** | eclipse-temurin:21-jre-alpine | python:3.11-slim | nginx:alpine |
| **빌드 도구** | Gradle | requirements.txt | npm (Vite) |
| **노출 포트** | 8080 | 8000 | 80 |
| **헬스체크** | /actuator/health | /health | nginx health |
| **실행 사용자** | appuser (non-root) | appuser (non-root) | nginx (non-root) |

---

## Dockerfile Best Practices 적용

| **원칙** | **적용 내용** |
| --- | --- |
| **캐시 최적화** | 의존성 파일 먼저 복사 → 소스 코드 나중에 복사 |
| **멀티스테이지 빌드** | 빌드 환경과 실행 환경 분리 (JDK/JRE, node/nginx) |
| **최소 이미지** | alpine, slim 기반 이미지 사용 |
| **RUN 통합** | 패키지 설치 + 캐시 정리를 하나의 RUN으로 |
| **비루트 사용자** | USER 명령어로 권한 없는 사용자로 전환 |
| **ENTRYPOINT vs CMD** | ENTRYPOINT로 고정 실행 파일, CMD로 기본 인자 |

---

## Dockerfile

### Spring Boot Backend

```docker
# ===========================================
# Stage 1: Build
# ===========================================
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# 1. 캐시 최적화: 의존성 파일 먼저 복사
COPY gradlew build.gradle settings.gradle ./
COPY gradle ./gradle

# 2. 의존성 다운로드 (캐시 활용)
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon

# 3. 소스 코드 복사 (자주 변경되는 부분)
COPY src ./src

# 4. 빌드
RUN ./gradlew bootJar --no-daemon

# ===========================================
# Stage 2: Runtime
# ===========================================
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# 5. 비루트 사용자 생성
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -D appuser

# 6. 빌드 결과물만 복사
COPY --from=builder /app/build/libs/*.jar app.jar

# 7. 권한 설정 및 사용자 전환
RUN chown appuser:appgroup app.jar
USER appuser

EXPOSE 8080

# 8. ENTRYPOINT + CMD 분리
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### FastAPI AI

```docker
# ===========================================
# Stage 1: Build (의존성 설치)
# ===========================================
FROM python:3.11-slim AS builder
WORKDIR /app

# 1. 캐시 최적화: requirements.txt 먼저 복사
COPY requirements.txt .

# 2. 의존성 설치 (virtualenv 사용)
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ===========================================
# Stage 2: Runtime
# ===========================================
FROM python:3.11-slim
WORKDIR /app

# 3. 비루트 사용자 생성
RUN groupadd -g 1001 appgroup && \
    useradd -u 1001 -g appgroup -m appuser

# 4. virtualenv 복사 (빌드 도구 제외)
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# 5. 소스 코드 복사
COPY --chown=appuser:appgroup . .

USER appuser

EXPOSE 8000

# 6. ENTRYPOINT + CMD 분리
ENTRYPOINT ["uvicorn", "main:app"]
CMD ["--host", "0.0.0.0", "--port", "8000"]
```

### Frontend (React + Vite)

```docker
# ===========================================
# Stage 1: Build
# ===========================================
FROM node:20-alpine AS builder
WORKDIR /app

# 1. 캐시 최적화: 의존성 파일 먼저 복사
COPY package.json package-lock.json ./

# 2. 의존성 설치 (캐시 활용)
RUN npm ci

# 3. 소스 코드 복사 (자주 변경되는 부분)
COPY . .

# 4. 빌드
RUN npm run build

# ===========================================
# Stage 2: Runtime (nginx)
# ===========================================
FROM nginx:alpine

# 5. 빌드 결과물만 복사 (node_modules, 소스 제외)
COPY --from=builder /app/dist /usr/share/nginx/html

# 6. nginx 설정 (선택)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

---

## .dockerignore 예시

### Spring Boot

```
# Git
.git
.gitignore

# Build
build/
.gradle/

# IDE
.idea/
*.iml

# Logs
*.log

# Secrets
.env
*.key
application-local.yml
```

### FastAPI

```
# Git
.git
.gitignore

# Python
__pycache__/
*.pyc
.venv/
venv/

# IDE
.idea/
.vscode/

# Secrets
.env
*.key
```

### Frontend (React + Vite)

```
# Git
.git
.gitignore

# Dependencies
node_modules/

# Build output
dist/

# Logs
*.log
npm-debug.log*

# IDE
.idea/
.vscode/

# Secrets
.env
.env.local
```

---

# 7. Docker Compose

## 환경별 구성 차이

| **항목** | **개발 (dev)** | **운영 (prod)** |
| --- | --- | --- |
| **목적** | 로컬 개발 환경 구성 | EC2 서버 배포 |
| **PostgreSQL** | 컨테이너 (편의성) | 호스트 설치 (external) |
| **Redis** | 컨테이너 (편의성) | 호스트 설치 (external) |
| **이미지 소스** | 로컬 빌드 (build context) | ECR Pull |
| **환경변수** | .env.dev 파일 | .env.prod 파일 |
| **네트워크** | Docker 내부 네트워크 | 호스트 네트워크 (host) |
| **재시작 정책** | no (수동) | unless-stopped (자동 복구) |

---

## 개발 환경 (docker-compose.dev.yml)

```yaml
services:
  # ===========================================
  # 애플리케이션 컨테이너
  # ===========================================
  spring-backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: tastecompass-backend-dev
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=dev
      - SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/tastecompass
      - SPRING_DATASOURCE_USERNAME=${DB_USERNAME}
      - SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD}
      - SPRING_REDIS_HOST=redis
      - SPRING_REDIS_PORT=6379
      - AI_SERVICE_URL=
```

---

## 운영 환경 (docker-compose.prod.yml)

```yaml
services:
  # ===========================================
  # 애플리케이션 컨테이너 (ECR에서 Pull)
  # ===========================================
  spring-backend:
    image: ${ECR_REGISTRY}/tastecompass/spring-backend:${IMAGE_TAG:-prod}
    container_name: tastecompass-backend
    ports:
      - "8080:8080"
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - SPRING_DATASOURCE_URL=jdbc:postgresql://${DB_HOST}:5432/tastecompass
      - SPRING_DATASOURCE_USERNAME=${DB_USERNAME}
      - SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD}
      - SPRING_REDIS_HOST=${REDIS_HOST}
      - SPRING_REDIS_PORT=6379
      - AI_SERVICE_URL=
```

---

## 환경변수 파일

### .env.dev (개발 환경)

```
# Database
DB_USERNAME=tastecompass
DB_PASSWORD=dev_password_change_me

# 개발 환경에서는 Docker 내부 네트워크 사용
```

### .env.prod (운영 환경)

```
# ECR
ECR_REGISTRY=
```

---

## 실행 명령어

### 개발 환경

```bash
# 시작
docker compose -f 
```

### 운영 환경

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 시작 (특정 태그로 배포)
IMAGE_TAG=sha-a1b2c3d docker compose -f 
```

---

## Docker Compose 요약

| **항목** | **개발 (dev)** | **운영 (prod)** |
| --- | --- | --- |
| **파일** | docker-compose.dev.yml | docker-compose.prod.yml |
| **환경변수** | .env.dev | .env.prod |
| **이미지** | 로컬 빌드 | ECR Pull (sha-xxxx) |
| **DB/Redis** | 컨테이너 | 호스트 (Private IP) |
| **재시작** | 수동 | unless-stopped |

---

# 8. 배포 절차

## 기존 수작업 배포 vs Docker 배포 비교

| **단계** | **기존 수작업 배포** | **소요 시간** | **Docker 배포** | **소요 시간** |
| --- | --- | --- | --- | --- |
| **1. 코드 Pull** | git pull origin main | 10~30초 | docker pull (ECR) | 5~10초 |
| **2. 빌드** | ./gradlew bootJar | 3~5분 | 생략 (CI에서 완료) | 0초 |
| **3. 애플리케이션 중지** | kill 프로세스 또는 systemctl stop | 5~10초 | docker stop (graceful) | 5~10초 |
| **4. 애플리케이션 시작** | nohup java -jar app.jar & | 30~60초 | docker run / compose up | 10~20초 |

---

## Docker 배포 플로우

```
1. CI (GitHub Actions)
   │
   ├── 코드 Push (main branch)
   │
   ├── 테스트 실행
   │
   ├── Docker 이미지 빌드
   │
   ├── ECR Push (sha-xxxxxxx 태그)
   │
   └── 배포 트리거 (CD)

2. CD (배포 서버)
   │
   ├── ECR 로그인
   │
   ├── 이미지 Pull
   │
   ├── 기존 컨테이너 중지 (graceful shutdown)
   │
   ├── 새 컨테이너 시작
   │
   ├── 헬스체크 확인
   │
   └── 배포 완료
```