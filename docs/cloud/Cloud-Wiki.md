# MoyeoBab Cloud Wiki

## 목차

- [단계별 확장 로드맵](#단계별-확장-로드맵)
- [마일스톤](#마일스톤)

## 단계별 확장 로드맵

### [1단계: Big Bang 방식 수작업 배포 설계](./design/1단계-빅뱅-방식-수작업-배포-설계/README.md)

### [2단계: CI(지속적 통합) 파이프라인 구축 설계](./design/2단계-CI-자동화-설계/README.md)

### [3단계: CD(지속적 배포) 파이프라인 구축 설계](./design/3단계-CD-자동화-설계/README.md)

### [4단계: Docker 컨테이너화 배포](./design/stage-4-container.md)

## 마일스톤

### [M1] 빅뱅 배포 구현 (VM 환경 기반 구축)

**목표:** VM(가상머신) 환경에서 애플리케이션을 수동으로 배포하고 실행하는 초기 배포 구조를 구현합니다. 서버 프로비저닝부터 애플리케이션 실행까지 전체 배포 흐름을 경험하고 문서화합니다.

- [VPC 및 서브넷 설정](./milestone/m1/vpc-subnet-setup.md)

- [EC2 인스턴스 생성 및 보안 그룹 설정](./milestone/m1/ec2-sg-setup.md)

- [애플리케이션 의존성 설치 및 환경 구성](./milestone/m1/app-dependency-env.md)

- [애플리케이션 정상 실행 및 접속 확인](./milestone/m1/app-execution-check.md)

- [DB 접근 보호 방법 조사](./DB-접근-보호-방식.md)


### [M2] 빅뱅 배포용 CI/CD 파이프라인 구현

**목표:** 빅뱅 배포를 자동화하기 위한 기본 CI/CD 파이프라인을 구현합니다. 코드 푸시 시 자동 빌드, 테스트, 배포가 이루어지는 기본 자동화 흐름을 구축합니다.

<!-- 
- [FE 빌드 및 테스트 자동화 파이프라인 구현](./milestone/m2/fe-ci-pipeline.md) 
-->

- [BE 빌드 및 테스트 자동화 파이프라인 구현](./milestone/m2/be-ci-pipeline.md)

<!-- 
- [VM 환경으로 자동 배포 스크립트 작성](./milestone/m2/vm-deploy-script.md)
-->

<!-- 
- [파이프라인 정상 동작 검증](./milestone/m2/pipeline-verification.md)
-->


- [CheckStyle 중단 해결](../backend/checkstyle-중단-해결.md)

- [SpotBugs 설정 완화](../backend/spotbugs-설정완화.md)

### [M3] IaC를 활용한 인프라 변환 (Terraform)

**목표:** 수동으로 생성한 인프라(VPC, EC2, Security Group)를 IaC(Infrastructure as Code)를 활용하여 코드로 변환합니다. 인프라의 버전 관리 및 재현 가능한 환경 구성을 목표로 합니다.

- [IaC 도구 선정 문서화](./milestone/m3/iac-tool-selection.md)

<!--
- [VPC 및 서브넷 구성 코드화](./milestone/m3/vpc-subnet-iac.md)
-->

<!-- 
- [EC2 인스턴스 프로비저닝 코드화](./milestone/m3/ec2-provision-iac.md)
-->

<!-- 
- [Security Group 규칙 코드화](./milestone/m3/sg-rules-iac.md)
-->

<!-- 
- [IaC 코드로 인프라 생성/삭제 테스트](./milestone/m3/iac-test.md)
-->

- [dev-core 환경 구성 (EIP, DB EBS 볼륨 분리 관리)](./milestone/m3/dev-core-env.md)

- [EC2 모듈에 EBS 볼륨 연결 기능 추가](./milestone/m3/ec2-ebs-attach.md)

- [Terraform 백엔드 설정](./milestone/m3/terraform-backend.md)

### [M4] SLI/SLO 설계 문서화 및 CD 검증

**목표:** 서비스 안정성 측정을 위한 SLI(Service Level Indicator)와 SLO(Service Level Objective)를 설계하고 문서화합니다.

- [우리 서비스에 적합한 SLI 지표 선정](./milestone/m4/sli-indicator-selection.md)

- [SLO 목표값 설정 및 근거 문서화](./milestone/m4/slo-target-setting.md)

### [M5] 수동 롤백 프로세스 정립 및 장애 알림 시스템 구축

**목표:** 배포 실패 또는 장애 상황에서 빠르게 이전 버전으로 복구할 수 있는 수동 롤백 프로세스를 정립하고, 장애 발생 시 팀에게 알림을 전달하는 시스템을 구축합니다.

- [장애 감지 기준 정의 (어떤 상황을 장애로 볼 것인가)](./장애-감지-기준-정의-(어떤-상황을-장애로-볼-것인가).md)

- [장애 알림 시스템 설계 및 구축](./장애-알림-시스템-설계-및-구축.md)

- [수동 롤백 시나리오](./수동-롤백-시나리오.md)

- [수동 롤백 스크립트](./수동-롤백-스크립트.md)

- [수동 롤백 테스트 수행 및 검증](./수동-롤백-테스트-수행-및-검증.md)

- [장애 대응 프로세스 정리](./장애-대응-프로세스-정리.md)

### [M6] 부하 테스트 시나리오 설계, 구현 및 문서화

**목표:** 서비스의 성능 한계와 병목 지점을 파악하기 위한 부하 테스트 시나리오를 설계하고 구현합니다.

- [부하테스트 도구 선정](./부하테스트-도구-선정.md)

- [부하테스트 시나리오](./부하테스트-시나리오.md)

- [부하테스트 결과 분석](./부하테스트-결과-분석.md)

### [M7] E2E 테스트 시나리오 설계 (Tool 선정 ~ 시나리오 구현) 및 문서화

**목표:** 실제 사용자 관점에서 서비스의 전체 흐름이 끊김 없이 정상 작동하는지 검증하여, 배포 전 기능의 무결성과 서비스 신뢰성을 확보합니다.

- [E2E 테스트 도구 조사 및 선정](./E2E-테스트-도구-조사-및-선정.md)

- [E2E 테스트 환경 구성](./E2E-테스트-환경-구성.md)

- [E2E 테스트 시나리오 설계](./E2E-테스트-시나리오-설계.md)


### [M8] 1차 배포 완료: 오픈 후 이슈 리포트, 병목 지점 파악, 비용 예측 리포트


### [M9] 도커 기반 배포 구조 전환 (3-Tier VPC, 다중 인스턴스 환경 등)

**목표:** 서비스 무중단을 보장하며, 보안과 확장성을 갖춘 고가용성 3-Tier 도커 인프라로의 안정적인 아키텍처 전환

- [인프라 마이그레이션 계획](./인프라-마이그래이션-계획.md)

- [ALB 기반 카나리 배포를 통한 운영환경 트래픽 이관 보고서](./운영환경-트래픽-이관.md)


### [M10] 도커 기반 CI/CD 파이프라인 재설계 및 구현

**목표:** 환경 격리와 일관성이 보장된 컨테이너 표준을 통해, 다중 인스턴스 환경으로의 신속하고 결함 없는 자동화된 배포 체계 확립


### [M11] IaC 업데이트 (도커 환경 반영) 및 문서화

**목표:** 인프라 코드화를 통한 환경 재현성 및 운영 정합성 확보와, 효율적인 관리 및 협업을 위한 인프라 기술 자산의 명세화


### [M12] MLOps 설계 및 구축 (S3 기반 파이프라인, CI/CD 연동 등)

**목표:** S3 중심의 데이터 및 모델 관리 체계와 CI/CD 파이프라인을 결합하여, ML 모델의 실험부터 운영 배포까지의 전 생애주기를 자동화하고 예측 서비스의 품질 일관성을 확보함



## 트러블슈팅

- [대규모 트래픽 유입 장애 (2026-02-02)](https://www.notion.so/gguip/2fc853be490b80089c89c0afcb6e052a?source=copy_link)

## 쿠버네티스 설계 문서

- [쿠버네티스 설계 문서](https://github.com/100-hours-a-week/13-team-project-cloud/blob/main/docs/kubernetes/K8S-001-final-design.md)

## 장애대응

- [정상 상태 기준선(Steady State) 정의](./정상-상태-기준선(Steady-State)-정의.md)
- [Application Fault Injection 시나리오](./Application-Fault-Injection-시나리오.md)
- [Infra Fault Injection 시나리오](./Infra-Fault-Injection-시나리오.md)
    - [Redis Sentinel 마스터 다운](./Redis-Sentinel-마스터-다운-시나리오.md)
    - [PostgreSQL Primary EC2 종료](./PostgreSQL-Primary-EC2-종료-시나리오.md)
    - [Backend → PostgreSQL 네트워크 지연 주입](./Backend-네트워크-지연-주입.md)
    - [Backend ASG 인스턴스 50% 종료](./Backend-ASG-인스턴스-50%25-종료.md)
    - [ap-northeast-2a AZ 격리](./AZ-격리.md)
