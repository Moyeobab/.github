## 1. 개요

Playwright를 사용한 E2E 테스트 환경을 구성한다. 프론트엔드 레포 내에 테스트 프로젝트를 세팅하고, dev 환경을 대상으로 테스트를 수행한다.

## 2. 테스트 대상 환경

| 구분 | dev 환경 | prod 환경 |
|------|----------|-----------|
| 용도 | E2E 테스트 수행 | 실 서비스 운영 |
| 배포 브랜치 | develop | main |
| API 서버 | dev EC2 | prod EC2 |
| 데이터베이스 | dev DB | prod DB |

E2E 테스트는 dev 환경에서만 수행한다. 모임 생성/삭제, 회원가입/탈퇴 등 데이터 변경이 발생하는 시나리오를 prod에서 실행하면 실 데이터가 오염될 수 있다.

## 3. Playwright 설치 및 프로젝트 세팅

### 3.1 설치

프론트엔드 레포 루트에서 Playwright를 설치한다.

```bash
npm init playwright@latest
```

설치 과정에서 다음 옵션을 선택한다:

- TypeScript 사용 (프론트엔드와 동일한 언어)
- 테스트 디렉토리: `e2e/` 또는 `tests/`
- GitHub Actions workflow 추가: No (현재는 CI 연동 안 함)
- 브라우저 설치: Yes

### 3.2 프로젝트 구조

```
frontend/
├── src/
├── e2e/
│   ├── tests/           # 테스트 파일
│   │   ├── auth.spec.ts
│   │   ├── meeting.spec.ts
│   │   └── vote.spec.ts
│   ├── fixtures/        # 테스트 픽스처 (재사용 가능한 설정)
│   ├── pages/           # Page Object Model (선택)
│   └── playwright.config.ts
├── package.json
└── ...
```

### 3.3 설정 파일

`e2e/playwright.config.ts` 기본 설정:

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  retries: 0,
  
  use: {
    baseURL: 'https://dev.moyeobab.com',  // dev 환경 URL
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
    {
      name: 'Mobile Chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'Mobile Safari',
      use: { ...devices['iPhone 13'] },
    },
  ],
});
```

### 3.4 환경 변수

테스트에 필요한 민감 정보는 파일에 저장하지 않고, 실행 시 환경 변수로 주입한다.

```bash
# 실행 시 환경 변수 주입
TEST_KAKAO_EMAIL=test@example.com TEST_KAKAO_PASSWORD=****** npx playwright test
```

테스트 코드에서 환경 변수 사용:

```typescript
const email = process.env.TEST_KAKAO_EMAIL;
const password = process.env.TEST_KAKAO_PASSWORD;
```

## 4. 테스트 전용 환경 구성

### 4.1 테스트 계정

**카카오 로그인 테스트 계정**

| 항목 | 설명 |
|------|------|
| 권장 | 테스트 전용 카카오 계정 생성 |
| 대안 | 개인 계정 사용 (회원탈퇴 시나리오 주의) |

테스트 전용 계정 사용 시 장점:
- 회원탈퇴 시나리오 안전하게 수행 가능
- 팀원 간 계정 공유 용이
- 개인 계정 데이터와 분리

개인 계정 사용 시 주의사항:
- 회원탈퇴(`DELETE /api/v1/member/me`) 시나리오는 스킵하거나 수동 확인으로 대체
- 테스트 데이터(모임, 투표 등)가 계정에 누적됨

### 4.2 테스트 데이터 관리

**원칙**

- 테스트 시작 시 필요한 데이터를 API로 직접 생성
- 테스트 종료 후 생성한 데이터 정리 (teardown)
- 다른 테스트에 영향을 주지 않는 독립적인 데이터 사용

**예시: 모임 테스트 데이터**

```typescript
test.beforeEach(async ({ request }) => {
  // 테스트용 모임 생성
  const response = await request.post('/api/v1/meetings', {
    data: {
      title: `E2E_TEST_${Date.now()}`,
      scheduledAt: '2025-02-10T12:00:00',
      // ...
    }
  });
  testMeetingId = (await response.json()).meetingId;
});

test.afterEach(async ({ request }) => {
  // 테스트용 모임 삭제
  await request.delete(`/api/v1/meetings/${testMeetingId}`);
});
```

### 4.3 dev DB 고려사항

dev DB에서 테스트를 수행하므로 다음 사항을 고려한다:

- 테스트 데이터는 `E2E_TEST_` 같은 prefix로 식별 가능하게 생성
- 주기적으로 테스트 데이터 정리 필요 시 prefix 기반으로 일괄 삭제 가능
- dev 환경을 다른 팀원이 수동 테스트 중일 수 있으므로, 기존 데이터 삭제/수정은 지양

## 5. 테스트 실행

### 5.1 기본 실행

```bash
# 전체 테스트 실행 (headless)
npx playwright test

# headed 모드로 실행 (브라우저 화면 확인)
npx playwright test --headed

# 특정 테스트 파일만 실행
npx playwright test auth.spec.ts

# 특정 브라우저만 실행
npx playwright test --project=chromium
```

### 5.2 디버깅

```bash
# UI 모드로 실행 (각 스텝 확인 가능)
npx playwright test --ui

# 디버그 모드
npx playwright test --debug

# 실패한 테스트 리포트 확인
npx playwright show-report
```

### 5.3 Trace Viewer

테스트 실패 시 trace 파일이 생성된다. 타임라인 기반으로 스크린샷, DOM 스냅샷, 네트워크 로그를 확인할 수 있다.

```bash
npx playwright show-trace trace.zip
```

## 6. CI/CD 파이프라인 연동 (추후 확장)

현재는 CI/CD에 연동하지 않고 로컬에서 수동 실행한다. 추후 필요 시 GitHub Actions로 연동할 수 있다.

### 6.1 연동 시 고려사항

- E2E 테스트는 실행 시간이 길고 외부 의존성(카카오 OAuth, dev 서버)이 있으므로 PR마다 실행하기보다 일정 주기(야간, 배포 전) 실행이 적합
- 카카오 로그인 자동화를 위해 GitHub Secrets에 테스트 계정 정보 저장 필요
- dev 서버가 실행 중이어야 테스트 가능하므로 서버 상태 체크 로직 필요

### 6.2 GitHub Actions 예시 구조

```yaml
# .github/workflows/e2e.yml (참고용)
name: E2E Tests

on:
  workflow_dispatch:  # 수동 실행
  schedule:
    - cron: '0 0 * * *'  # 매일 자정 (선택)

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npx playwright test
        env:
          TEST_KAKAO_EMAIL: ${{ secrets.TEST_KAKAO_EMAIL }}
          TEST_KAKAO_PASSWORD: ${{ secrets.TEST_KAKAO_PASSWORD }}
```

실제 연동 시점에 상세 설정을 진행한다.