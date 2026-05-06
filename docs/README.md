# 모여밥 문서 허브

## 카테고리

- [🤖 AI](./ai/)
- [☁️ Cloud](./cloud/)
- [🔧 Backend](./backend/)
- [🎨 Frontend](./frontend/)
- [🎯 Planning](./planning/)

---

## 🤖 AI

- [1단계: 모델 API 설계](./ai/API.md)
- [2단계: 모델 추론 성능 최적화](./ai/Optimization.md)
- [3단계: 서비스 아키텍처 모듈화](./ai/AI_Architecture.md)
- [4단계: 멀티스텝 AI/파이프라인 구현 검토](./ai/Pipeline.md)
- [5단계: 데이터/컨텍스트 보강 설계](./ai/data.md)
- [6단계: 표준화된 도구 통합 및 외부 API 활용 설계](./ai/MCP.md)

## ☁️ Cloud

- [Cloud Wiki (인덱스)](./cloud/Cloud-Wiki.md)

### 단계별 설계

- [1단계: Big Bang 방식 수작업 배포 설계](./cloud/design/1단계-빅뱅-방식-수작업-배포-설계/README.md)
- [2단계: CI 파이프라인 구축 설계](./cloud/design/2단계-CI-자동화-설계/README.md)
- [3단계: CD 파이프라인 구축 설계](./cloud/design/3단계-CD-자동화-설계/README.md)
- [4단계: Docker 컨테이너화 배포](./cloud/design/4단계-Docker-컨테이너화-설계/README.md)

### 마일스톤

- [M1 - 빅뱅 배포 구현](./cloud/milestone/m1/)
- [M2 - CI/CD 파이프라인](./cloud/milestone/m2/)
- [M3 - IaC (Terraform)](./cloud/milestone/m3/)
- [M4 - SLI/SLO 설계](./cloud/milestone/m4/)
- [M5 - 장애 알림 시스템](./cloud/milestone/m5/)
- [M6 - 부하 테스트](./cloud/milestone/m6/)

### 마이그레이션

- [Infra Migration 계획](./cloud/Infra-Migration-계획.md)
- [인프라 마이그레이션 계획](./cloud/인프라-마이그래이션-계획.md)
- [데이터베이스 마이그레이션 계획](./cloud/데이터베이스-마이그레이션-계획.md)
- [v3 Kubernetes 설계 문서](./cloud/v3-Kubernetes-설계-문서.md)
- [DB 접근 보호 방식](./cloud/DB-접근-보호-방식.md)
- [운영환경 트래픽 이관](./cloud/운영환경-트래픽-이관.md)

### 장애 대응 / 카오스 엔지니어링

- [정상 상태 기준선(Steady State) 정의](./cloud/정상-상태-기준선(Steady-State)-정의.md)
- [장애 감지 기준 정의](./cloud/장애-감지-기준-정의-(어떤-상황을-장애로-볼-것인가).md)
- [장애 알림 시스템 설계 및 구축](./cloud/장애-알림-시스템-설계-및-구축.md)
- [장애 대응 프로세스 정리](./cloud/장애-대응-프로세스-정리.md)
- [Application Fault Injection 시나리오](./cloud/Application-Fault-Injection-시나리오.md)
- [Infra Fault Injection 시나리오](./cloud/Infra-Fault-Injection-시나리오.md)
  - [Redis Sentinel 마스터 다운](./cloud/Redis-Sentinel-마스터-다운-시나리오.md)
  - [PostgreSQL Primary EC2 종료](./cloud/PostgreSQL-Primary-EC2-종료-시나리오.md)
  - [Backend → PostgreSQL 네트워크 지연 주입](./cloud/Backend-네트워크-지연-주입.md)
  - [Backend ASG 인스턴스 50% 종료](./cloud/Backend-ASG-인스턴스-50%25-종료.md)
  - [ap-northeast-2a AZ 격리](./cloud/AZ-격리.md)

### 부하/E2E 테스트

- [부하테스트 도구 선정](./cloud/부하테스트-도구-선정.md)
- [부하테스트 시나리오](./cloud/부하테스트-시나리오.md)
- [부하테스트 결과 분석](./cloud/부하테스트-결과-분석.md)
- [E2E 테스트 도구 조사 및 선정](./cloud/E2E-테스트-도구-조사-및-선정.md)
- [E2E 테스트 환경 구성](./cloud/E2E-테스트-환경-구성.md)
- [E2E 테스트 시나리오 설계](./cloud/E2E-테스트-시나리오-설계.md)

### 수동 롤백

- [수동 롤백 시나리오](./cloud/수동-롤백-시나리오.md)
- [수동 롤백 스크립트](./cloud/수동-롤백-스크립트.md)
- [수동 롤백 테스트 수행 및 검증](./cloud/수동-롤백-테스트-수행-및-검증.md)

## 🔧 Backend

- [Backend Wiki](./backend/Backend-Wiki.md)
- [CheckStyle 중단 해결](./backend/checkstyle-중단-해결.md)
- [SpotBugs 설정 완화](./backend/spotbugs-설정완화.md)

## 🎨 Frontend

- [Frontend Wiki](./frontend/Frontend-Wiki.md)

## 🎯 Planning

- [Vision](./planning/Vision.md)
- [Roadmap](./planning/Roadmap.md)
- [Product Backlog](./planning/Product‐Backlog.md)
- [Product Backlog Template](./planning/Product‐Backlog‐Template.md)
- [Release Planning](./planning/Release‐Planning.md)
- [Sprint Planning Template](./planning/Sprint‐Planing‐Template.md)
- [Sprint Backlog Template](./planning/Sprint‐Backlog‐Template.md)
- [Daily Scrum Template](./planning/Daily‐Scrum‐Template.md)
- [Sprint Review Template](./planning/Review‐Template.md)
- [Retrospective Template](./planning/Retrospective‐Template.md)
