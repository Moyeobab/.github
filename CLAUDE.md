# Claude 작업 지침 (.github)

이 리포는 모여밥(Moyeobab) organization의 문서 허브입니다. Claude가 이 리포에서 작업할 때 따라야 할 규칙을 정리합니다.

## 리포 역할

- `profile/README.md` — organization 메인 페이지에 표시되는 소개
- `docs/README.md` — 전체 문서 네비게이션 허브
- `docs/{ai,cloud,backend,frontend,planning}/` — 카테고리별 문서

원본 wiki는 `../13-team-project-wiki.wiki/`에 있고, 이 리포는 그 복사본 기반입니다.

## 자주 하는 작업

문서 **구조 개편** — 폴더 재배치, 파일 이동, 인덱스 갱신.

## 규칙

### 폴더 구조

- 카테고리는 `ai / cloud / backend / frontend / planning` **5개로 고정**.
- 새 카테고리를 임의로 만들지 않는다.
- infra 관련 문서는 `cloud/`에 둔다 (별도 `infra/` 폴더 만들지 않기).

### 파일

- `_Sidebar.md`, `_Footer.md` 같은 GitHub Wiki 전용 파일은 만들지 않는다 — 일반 리포에선 작동하지 않는다.
- `profile/README.md`는 위치 고정. organization 메인 페이지에 노출되므로 경로를 옮기지 않는다.

### 인덱스 동기화

- 문서를 **추가/삭제/이동**하면 `docs/README.md`의 해당 카테고리 링크를 반드시 함께 갱신한다.
- 카테고리 인덱스 파일(`Cloud-Wiki.md` 등)도 영향 있으면 같이 갱신한다.

### 이미지

- 이미지는 해당 카테고리 폴더 안에 둔다. 예: `docs/cloud/images/`, `docs/cloud/milestone/m1/assets/images/`.
- 카테고리 외부의 공용 `assets/` 디렉토리는 만들지 않는다.

### 원본 wiki는 건드리지 않는다

- `../13-team-project-wiki.wiki/`는 읽기 전용으로 본다.
- 동기화가 필요하면 wiki → `.github`로만 단방향 복사. 반대 방향은 하지 않는다.

## 커밋

- Conventional Commits 스타일을 따른다. 이 리포는 문서만 다루므로 사실상 `docs:` 한 종류면 충분하다.
  - 예: `docs: add M7 E2E 테스트 시나리오 페이지`
  - 예: `docs: fix broken links in cloud/Cloud-Wiki.md`
- 제목은 72자 이내, 끝에 마침표 X.
- Co-Authored-By 라인은 붙이지 않는다.

## 브랜치/푸시

- `main`에 직접 푸시 OK. 별도 PR 절차 없다.
- force push가 필요한 경우(예: 직전 커밋 메시지 수정)에는 `--force-with-lease`를 쓴다.

## 링크

- `.md` 확장자 + 상대경로를 권장한다.
- wiki 스타일 링크(`[text](Page-Name)`처럼 확장자 없는 링크)도 GitHub에서 그럭저럭 보이므로 강제하지는 않는다 — 다만 새로 작성할 때는 `.md`를 붙이는 게 깔끔하다.
