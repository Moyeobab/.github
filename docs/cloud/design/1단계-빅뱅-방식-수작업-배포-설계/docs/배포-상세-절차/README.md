# 참고 문서: 배포 상세 절차

> 이 문서는 1단계 수작업 배포의 상세 절차, 체크리스트, 롤백 절차를 담고 있습니다.
> 본문([README.md](../../../../Cloud-Wiki.md))에서는 핵심 배포 절차만 요약하고, 상세 내용은 이 문서를 참고하세요.

---

## A. 배포 개요

| 항목                      | 내용                             |
| ------------------------- | -------------------------------- |
| **배포 방식**             | Big Bang - 전체 시스템 일괄 교체 |
| **배포 주기**             | 주 1회 이하                      |
| **예상 배포 소요 시간**   | 약 38분                          |
| **예상 서비스 중단 시간** | 약 8분                           |
| **배포 담당자**           | DevOps 담당자 2명                |
| **배포 수행 시간대**      | 매주 수요일 02:00~03:00 AM       |

---

## B. 배포 전 준비사항 체크리스트

### B.1 코드 준비

- [ ] 배포할 코드의 Git 브랜치/커밋 확인
- [ ] 코드 리뷰 완료 여부 확인
- [ ] main 브랜치에 병합 완료

### B.2 빌드 검증

- [ ] Backend 로컬 빌드 성공 확인
  ```bash
  ./gradlew clean build -x test
  ```
- [ ] Frontend 로컬 빌드 성공 확인
  ```bash
  npm install && npm run build
  ```

### B.3 데이터베이스 준비

- [ ] DB 스키마 변경 여부 확인
- [ ] 변경 시 마이그레이션 SQL 파일 준비 완료
- [ ] 마이그레이션 SQL 로컬 검증 완료

### B.4 백업 준비

- [ ] 기존 파일 백업 위치 확인 (`/app/backup/`)
- [ ] 백업 디스크 용량 확인

### B.5 커뮤니케이션

- [ ] 서비스 공지 문구 작성 완료
- [ ] 배포 담당자 연락처 확인
- [ ] 긴급 롤백 의사결정자 확인

---

## C. 롤백 절차

배포 실패 시 이전 버전으로 되돌리는 절차입니다.

### C.1 롤백 절차 상세

| 단계 | 작업 내용            | 담당자 | 사용 도구/명령어                                                   | 예상 소요 시간 | 비고              |
| ---- | -------------------- | ------ | ------------------------------------------------------------------ | -------------- | ----------------- |
| 1    | Backend 서비스 중단  | DevOps | `sudo systemctl stop spring-boot`                                  | 1분            | **다운타임 시작** |
| 2    | Frontend 서비스 중단 | DevOps | `pm2 stop nextjs`                                                  | 1분            |                   |
| 3    | Backend 백업본 복원  | DevOps | `cp /app/backup/app.jar.bak /app/backend/app.jar`                  | 1분            |                   |
| 4    | Frontend 백업본 복원 | DevOps | `cp -r /app/backup/.next.bak /app/frontend/.next`                  | 1분            |                   |
| 5    | DB 데이터 복원       | DevOps | `psql -U postgres -d {db_name} < backup_YYYYMMDD.sql`              | 3분            | 스키마 변경 시    |
| 6    | Backend 서비스 시작  | DevOps | `sudo systemctl start spring-boot`                                 | 1분            |                   |
| 7    | Frontend 서비스 시작 | DevOps | `pm2 start nextjs`                                                 | 1분            | **다운타임 종료** |
| 8    | 정상 동작 확인       | DevOps | `curl http://localhost:8080/health` / `curl http://localhost:3000` | 2분            |                   |

**예상 총 롤백 소요 시간:** 약 11분
**예상 서비스 중단 시간 (다운타임):** 약 9분 (1단계~7단계)

### C.2 배포 전 백업 명령어

배포 전 반드시 기존 파일을 백업해야 합니다.

```bash
# 백업 디렉토리 생성
mkdir -p /app/backup

# Backend jar 백업
cp /app/backend/app.jar /app/backup/app.jar.bak

# Frontend 빌드 결과 백업
cp -r /app/frontend/.next /app/backup/.next.bak

# 데이터베이스 백업
pg_dump -U postgres -d {db_name} > /app/backup/db_backup_$(date +%Y%m%d_%H%M%S).sql
```

### C.3 롤백 판단 기준

다음 상황 중 하나라도 발생하면 즉시 롤백을 진행합니다:

1. Health Check 3회 연속 실패
2. 에러 로그에서 Critical/Fatal 에러 발생
3. 주요 기능(로그인, 메인 페이지) 동작 불가
4. 배포 후 5분 내 사용자 장애 신고 접수

---

## D. GPU 서버 배포 (RunPod Serverless)

GPU 서버는 EC2와 별도로 RunPod Serverless에서 운영되며, 독립적으로 배포 가능합니다.

### D.1 배포 특징

- EC2와 독립적으로 배포 가능
- Endpoint URL을 환경변수로 관리하는 경우 변경 시 Backend 재시작 필요
- Backend 재시작 시 약 1~2분간 서비스 중단 발생

### D.2 배포 절차

1. RunPod 콘솔에서 새 Endpoint 생성 또는 기존 Endpoint 업데이트
2. 새 Endpoint URL 확인
3. Backend 환경변수 업데이트 (필요 시)
4. Backend 재시작 (환경변수 변경 시)

> 상세 배포 절차는 [참고: RunPod 배포 방식 상세](../RunPod-배포-방식/README.md) 참고

---

## E. Nginx 설정 변경

Nginx 설정 변경이 필요한 경우 (config 변경 시에만) 다음 절차를 따릅니다.

```bash
# 설정 문법 검사
sudo nginx -t

# 무중단 설정 반영
sudo nginx -s reload
```

> **참고:** Nginx는 리버스 프록시 역할만 수행하므로 일반 코드 배포 시에는 재시작 불필요

---

## F. 배포 후 검증 체크리스트

### F.1 시스템 검증

- [ ] Backend Health Check 통과 (`curl http://localhost:8080/health`)
- [ ] Frontend Health Check 통과 (`curl http://localhost:3000`)
- [ ] 프로세스 상태 확인 (`systemctl status spring-boot`, `pm2 status`)

### F.2 기능 검증

- [ ] 로그인/회원가입 정상 동작
- [ ] 메인 페이지 정상 로드
- [ ] API 응답 정상 (주요 엔드포인트 테스트)
- [ ] AI 기능 정상 동작 (RunPod 연동 확인)

### F.3 로그 검증

- [ ] Backend 에러 로그 없음 (`tail -f /app/backend/logs/app.log`)
- [ ] Frontend 에러 로그 없음 (`pm2 logs nextjs`)
- [ ] Nginx 에러 로그 없음 (`tail -f /var/log/nginx/error.log`)

### F.4 모니터링 (배포 후 10분)

- [ ] CPU/메모리 사용량 정상 범위
- [ ] 응답 시간 정상 범위
- [ ] 에러율 0% 유지

---

## 참고 링크

- [PM2 공식 문서](https://pm2.keymetrics.io/docs/)
- [Systemd 서비스 관리](https://www.freedesktop.org/software/systemd/man/systemctl.html)
- [PostgreSQL pg_dump 문서](https://www.postgresql.org/docs/current/app-pgdump.html)
