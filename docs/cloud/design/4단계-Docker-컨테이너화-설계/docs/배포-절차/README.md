# 배포 절차

## 기존 수작업 배포 vs Docker 배포 비교

| **단계** | **기존 수작업 배포** | **소요 시간** | **Docker 배포** | **소요 시간** |
| --- | --- | --- | --- | --- |
| **1. 코드 Pull** | git pull origin main | 10-30초 | docker pull (ECR) | 5-10초 |
| **2. 빌드** | ./gradlew bootJar | 3-5분 | 생략 (CI에서 완료) | 0초 |
| **3. 애플리케이션 중지** | kill 프로세스 또는 systemctl stop | 5-10초 | docker stop (graceful) | 5-10초 |
| **4. 애플리케이션 시작** | nohup java -jar app.jar & | 30-60초 | docker run / compose up | 10-20초 |

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
