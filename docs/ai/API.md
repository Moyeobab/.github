# 음식점 추천 기능
## 엔드포인트 목록 & 기능 설명
#### 1. `POST /api/v1/recommendations`
- 모임 정보(선호/비선호 집계, 시작시간, 인원, 장소, 스와이프갯수)를 입력받아 스와이프 카드용 식당 랭킹(top_n) 반환
#### 2. `POST /api/v2/meetings`
- 모임 정보(선호/비선호 집계, 시작시간, 인원, 장소, 스와이프갯수)를 입력받아 스와이프 카드용 식당 랭킹(top_n) 반환
- 유사 모임 벡터 적용 → 모임생성 + 추천 반환
- 입력 : 모임 정보
- 출력 : meeting_id, 추천 결과 리스트, 랭킹, 점수

<br>

## 입출력 형식 명세서
#### 2.1. `POST /api/v1/recommendations`
**(1) Request JSON Schema**
```json
{
  "user_id": "number (>=1)",
  "request_id": "string",

  "meeting": {
    "start_time": "string (ISO8601, timezone 포함)",
    "headcount": "number (>=1)"
  },

  "location": {
    "lat": "number (-90~90)",
    "lng": "number (-180~180)",
    "radius_m": "number (100~20000)"
  },

  "swipe": {
    "card_limit": "number (1~15)"
  },

  "preferences": {
    "like": {
      "한식": "number (>=0)",
      "중식": "number (>=0)",
      "...": "..."
    },
    "dislike": {
      "한식": "number (>=0)",
      "중식": "number (>=0)",
      "...": "..."
    }
  }
}

`````
**(2) Request Example**
```json
{
  "user_id": 123,
  "request_id": "req_20260106_0302",
  "meeting": {
    "start_time": "2026-01-10T19:00:00+09:00",
    "headcount": 6
  },
  "location": {
    "lat": 37.4979,
    "lng": 127.0276,
    "radius_m": 2000
  },
  "swipe": {
    "card_limit": 10
  },
  "preferences": {
    "like": {
      "한식": 1,
      "중식": 3,
      "일식": 2,
      "양식": 0,
      "아시안": 1,
      "고기": 3,
      "해산물": 0,
      "치킨": 1,
      "분식": 0
    },
    "dislike": {
      "한식": 0,
      "중식": 0,
      "일식": 0,
      "양식": 2,
      "아시안": 0,
      "고기": 0,
      "해산물": 3,
      "치킨": 0,
      "분식": 1
    }
  }
}
```
**(3) Response JSON Schema** 

```json
{
  "request_id": "string",
  "user_id": "number",
  "top_n": "number",
  "restaurants": [
    {
      "rank": "number (>=1)",
      "store_id": "string",
      "distance_m": "number (>=0)",
      "final_score": "number (0.0~1.0)"
    }
  ],
  "created_at": "string (ISO8601, timezone 포함)"
}
```
**(4) Response Example** 
```json
{
  "request_id": "req_20260106_0302",
  "user_id": 123,
  "top_n": 10,
  "restaurants": [
    { "rank": 1, "store_id": "s_000001", "distance_m": 320, "final_score": 0.93 },
    { "rank": 2, "store_id": "s_000002", "distance_m": 340, "final_score": 0.91 }
  ],
  "created_at": "2026-01-10T19:00:00+09:00"
}
```
<br>

**에러코드**

HTTP | code | 의미
-- | -- | --
400 | INVALID_REQUEST | 요청 형식 오류
400 | INVALID_LOCATION | 위치 정보 오류
422 | UNPROCESSABLE_PREFERENCES | 선호 조건 의미 오류
404/200 | NO_RESTAURANTS_FOUND | 후보 없음
500 | RECOMMENDATION_FAILED | 추천 로직 실패
503 | DATABASE_UNAVAILABLE | DB 장애


<!-- notionvc: a981b5bf-0119-4059-b374-6b2dbb3b1a3f -->


<br>

#### 2.2 **`POST /api/v2/meetings` (세션 생성 + 추천)**

**(1) Request JSON Schema**

```json
{
  "user_id": "number (>=1)",
  "request_id": "string",

  "meeting": {
    "start_time": "string (ISO8601, timezone 포함)",
    "headcount": "number (>=1)"
  },

  "location": {
    "lat": "number (-90~90)",
    "lng": "number (-180~180)",
    "radius_m": "number (100~20000)"
  },

  "swipe": {
    "card_limit": "number (1~15)"
  },

  "preferences": {
    "like": {
      "한식": "number (>=0)",
      "중식": "number (>=0)",
      "...": "..."
    },
    "dislike": {
      "한식": "number (>=0)",
      "중식": "number (>=0)",
      "...": "..."
    }
  }
}

```

**(2) Request Example**

```json
{
  "user_id": 123,
  "request_id": "req_20260106_0302",
  "meeting": {
    "start_time": "2026-01-10T19:00:00+09:00",
    "headcount": 6
  },
  "location": {
    "lat": 37.4979,
    "lng": 127.0276,
    "radius_m": 2000
  },
  "swipe": {
    "card_limit": 10
  },
  "preferences": {
    "like": { "한식": 1, "중식": 3, "일식": 2, "양식": 0, "아시안": 1, "고기": 3, "해산물": 0, "치킨": 1, "분식": 0 },
    "dislike": { "한식": 0, "중식": 0, "일식": 0, "양식": 2, "아시안": 0, "고기": 0, "해산물": 3, "치킨": 0, "분식": 1 }
  }
}
```

**(3) Response JSON Schema** 

```json
{
  "request_id": "string",
  "user_id": "number",
  "top_n": "number",
  "restaurants": [
    {
      "rank": "number (>=1)",
      "store_id": "string",
      "distance_m": "number (>=0)",
      "final_score": "number (0.0~1.0)"
    }
  ],
  "created_at": "string (ISO8601, timezone 포함)"
}
```

**(4) Response Example**

```json
{
  "request_id": "req_20260106_0302",
  "user_id": 123,
  "top_n": 10,
  "restaurants": [
    { "rank": 1, "store_id": "s_000001", "distance_m": 320, "final_score": 0.93 },
    { "rank": 2, "store_id": "s_000002", "distance_m": 340, "final_score": 0.91 }
  ],
  "created_at": "2026-01-10T19:00:00+09:00"
}
```
<br>

**에러코드**

HTTP | code | 의미
-- | -- | --
400 | INVALID_REQUEST | 형식/필수값 오류
400 | INVALID_LOCATION | 위치 오류
422 | CANDIDATE_FILTER_TOO_STRICT | 후보 생성 불가(필터 과함)
409 | DUPLICATE_REQUEST | request_id 중복
500 | POOL_BUILD_FAILED | 후보풀 생성 실패
503 | DATABASE_UNAVAILABLE | RDB 장애
503/200 | VECTOR_DB_UNAVAILABLE | (옵션) 유사모임 검색 장애


<!-- notionvc: 1c87928b-e11c-4e10-900f-8fa4f544622b -->

<br>

## 서비스 전체 구조에서의 API의 역할 & 연동 관계
"맛침반" 서비스에서 호출하는 추천 게이트웨이 역할

<br>

### 역할

1.  **V1**
- 클라이언트 입력(모임 정보) → 추천 결과(식당 ID, 랭킹, 점수) 반환
- 추천 결과
    - 프론트가 카드 UI로 보여준다
1. **V2**
    
    모임 단위로 모임정보와 최종 선택한 식당이 축적됨
    
    **(1) Serving : 음식점 추천**
    
    - 사용자 요청 → 후보 조회(RDB) → 스코어링 → 랭킹 반환
    - 유사 모임 반영
        - vector DB에서 meeting_vector 유사 검색
        - 유사 모임의 최종 선택 식당들의 특징 추출해 가중치 보정
    
    **(2) Learning/Memory : 모임 임베딩 저장**
    
    - 최종 선택 확점 시점에
        - meeting features(모임 조건 + 최종 선택 식당 특징) 구성
        - embedding → meeting_vector 생성
        - Vector DB에 meeting_id키로 저장
    
    **(3) RDB와 Vector DB의 역할 분리**
    
    - **RDB**: “사실(ground truth) 저장”
        - meeting 테이블(요청/조건)
        - final choice
        - restaurants 정형 속성(카테고리/좌표/영업시간/리뷰수 등)
    - **Vector DB**: “경향/유사성 검색”
        - meeting_vector
        - 유사 meeting을 빠르게 찾고 추천에 반영

### 연동 관계

- RDB : place_id/store_id, 좌표, 카테고리, 영업시간, 메뉴, 리뷰 수, 편의시설 등
- Vector DB : 리뷰/AI브리핑/LLM 태그 임베딩 → V2에서 “비슷한 식당/취향” 검색에 활용
- LLM : 리뷰 태그 정규화, 식당 카테고리 정규화

<br><br>
# RAG 챗봇
- **Backend(API Gateway)**: 인증/권한, 식당 CRUD, 검색 필터, 대화 세션/로그 저장, AI 서버 호출
- **AI/RAG Server(Internal)**: 임베딩/인덱싱, 검색(retrieve), 답변 생성(generate), 출처/근거 반환
<br><br>

## 엔드포인트 목록 & 기능 설명
#### 1. `POST /api/v3/chat:generate`
백엔드가 사용자 질문을 보내면
AI 서버가
- VectorDB retrieve (필요시 hybrid/rerank)
- LLM 답변 생성
- citations(근거) 반환
<br>

## 입출력 형식 명세서

#### 2.1 `POST /api/v3/chat:generate`

**(1) Request JSON Schema**

```json
{
  "request_id": "string",
  "trace": {
    "session_id": "string",
    "user_id": "string",
    "locale": "ko-KR",
    "timezone": "Asia/Seoul"
  },
  "query": "string",
  "history": [
    { "role": "user", "content": "string" },
    { "role": "assistant", "content": "string" }
  ],
  "filters": {
    "region": "string",
    "categories": ["string"],
    "must_have": ["string"],
    "exclude": ["string"],
    "price_range": { "min": 0, "max": 0 },
    "open_now": true
  },
  "retrieval": {
    "top_k": 8,
    "hybrid": true,
    "rerank": true,
    "score_threshold": 0.0
  },
  "generation": {
    "answer_style": "concise_korean",
    "cite_sources": true,
    "max_tokens": 700,
    "temperature": 0.3
  }
}

```
**(2) Request Example**
```json
{
  "request_id": "req_20260107_0001",
  "trace": {
    "session_id": "sess_123",
    "user_id": "u_77",
    "locale": "ko-KR",
    "timezone": "Asia/Seoul"
  },
  "query": "삼평동에서 단체 가능하고 주차 되는 일식집 추천해줘",
  "history": [
    { "role": "user", "content": "삼평동 근처 회식할 곳 찾아줘" },
    { "role": "assistant", "content": "인원수와 선호 카테고리를 알려주면 더 정확해요." }
  ],
  "filters": {
    "region": "삼평동",
    "categories": ["일식"],
    "must_have": ["주차", "단체"]
  },
  "retrieval": { "top_k": 8, "hybrid": true, "rerank": true, "score_threshold": 0.25 },
  "generation": { "answer_style": "concise_korean", "cite_sources": true, "max_tokens": 700, "temperature": 0.2 }
}

```


**(3) Response JSON Schema**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/schemas/chat-generate-response.json",
  "type": "object",
  "required": [
    "request_id",
    "answer",
    "citations",
    "insufficient_context"
  ],
  "properties": {
    "request_id": {
      "type": "string",
      "description": "요청 추적을 위한 고유 ID (백엔드에서 전달하거나 서버에서 생성)"
    },
    "answer": {
      "type": "string",
      "description": "RAG 기반으로 생성된 최종 사용자 응답 텍스트"
    },
    "citations": {
      "type": "array",
      "description": "답변의 근거가 되는 문서/식당 정보 목록 (근거가 없으면 빈 배열)",
      "items": {
        "type": "object",
        "required": [
          "restaurant_id",
          "doc_id",
          "snippet"
        ],
        "properties": {
          "restaurant_id": {
            "type": "integer",
            "description": "식당 고유 ID (RDB 기준)"
          },
          "doc_id": {
            "type": "string",
            "description": "VectorDB에 저장된 문서 ID (예: rest_101_facility)"
          },
          "snippet": {
            "type": "string",
            "description": "답변에 사용된 문서의 핵심 근거 텍스트 일부"
          }
        },
        "additionalProperties": false
      }
    },
    "insufficient_context": {
      "type": "boolean",
      "description": "충분한 근거를 찾지 못해 신뢰도 있는 답변이 어려운 경우 true"
    }
  }
}

```

**(4) Response Example**
```json
{
  "request_id": "req_20260107_0001",
  "answer": "…",
  "citations": [
    { "restaurant_id": 101, "doc_id": "rest_101_facility", "snippet": "…" }
  ],
  "insufficient_context": false
}

```
**에러코드**
- 4xx : 재시도 x
- 5xx/408 : 재시도 o
```json
{
  "error": {
    "code": "VECTOR_DB_ERROR",
    "message": "Vector DB search failed",
    "details": {
      "service": "qdrant",
      "reason": "connection timeout"
    },
    "request_id": "req_20260107_0001"
  }
}
```

HTTP | error.code | 의미 | 발생 조건(예시) | 백엔드 대응
-- | -- | -- | -- | --
400 | INVALID_ARGUMENT | 필수 필드 누락 | query 없음 | 요청 스키마 수정
400 | VALIDATION_FAILED | 값 범위/형식 오류 | top_k <= 0 | 파라미터 검증
401 | UNAUTHORIZED | 인증 실패 | 내부 토큰 누락/만료 | 토큰 재발급
403 | FORBIDDEN | 권한 없음 | 호출 서비스 ACL 불일치 | 권한 설정 확인
404 | INDEX_NOT_READY | 활성 인덱스 없음 | 배치 미실행 | 배치 실행
409 | IDEMPOTENCY_CONFLICT | 멱등성 충돌 | 같은 Key 다른 payload | Key 재생성
429 | RATE_LIMITED | 호출 제한 초과 | QPS/일일 쿼터 초과 | 재시도(backoff)

<!-- notionvc: 8c0f0c72-cf05-441b-a9ec-183fb168a5b0 -->

<br><br>
<h1>OCR</h1>
<h2>목적</h2>
<p>영수증 이미지(파일)를 업로드하면 <strong>OCR + 파싱</strong>을 통해 <strong>항목/수량/단가/금액/총액</strong>을 추출하고, 백엔드가 바로 저장/정산에 쓸 수 있도록 <strong>구조화된 JSON</strong>으로 반환한다.</p>
<hr>
<h2>API가 하는 일 1문장 정의</h2>
<p>사용자가 올린 영수증 이미지를 OCR 처리해 메뉴/수량/금액/총액을 추출한 결과를 JSON으로 돌려준다.</p>
<h2>Endpoint</h2>
<h3>1) <code>POST /api/v2/receipts/ocr</code></h3>
<ul>
<li>영수증 이미지 업로드 → OCR 실행 → 항목/총액 추출 → JSON 반환</li>
<li>호출자: Backend (권장), 필요 시 클라이언트 직접 호출도 가능(보안/비용 고려)</li>
</ul>
<h3>2) <code>GET /internal/v2/health</code></h3>
<ul>
<li>OCR 서버 생존 여부 + 핵심 의존성(모델/OCR 엔진 등) 최소 체크</li>
<li>호출자: Backend / 인프라 모니터링</li>
</ul>
<h2>내부용 / 외부용 구분</h2>
<ul>
<li><strong>외부 직접 호출(클라이언트 → OCR 서버)</strong>
<ul>
<li>OCR은 비용/남용 리스크 큼</li>
</ul>
</li>
<li><strong>내부 호출(Backend → OCR 서버)</strong>
<ul>
<li>백엔드가 JWT로 사용자 인증/권한 체크 후, OCR 서버는 <strong>서버 간 인증(Internal Token 또는 mTLS)</strong> 만 확인</li>
</ul>
</li>
</ul>
<h3>내부 호출 인증 헤더 예시</h3>
<ul>
<li><code>X-Internal-Token: &lt;shared-secret&gt;</code></li>
<li>또는 mTLS</li>
</ul>
<h2>입출력 형식 명세서</h2>
<h2><code>POST /api/v2/receipts/ocr</code></h2>
<h3>(1) Request</h3>
<p><strong>Content-Type</strong>: <code>multipart/form-data</code></p>
<h3>필수 필드</h3>
<ul>
<li><code>user_id</code> (int, &gt;=1): 요청 사용자 ID</li>
<li><code>request_id</code> (string): 요청 추적용 고유 ID (idempotency 키로도 사용 가능)</li>
<li><code>image</code> (file): 영수증 이미지 파일
<ul>
<li>권장 확장자: <code>png</code>, <code>jpg</code>, <code>jpeg</code>, <code>heic</code>, <code>heif</code></li>
</ul>
</li>
</ul>
<h3>선택</h3>
<ul>
<li><code>force_ocr</code> (boolean, default <code>false</code>): 캐시가 있어도 재처리</li>
<li><code>client_ts</code> (string ISO8601): 클라 기준 요청 시각(로그/분석용)</li>
</ul>
<h3>(2) Request Example (curl)</h3>
<pre><code class="language-bash">curl -X POST&quot;&lt;https://ocr.example.com/api/v2/receipts/ocr&gt;&quot; \\
  -H&quot;X-Internal-Token: INTERNAL_SHARED_SECRET&quot; \\
  -F&quot;request_id=req_20260106_0001&quot; \\
  -F&quot;image=@receipt.jpg&quot; \\

</code></pre>
<h3>(3) Response JSON Schema (성공)</h3>
<pre><code class="language-json">{
  &quot;request_id&quot;: &quot;string&quot;,
  &quot;result&quot;: {
    &quot;items&quot;: [
      {
        &quot;name&quot;: &quot;string&quot;,
        &quot;unit_price&quot;: &quot;number (&gt;=0)&quot;,
        &quot;quantity&quot;: &quot;number (&gt;=0)&quot;,
        &quot;amount&quot;: &quot;number (&gt;=0)&quot;
      }
    ],
    &quot;total_amount&quot;: &quot;number (&gt;=0)&quot;,
    &quot;discount_amount&quot;: &quot;number (&gt;=0)&quot;,
    &quot;paid_amount&quot;: &quot;number (&gt;=0)&quot;,
    &quot;created_at&quot;: &quot;string (ISO8601, timezone 포함)&quot;
  }
}

</code></pre>
<p><code>source</code></p>
<ul>
<li><code>ocr_llm</code>: OCR 텍스트 → LLM 파싱 성공</li>
<li><code>ocr_rule_fallback</code>: LLM 파싱 실패 → 룰/정규식 기반 추출로 대체</li>
</ul>
<h3>(4) Response Example (성공)</h3>
<pre><code class="language-json">{
  &quot;request_id&quot;: &quot;req_20260106_0001&quot;,
  &quot;result&quot;: {
    &quot;items&quot;: [
    { &quot;name&quot;: &quot;생삼겹살&quot;, &quot;unit_price&quot;: 7000, &quot;quantity&quot;: 25, &quot;amount&quot;: 175000 },
    { &quot;name&quot;: &quot;맥주&quot;, &quot;unit_price&quot;: 3000, &quot;quantity&quot;: 4, &quot;amount&quot;: 12000 },
    { &quot;name&quot;: &quot;음료수&quot;, &quot;unit_price&quot;: 1000, &quot;quantity&quot;: 4, &quot;amount&quot;: 4000 },
    { &quot;name&quot;: &quot;밥+된장&quot;, &quot;unit_price&quot;: 2000, &quot;quantity&quot;: 13, &quot;amount&quot;: 26000 }
    ],
    &quot;total_amount&quot;: 217000,
    &quot;discount_amount&quot;: 17000,
    &quot;paid_amount&quot;: 200000,
    &quot;created_at&quot;: &quot;2026-01-06T18:10:00+09:00&quot;
  }
}

</code></pre>
<h2>에러 규격</h2>
<h3>(1) Error Response Schema</h3>
<pre><code class="language-json">{
&quot;request_id&quot;:&quot;string|null&quot;,
&quot;error&quot;:{
&quot;code&quot;:&quot;string&quot;,
&quot;message&quot;:&quot;string&quot;
}
}

</code></pre>
<h3>(2) Error Codes</h3>

HTTP | code | 의미
-- | -- | --
400 | INVALID_REQUEST | 필수 필드 누락/형식 오류
401 | UNAUTHORIZED | 내부 토큰 누락/불일치
413 | IMAGE_TOO_LARGE | 이미지 용량/해상도 제한 초과
415 | UNSUPPORTED_MEDIA_TYPE | 지원하지 않는 파일 포맷
422 | UNPROCESSABLE_IMAGE | 이미지가 영수증으로 인식 불가/품질 문제
429 | RATE_LIMITED | 요청 과다(사용자/서버 단위 제한)
500 | OCR_FAILED | OCR 실행 실패
500 | PARSING_FAILED | 파싱 실패(룰 fallback도 실패)
503 | DEPENDENCY_UNAVAILABLE | OCR 엔진/LLM/스토리지 등 의존성 장애


<h2>성능/비용</h2>
<ul>
<li><strong>요청 제한(권장)</strong>: 이미지 최대 10MB, 최대 해상도 4000px</li>
<li><strong>처리 시간 목표(예시)</strong>: p95 3초, 타임아웃 10초</li>
<li><strong>캐시(선택)</strong>: <code>image_sha256 + user_id</code> 기준 24시간 캐시로 중복 비용 절감</li>
<li><strong>LLM 실패 시 fallback(한 줄)</strong>: <em>LLM 파싱이 실패하면 OCR 원문 기반 정규식/룰 기반 추출 결과로 대체하고 <code>source=&quot;ocr_rule_fallback&quot;</code>으로 반환한다.</em></li>
</ul>
<h2>서비스 전체 구조에서 OCR API의 역할 &amp; 연동 관계</h2>
<h3>역할</h3>
<ul>
<li><strong>정산/영수증 기능</strong>을 위한 <strong>OCR 게이트웨이</strong></li>
<li>Backend가 사용자 인증(JWT) 및 데이터 저장을 담당하고, OCR 서버는 “추출”에만 집중</li>
</ul>
<h3>(1) 연동 관계</h3>
<ul>
<li><strong>Backend → OCR 서버</strong>: 이미지 + user_id/request_id 전달, 결과 JSON 수신</li>
<li><strong>Backend → RDB</strong>: OCR 결과 저장(영수증/정산 도메인 테이블)</li>
</ul>
<!-- notionvc: 749bfd4d-cbd1-4b02-a796-8a225bd7163f -->