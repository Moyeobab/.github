# 프로젝트 이름 Backend Wiki
a
### [서비스 바로가기](여기에_서비스_URL_삽입)
[Backend Repository](여기에_백엔드_레포_URL_삽입)

<br />

## 목차
> - [개발 일정](#개발-일정)
> - [컨벤션 룰](#컨벤션-룰)
> - [트러블 슈팅](#트러블-슈팅)
> - [ERD](#ERD)
> - [API](#API)
> - [배포 환경 및 CI/CD 파이프라인](#배포-환경-및-CI/CD-파이프라인)
> - [코드 품질 관리 도구](#코드-품질-관리-도구)

<br />

## 개발 일정
| 기간 | 주요 작업 |
|------|-------------|
| MM/DD ~ | 작업 내용 작성 |

<br />

## 컨벤션 룰

### 1. 코드 스타일 가이드
> 예시 <br>
1. EditorConfig 설정

설정 항목 | 값 | 설명
-- | -- | --
charset | utf-8 | 
end_of_line | lf | 
indent_style | space | 
insert_final_newline | true | 
trim_trailing_whitespace | true | 
max_line_length | 120 | 

### 2. CheckStyle 설정
> 예시 <br>

항목 | 규칙
-- | --
클래스명 | 
변수명 및 메서드명 | 
상수명 | 
패키지명 | 
탭 사용 | 
줄 바꿈 | 
최대 라인 길이 | 
제어문 블록 {} | 
연산자 배치 | 
import 순서 | 
주석 스타일 | 

### 3. 커밋 메시지 컨벤션
> 예시 
<br>

** 커밋 메시지는 type: message 형식을 따르며, 아래의 규칙을 따릅니다. **  

**제목 규칙**

- 제목은 다음 대소문자 스타일 중 하나를 따라야 합니다:
    - sentence-case
    - start-case
    - pascal-case
    - upper-case
    - lower-case
- 제목 끝에 마침표(.)를 사용하지 않습니다.
- 제목은 최소 5자 이상이어야 합니다.
- 전체 헤더는 72자를 초과하지 않아야 합니다.

타입 | 설명
-- | --
build | 
chore | 
content | 
docs | 
feat | 
fix | 
refactor | 
style | 
test | 
deploy | 

#### 커밋 메시지 형식
<pre><code>type: 제목 (#이슈번호)

본문 (선택 사항)

</code></pre>

예시
<pre><code>feat: 기능 요약 (#이슈번호)

기능에 대한 간단한 설명 추가

</code></pre>

### 4. 추가 규칙
> 예시 <br>
<ul>
<li>PR 제목은 커밋 메시지와 동일한 형식을 유지합니다.</li>
<li>한 번의 PR은 하나의 목적을 가져야 합니다.</li>
<li>코드 리뷰를 거친 후 병합을 수행합니다.</li>
</ul>
<p>이 컨벤션을 준수하여 팀의 코드 품질을 유지하고 원활한 협업을 진행합시다!</p>
<!-- notionvc: template-id-placeholder -->

<br />

## 트러블 슈팅
- [1. 트러블 슈팅 제목](링크)

<br />

## ERD
> ERD 이미지 또는 링크 삽입

<br />

## API
1. [API 인증 흐름](API 인증 흐름 링크)
2. [API 응답 규격](응답 규격 링크)
3. [에러 메세지 목록](에러 목록 링크)

<br />

## 배포 환경 및 CI/CD 파이프라인
> 관련 구성 및 파이프라인 설명 작성

<br />

## 코드 품질 관리 도구
> 예시 <br>

| 도구 | 역할 | 목적 |
|------|-------------|-------------|
| .editorconfig |  |  |
| Checkstyle |  |  |
| JaCoCo |  |  |
| Java Test Fixtures |  |  |
| SonarQube |  |  |