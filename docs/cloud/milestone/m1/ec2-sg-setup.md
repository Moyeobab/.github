# EC2 인스턴스 생성 및 보안 그룹 설정 (Big Bang 배포 기준)

이 문서는 Big Bang(컨테이너 미사용) 배포를 위한 수동(AWS 콘솔) 절차를 정리합니다.
프로젝트 기준값에 맞춰 동일한 구성을 수동으로 재현하는 것을 목표로 합니다.

## 기준값

### EC2/보안 그룹

- 운영체제: `Ubuntu Server 24.04 LTS`
- 인스턴스 타입: `t4g.small`
- 루트 볼륨: `50 GiB`, `gp3`
- 보안 그룹 인바운드:
  - SSH `TCP 22` (CIDR: `0.0.0.0/0`)
  - HTTP `TCP 80` (CIDR: `0.0.0.0/0`)
  - HTTPS `TCP 443` (CIDR: `0.0.0.0/0`)
- 보안 그룹 아웃바운드: 전체 허용 (`0.0.0.0/0`)

### EIP

- EIP 이름: `moyeoBab-app-eip`

## 1. 보안 그룹 생성 (EC2용)

1. 보안 그룹 생성:
   - 이름: `moyeoBab-app-sg`
   - VPC: `moyeoBab`
   - 설명: `Allow SSH/HTTP/HTTPS`
   - 태그: `Environment=dev`, `Project=moyeoBab`
2. 인바운드 규칙 추가:
   - SSH: `TCP 22`, 소스 `0.0.0.0/0`
   - HTTP: `TCP 80`, 소스 `0.0.0.0/0`
   - HTTPS: `TCP 443`, 소스 `0.0.0.0/0`
3. 아웃바운드 규칙:
   - 기본값(전체 허용, `0.0.0.0/0`) 유지

## 2. EC2 인스턴스 생성

1. 인스턴스 생성:
   - 운영체제: `Ubuntu Server 24.04 LTS`
   - 타입: `t4g.small`
   - VPC: `moyeoBab`
   - 서브넷: `moyeoBab-subnet-1`
   - 퍼블릭 IP 자동 할당: `활성화`
   - 보안 그룹: `moyeoBab-app-sg`
2. 스토리지 설정:
   - 루트 볼륨: `50 GiB`, `gp3`
3. 태그:
   - `Name=moyeoBab-app`
   - `Environment=dev`
   - `Project=moyeoBab`

## 3. EIP (선택)

1. Elastic IP 할당:
   - EIP 생성(도메인: VPC)
   - 태그: `Name=moyeoBab-app-eip`, `Environment=dev`, `Project=moyeoBab`
2. EIP 연결:
   - 생성한 EIP를 EC2 인스턴스에 연결

## 4. 검증 체크리스트

- 보안 그룹 인바운드 규칙이 기준값과 동일함
- 인스턴스가 `moyeoBab-subnet-1`에 배치됨
- EIP 연결 후 고정 퍼블릭 IP로 접속 가능