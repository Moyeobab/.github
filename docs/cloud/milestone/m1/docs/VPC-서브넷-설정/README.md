# VPC 네트워크 설정 (Big Bang 배포 기준)

이 문서는 Big Bang(컨테이너 미사용) 배포를 위한 수동(AWS 콘솔) VPC 구성 절차입니다.
프로젝트 기준값에 맞춰 동일한 네트워크 구성을 수동으로 재현하는 것을 목표로 합니다.

## 기준값

- 리전: `ap-northeast-2` (Seoul)
- VPC 이름: `moyeoBab`
- VPC CIDR: `10.0.0.0/16`
- 가용 영역: `ap-northeast-2a`
- 서브넷 CIDR: `10.0.0.0/24` (`moyeoBab-subnet-1`)
- 인터넷 게이트웨이: `moyeoBab-igw`
- 라우팅 테이블: `moyeoBab-rt`
- 라우트: `0.0.0.0/0` → `moyeoBab-igw`
- 퍼블릭 IPv4 자동 할당: `활성화`
- 태그:
  - `Environment=dev`
  - `Project=moyeoBab`

## 1. VPC 생성

1. AWS 콘솔에서 VPC 생성:
   - 이름: `moyeoBab`
   - IPv4 CIDR: `10.0.0.0/16`
   - 태그: `Environment=dev`, `Project=moyeoBab`

## 2. 서브넷 생성

1. 서브넷 생성:
   - VPC: `moyeoBab`
   - 이름: `moyeoBab-subnet-1`
   - AZ: `ap-northeast-2a`
   - CIDR: `10.0.0.0/24`
   - 퍼블릭 IPv4 자동 할당: `활성화`
   - 태그: `Environment=dev`, `Project=moyeoBab`

## 3. 인터넷 게이트웨이(IGW) 생성 및 연결

1. 인터넷 게이트웨이 생성:
   - 이름: `moyeoBab-igw`
   - 태그: `Environment=dev`, `Project=moyeoBab`
2. VPC에 연결:
   - 대상 VPC: `moyeoBab`

## 4. 라우팅 테이블 생성 및 연결

1. 라우팅 테이블 생성:
   - 이름: `moyeoBab-rt`
   - VPC: `moyeoBab`
   - 태그: `Environment=dev`, `Project=moyeoBab`
2. 라우트 추가:
   - `0.0.0.0/0` → `moyeoBab-igw`
3. 서브넷 연결:
   - `moyeoBab-subnet-1`을 `moyeoBab-rt`에 연결

## 5. 검증 체크리스트

- VPC CIDR이 `10.0.0.0/16`으로 설정됨
- 서브넷이 `ap-northeast-2a`에 생성되고 CIDR이 `10.0.0.0/24`임
- IGW가 VPC에 연결되어 있음
- 라우팅 테이블에 `0.0.0.0/0 → IGW` 라우트가 있음
- 서브넷이 라우팅 테이블에 연결되어 있음
- 서브넷의 퍼블릭 IPv4 자동 할당이 활성화됨