## 1. 개요

Moyeobab 서비스의 E2E 테스트를 위한 도구를 선정한다.

## 2. 서비스 기술 스택

| 구분 | 기술 |
|------|------|
| 프론트엔드 | React, TypeScript, Vite |
| 백엔드 (메인 API) | Spring Boot (`moyeobab-api.service`) |
| 백엔드 (AI 추천) | Python FastAPI (`recommend.service`) |
| 인증 | 카카오 OAuth 2.0 (302 리다이렉트 기반) |
| 보안 | CSRF 토큰 (쿠키 기반) |
| 인프라 | AWS EC2, Nginx, PostgreSQL, Redis |
| 배포 도메인 | `https://api.moyeobab.com` |

## 3. 도구 선정 기준

E2E 테스트 도구를 선정하기 위해 Moyeobab 서비스의 특성에서 도출한 평가 기준이다.

| 기준 | 근거 |
|------|------|
| OAuth 리다이렉트 처리 | 카카오 로그인이 302 리다이렉트 기반이므로, 외부 도메인 전환 및 콜백 처리를 안정적으로 지원해야 한다 |
| 크로스 브라우저 지원 | 모바일 환경에서도 사용 가능한 서비스이므로 Chromium 외에 WebKit(Safari) 테스트가 가능해야 한다 |
| API + UI 혼합 테스트 | UI 흐름과 API 직접 호출을 하나의 테스트 안에서 결합할 수 있어야 한다 (예: API로 모임 생성 후 UI에서 투표 진행) |

## 4. 후보 도구 비교

### 4.1 Playwright

Microsoft에서 개발한 오픈소스 E2E 테스트 프레임워크이다. 2020년 출시 이후 빠르게 성장하여 GitHub 스타 61,000개 이상, NPM 주간 다운로드 400만 이상을 기록하고 있다.

**주요 특징**

- Chromium, Firefox, WebKit 세 엔진을 단일 API로 지원한다
- DevTools Protocol로 브라우저를 직접 제어하여 auto-wait가 내장되어 있다
- `request` 컨텍스트를 통해 UI 테스트와 API 테스트를 하나의 스크립트에서 혼합할 수 있다
- `storageState`로 인증 상태(쿠키, localStorage)를 파일로 저장하고 테스트 간 재사용할 수 있다
- `route()`를 통한 네트워크 요청 가로채기, 모킹, 수정이 가능하다
- Trace Viewer로 테스트 실패 시 스크린샷, DOM 스냅샷, 네트워크 로그를 타임라인으로 확인할 수 있다
- JavaScript, TypeScript, Python, Java, C# 등 다중 언어를 지원한다

### 4.2 Cypress

프론트엔드 개발자 친화적인 E2E 테스트 도구이다. 브라우저 내부에서 직접 실행되는 고유한 아키텍처를 가진다.

**주요 특징**

- 브라우저의 이벤트 루프 안에서 실행되어 DOM에 직접 접근할 수 있다
- Time Travel 디버깅으로 각 스텝의 DOM 상태를 시각적으로 확인할 수 있다
- `cy.intercept()`로 네트워크 요청을 가로채고 모킹할 수 있다
- `cy.request()`로 API 호출이 가능하다
- JavaScript/TypeScript만 지원한다
- v10.8.0부터 WebKit(Safari 엔진)을 실험적(experimental)으로 지원한다. `experimentalWebKitSupport: true` 설정과 `playwright-webkit` 패키지 설치가 필요하며, Playwright의 WebKit 빌드를 내부적으로 활용한다

**제한 사항**

- WebKit 지원이 아직 experimental 단계이므로 일부 기능 누락이나 버그가 존재할 수 있다
- 단일 탭에서만 동작하므로 OAuth 리다이렉트 시 외부 도메인으로의 전환이 제약된다. `cy.origin()`으로 부분적으로 우회할 수 있으나 완전하지 않다
- 브라우저 내부 실행 구조로 인해 멀티 탭, iframe 처리에 제약이 있다
- 무료 병렬 실행이 제한적이다 (Cypress Cloud 유료 또는 외부 도구 필요)

### 4.3 Selenium

2004년부터 사용된 가장 오래된 브라우저 자동화 프레임워크이다. WebDriver 프로토콜을 통해 브라우저를 제어한다.

**주요 특징**

- 사실상 모든 브라우저를 지원한다 (Chrome, Firefox, Safari, Edge, Opera 등)
- Java, Python, C#, Ruby, JavaScript, Kotlin 등 가장 넓은 언어 지원을 제공한다
- Selenium Grid를 통한 분산 테스트 실행이 가능하다
- Selenium 4+에서 BiDi 프로토콜과 CDP를 지원하여 네트워크 인터셉션 등의 기능이 추가되었다

**제한 사항**

- WebDriver 계층을 거치므로 Playwright 대비 실행 속도가 느리다
- auto-wait가 내장되어 있지 않아 명시적 대기(explicit wait)를 직접 관리해야 한다
- 브라우저 드라이버 설치 및 버전 관리가 필요하다 (Selenium 4.6+ Selenium Manager로 개선됨)
- 인증 상태 재사용을 위한 내장 기능이 없어 직접 쿠키를 관리해야 한다
- 디버깅 도구가 Playwright, Cypress 대비 부족하며 외부 플러그인에 의존한다

### 4.4 비교 요약

| 평가 기준 | Playwright | Cypress | Selenium |
|-----------|:----------:|:-------:|:--------:|
| OAuth 리다이렉트 처리 | 외부 도메인 리다이렉트를 자연스럽게 추적 | 단일 도메인 원칙으로 인해 `cy.origin()` 우회 필요 | 리다이렉트 추적 가능 |
| 크로스 브라우저 (WebKit 포함) | Chromium, Firefox, WebKit | Chromium, Firefox, WebKit (experimental) | 거의 모든 브라우저 |
| API + UI 혼합 테스트 | `request` 컨텍스트 내장 | `cy.request()` 가능하나 UI 컨텍스트와 분리됨 | 별도 HTTP 클라이언트 필요 |
| 디버깅 | Trace Viewer (타임라인 기반) | Time Travel (DOM 스냅샷) | 외부 도구 의존 |
| 실행 속도 | 벤치마크 기준 가장 빠름 | 벤치마크 기준 가장 느림 | Playwright과 유사함 |

## 5. 팀 기술 스택 호환성 검토

### 5.1 프론트엔드 (React + TypeScript + Vite)

세 도구 모두 React 앱 테스트를 지원한다. Playwright와 Cypress는 TypeScript를 네이티브로 지원하므로 프론트엔드와 동일한 언어로 테스트를 작성할 수 있다. Vite 기반 프로젝트와의 호환성도 세 도구 모두 문제없다.

### 5.2 카카오 OAuth 인증 흐름

Moyeobab의 로그인 흐름은 다음과 같다:

1. `/api/v1/auth/kakao/login` → 카카오 인가 페이지로 302 리다이렉트
2. 카카오 로그인/동의 → `/api/v1/auth/kakao/auth-code`로 콜백
3. state 검증 후 프론트엔드로 302 리다이렉트 (AT/RT 쿠키 설정)

이 과정에서 `api.moyeobab.com` → `kauth.kakao.com` → `api.moyeobab.com` → 프론트엔드로 도메인이 여러 차례 전환된다. 도구가 외부 도메인 리다이렉트를 안정적으로 추적할 수 있는지가 핵심 검토 사항이다.

### 5.3 CSRF 토큰 및 쿠키 기반 인증

모든 쓰기 API가 `X-CSRF-Token` 헤더를 요구하며, 인증 토큰은 쿠키로 관리된다. API 레벨 테스트 시 CSRF 토큰 발급(`/api/csrf`) → 쿠키 수신 → 후속 요청에 헤더 포함하는 흐름을 테스트 내에서 처리할 수 있어야 한다.

### 5.4 Spring Boot + FastAPI 구성

메인 API(Spring Boot)와 추천 API(FastAPI)가 분리되어 있으나, E2E 관점에서는 프론트엔드를 통해 통합된 흐름으로 테스트하므로 도구 선택에 직접적인 영향은 없다.

## 6. 선정 결과: Playwright

### 6.1 선정 이유

Moyeobab의 핵심 기술적 요구사항에 대해 Playwright가 가장 적합한 이유는 다음과 같다.

**카카오 OAuth 리다이렉트 완벽 지원**: Moyeobab의 로그인은 3회 이상의 도메인 전환이 발생하는 OAuth 흐름이다. Playwright는 외부 도메인 리다이렉트를 제한 없이 추적하며, 인증 완료 후 `storageState`로 쿠키 상태를 저장해 이후 테스트에서 재사용할 수 있다.

**API + UI 혼합 테스트가 자연스러움**: 모임 생성(API) → 초대 코드 공유 → 참여(UI) → 투표(UI) → 최종 선택(UI) 같은 시나리오에서, 사전 데이터를 API로 세팅하고 이어서 UI 테스트를 진행하는 패턴이 빈번하다. Playwright는 동일 테스트 내에서 `request` 컨텍스트와 `page` 컨텍스트를 자유롭게 전환할 수 있다.

**WebKit 정식 지원**: 모바일에서도 사용 가능한 서비스이므로 iOS Safari 사용자를 고려해야 한다. Playwright는 WebKit 엔진 테스트를 정식 기능으로 제공한다.

**실행 속도**: 전체 시나리오를 한 번에 돌릴 때 속도 차이가 체감된다. 벤치마크 기준 동일 테스트 평균 실행 시간이 약 4.5초로 가장 빠르다.

### 6.2 사용 계획

- 로컬 환경에서 headed 모드로 실행하여 테스트 흐름을 직접 확인한다
- 인증은 setup 단계에서 1회 수행 후 `storageState`로 전 테스트에 공유한다
- Trace Viewer를 활용하여 실패 시나리오를 분석한다