# CI 설정 명세서

## 1. 워크플로우 트리거 설정

```yaml
name: CI Pipeline

on:
  pull_request:
    branches:
      - develop
      - main
    types:
      - opened
      - synchronize

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| 트리거 이벤트 | `pull_request` | PR 생성 및 업데이트 시 실행 |
| 대상 브랜치 | `develop`, `main` | 해당 브랜치로의 PR만 CI 실행 |
| 트리거 타입 | `opened`, `synchronize` | PR 생성 시, 새 커밋 푸시 시 |

---

## 2. Lint 설정 - stage 1

### Backend (Checkstyle)

```yaml
- name: Run Checkstyle
  run: ./gradlew checkstyleMain checkstyleTest

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| 실행 명령 | `./gradlew checkstyleMain checkstyleTest` | 메인/테스트 코드 스타일 검사 |
| 설정 파일 | `config/checkstyle/checkstyle.xml` | 팀 코딩 컨벤션 정의 |
| 실패 조건 | 스타일 위반 발견 시 | 빌드 실패 처리 |

### Frontend (ESLint)

```yaml
- name: Run ESLint
  run: npm run lint

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| 실행 명령 | `npm run lint` | ESLint 실행 |
| 설정 파일 | `eslint.config.js` | React, TypeScript 규칙 정의 |
| 실패 조건 | error 레벨 위반 시 | 빌드 실패 처리 |

---

## 3. Build 설정 - stage 2

### Backend

```yaml
- name: Setup Java
  uses: actions/setup-java@v4
  with:
    java-version: '17'
    distribution: 'temurin'

- name: Cache Gradle
  uses: actions/cache@v4
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
    key: gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}

- name: Build Backend
  run: ./gradlew compileJava compileTestJava

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| Java 버전 | 17 | LTS 버전 사용 |
| 캐시 대상 | Gradle caches, wrapper | 빌드 속도 향상 |
| 실행 명령 | `./gradlew compileJava compileTestJava` | 메인/테스트 코드 컴파일 |

### Frontend

```yaml
- name: Setup Node
  uses: actions/setup-node@v4
  with:
    node-version: '20'
    cache: 'npm'

- name: Install Dependencies
  run: npm ci

- name: Build Frontend
  run: npm run build

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| Node 버전 | 20 | LTS 버전 사용 |
| 캐시 대상 | npm | 의존성 설치 속도 향상 |
| 실행 명령 | `npm run build` | TypeScript 컴파일 + Vite 빌드 |

---

## 4. Static Analysis (SpotBugs) 설정 - stage 3

```yaml
- name: Run SpotBugs
  run: ./gradlew spotbugsMain

```

### build.gradle 설정

```groovy
plugins {
    id 'com.github.spotbugs' version '6.0.0'
}

spotbugs {
    toolVersion = '4.8.0'
    excludeFilter = file('config/spotbugs/exclude.xml')
}

spotbugsMain {
    reports {
        html.required = true
        xml.required = true
    }
}

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| 실행 명령 | `./gradlew spotbugsMain` | 메인 코드 버그 패턴 분석 |
| 리포트 형식 | HTML, XML | 리뷰어 확인용, CI 파싱용 |
| 실패 조건 | High 심각도 발견 시 | 빌드 실패 처리 |

### SpotBugs 실패 기준

| 심각도 | 카테고리 | 처리 |
| --- | --- | --- |
| High | Null 참조, 리소스 누수 | 즉시 빌드 실패 |
| High | 동시성 문제 | 즉시 빌드 실패 |
| Medium | 비효율 코드 | 일정 개수 초과 시 빌드 실패 |

---

## 5. Test 설정 - stage 4

### Backend

```yaml
- name: Run Tests
  run: ./gradlew test

- name: Verify Coverage
  run: ./gradlew jacocoTestCoverageVerification

```

### build.gradle 커버리지 설정

```groovy
jacocoTestCoverageVerification {
    violationRules {
        rule {
            element = 'PACKAGE'

            includes = [
                'com.app.service.filter.*',
                'com.app.service.settlement.*',
                'com.app.domain.*'
            ]

            limit {
                counter = 'LINE'
                minimum = 0.80
            }
        }
    }
}

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| 테스트 명령 | `./gradlew test` | 단위 + 통합 테스트 실행 |
| 커버리지 검증 | `jacocoTestCoverageVerification` | 핵심 패키지 임계값 검증 |
| 측정 대상 | `service.filter`, `service.settlement`, `domain` | 핵심 비즈니스 로직 패키지 |
| 최소 커버리지 | 80% | 실패 시 타격이 큰 핵심 로직만 설정 |

### Frontend

```yaml
- name: Run Tests
  run: npm run test -- --coverage

```

### vitest.config.ts 설정

```tsx
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      include: [
        'src/hooks/**',
        'src/utils/**',
        'src/services/**'
      ],
      exclude: [
        'src/components/ui/**',
        'src/**/*.d.ts'
      ],
      thresholds: {
        'src/hooks/**': { lines: 80 },
        'src/services/**': { lines: 80 }
      }
    }
  }
})

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| 테스트 명령 | `npm run test -- --coverage` | 테스트 + 커버리지 측정 |
| 측정 대상 | `hooks`, `utils`, `services` | 핵심 로직 디렉토리 |
| 측정 제외 | `components/ui`, `.d.ts` | UI 컴포넌트, 타입 정의 제외 |
| 최소 커버리지 | 80% | 핵심 디렉토리만 높은 기준 적용 |

---

## 6. Artifact 설정 - stage 5

```yaml
- name: Upload Test Results
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: test-results
    path: |
      build/reports/tests/
      coverage/
    retention-days: 30

- name: Upload Coverage Report
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: coverage-report
    path: |
      build/reports/jacoco/
      coverage/lcov-report/
    retention-days: 30

- name: Upload Analysis Report
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: analysis-report
    path: |
      build/reports/checkstyle/
      build/reports/spotbugs/
    retention-days: 30

- name: Upload Build Artifact (JAR)
  uses: actions/upload-artifact@v4
  if: success()
  with:
    name: executable-jar
    path: build/libs/*.jar
    retention-days: 30

```

| 항목 | 설정값 | 설명 |
| --- | --- | --- |
| 업로드 조건 | `if: always()` | 테스트 실패해도 리포트 업로드 |
| 보관 기간 | 30일 | 2개 버전 주기(4주) 내 참조 가능 |
| 저장소 | GitHub Actions Artifact | 별도 설정 없이 즉시 사용 |

---

## 7. 전체 워크플로우 구조

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      # Checkstyle, ESLint 실행

  build:
    needs: lint
    runs-on: ubuntu-latest
    steps:
      # Backend 컴파일, Frontend 빌드

  analysis:
    needs: build
    runs-on: ubuntu-latest
    steps:
      # SpotBugs 실행

  test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      # 단위/통합 테스트, 커버리지 검증

  artifact:
    needs: [analysis, test]
    runs-on: ubuntu-latest
    if: always()
    steps:
      # 리포트 업로드

```

| 단계 | 의존 관계 | 실패 시 동작 |
| --- | --- | --- |
| Lint | 없음 | 후속 단계 중단 |
| Build | Lint 성공 | 후속 단계 중단 |
| Analysis | Build 성공 | Artifact 단계는 실행 |
| Test | Build 성공 | Artifact 단계는 실행 |
| Artifact | Analysis, Test 완료 | 항상 실행 (리포트 보존) |

---

## 8. 환경 변수 및 시크릿

### 환경 변수

워크플로우 내에서 직접 정의하는 값들입니다.

```yaml
env:
  JAVA_VERSION: '17'
  NODE_VERSION: '20'
  GRADLE_OPTS: '-Dorg.gradle.daemon=false -Xmx2g'

  # 애플리케이션 설정
  SPRING_PROFILES_ACTIVE: 'test'
  APP_PORT: '8080'

  # 테스트 DB 설정
  TEST_DB_URL: 'jdbc:h2:mem:testdb'
  TEST_DB_USERNAME: 'sa'

```

| 변수명 | 값 | 용도 |
| --- | --- | --- |
| `JAVA_VERSION` | 17 | Java 버전 지정 |
| `NODE_VERSION` | 20 | Node 버전 지정 |
| `GRADLE_OPTS` | `-Dorg.gradle.daemon=false -Xmx2g` | Gradle 메모리 설정 |
| `SPRING_PROFILES_ACTIVE` | test | 테스트 프로파일 활성화 |
| `APP_PORT` | 8080 | 애플리케이션 포트 |
| `TEST_DB_URL` | jdbc:h2:mem:testdb | 테스트용 H2 DB 주소 |
| `TEST_DB_USERNAME` | sa | 테스트용 DB 사용자 |

### 시크릿 관리도구 선택

**GitHub Secrets**는 GitHub에서 제공하는 암호화된 저장소입니다. GitHub Actions와 바로 연동되고 별도 설정 없이 사용할 수 있습니다. 무료이고 로그에 자동으로 마스킹돼서 보안도 괜찮습니다. GitHub에 의존적인 특징이 있습니다.

**AWS Secrets Manager**는 AWS에서 제공하는 관리형 비밀 저장소입니다. 버전 관리가 되고 비밀번호 자동 로테이션 기능이 있습니다. 사용량에 따라 비용이 발생하고 설정이 복잡하다는 특징이 있습니다.

**AWS Parameter Store**는 AWS에서 제공하는 파라미터 저장 서비스입니다. 무료 티어가 있어서 비용 부담을 줄일 수 있습니다. Secrets Manager보다 기능이 적고 자동 로테이션이 안 된다는 특징이 있습니다.

**HashiCorp Vault**는 오픈소스 비밀 관리 도구입니다. 보안이 강력하고 멀티클라우드 환경에서 쓸 수 있습니다. 직접 서버를 운영해야 해서 관리 부담의 특징이 있습니다.

**.env 파일**은 서버에 직접 파일로 저장하는 방식입니다. 가장 단순하지만 보안에 취약하고 여러 서버에서 관리하기 어렵다는 특징이 있습니다.

### *저희 팀은 GitHub를 사용하고 있으며 Github Actions와 바로 연동된다는 특성을 고려하여 Github Secrets를 사용했습니다.

### GitHub Secrets

GitHub Repository Settings → Secrets and variables → Actions에서 설정합니다.

```yaml
# 워크플로우에서 사용 시
env:
  DATABASE_PASSWORD: ${{ secrets.DATABASE_PASSWORD }}
  JWT_SECRET: ${{ secrets.JWT_SECRET }}
  OAUTH_CLIENT_SECRET: ${{ secrets.OAUTH_CLIENT_SECRET }}

```

| Secret명 | 용도 | 설정 위치 |
| --- | --- | --- |
| `DATABASE_PASSWORD` | 테스트 DB 비밀번호 (필요 시) | Repository Secrets |
| `JWT_SECRET` | JWT 토큰 서명 키 | Repository Secrets |
| `OAUTH_CLIENT_ID` | 소셜 로그인 Client ID | Repository Secrets |
| `OAUTH_CLIENT_SECRET` | 소셜 로그인 Client Secret | Repository Secrets |
| `KAKAO_MAP_API_KEY` | 카카오 지도 API 키 | Repository Secrets |
| `SLACK_WEBHOOK_URL` | CI 실패 알림용 Slack Webhook | Repository Secrets |

---

## 사용 예시

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      JAVA_VERSION: '17'
      SPRING_PROFILES_ACTIVE: 'test'
    steps:
      - name: Run Tests
        env:
          JWT_SECRET: ${{ secrets.JWT_SECRET }}
          OAUTH_CLIENT_SECRET: ${{ secrets.OAUTH_CLIENT_SECRET }}
        run: ./gradlew test

```

---

## 주의사항

| 구분 | 환경 변수 | GitHub Secrets |
| --- | --- | --- |
| 노출 여부 | 로그에 노출 가능 | 로그에 마스킹 처리 |
| 저장 대상 | 포트, 버전, 프로파일 등 | API 키, 비밀번호, 토큰 등 |
| 변경 방법 | 워크플로우 파일 수정 | GitHub 설정에서 변경 |
