# 참고 문서: 벡터 DB 선택 (pgvector vs Qdrant)

> 이 문서는 벡터 검색 기능 구현 시 PostgreSQL pgvector와 Qdrant 중 선택 근거를 정리한 참고 자료입니다.

---

## 배경

MVP 단계에서 벡터 검색 기능이 필요할 때, 별도의 벡터 DB(Qdrant)를 추가할지 기존 PostgreSQL에 pgvector 확장을 사용할지 검토.

---

## 비교표

| 항목 | pgvector (PostgreSQL) | Qdrant |
|------|----------------------|--------|
| **설치** | `CREATE EXTENSION vector;` | 별도 서비스 실행 |
| **벡터 검색** | ✅ 지원 (HNSW, IVFFlat) | ✅ 지원 (HNSW) |
| **필터링 + 벡터 검색** | ✅ SQL WHERE + 벡터 검색 | ✅ 지원 |
| **최대 차원** | 2,000 (v0.5.0+) | 65,535 |
| **성능 (10만 벡터 이하)** | 충분 | 약간 빠름 |
| **성능 (100만 벡터 이상)** | 느려질 수 있음 | 최적화됨 |
| **관리 포인트** | 없음 (기존 DB 활용) | 추가 서비스 |
| **메모리 사용** | PostgreSQL과 공유 | 별도 1~2GB |
| **백업/복구** | pg_dump로 통합 | 별도 관리 필요 |
| **트랜잭션** | ✅ ACID 보장 | ❌ 별도 시스템 |

---

## pgvector가 적합한 경우

- 벡터 10만 개 이하
- 임베딩 차원 1,536 이하 (OpenAI ada-002, text-embedding-3-small 등)
- 초당 검색 요청 10건 이하
- 관계형 데이터와 벡터를 함께 조회하는 경우
- 관리 포인트를 최소화하고 싶은 경우

---

## Qdrant가 필요한 경우

- 벡터 100만 개 이상
- 실시간 고빈도 검색 (초당 100건 이상)
- 복잡한 벡터 연산 (멀티벡터, 희소벡터, 양자화 등)
- 벡터 전용 고급 기능 필요 (페이로드 인덱싱, 샤딩 등)

---

## MVP 단계 권장: pgvector

**선택 이유:**

1. **관리 포인트 감소**
   - Qdrant 서비스 추가 불필요
   - EC2에서 관리할 프로세스 1개 감소

2. **리소스 절약**
   - Qdrant가 사용하던 메모리 1~2GB 절약
   - 해당 리소스를 PostgreSQL, Spring Boot에 활용 가능

3. **운영 단순화**
   - 백업: `pg_dump` 하나로 관계형 데이터 + 벡터 데이터 통합 백업
   - 복구: 단일 복구 절차
   - 모니터링: PostgreSQL만 모니터링

4. **트랜잭션 일관성**
   - 관계형 데이터와 벡터 데이터가 같은 트랜잭션에서 처리
   - 데이터 정합성 보장 용이

5. **확장 경로**
   - 트래픽 증가 시 Qdrant로 마이그레이션 가능
   - pgvector에서 벡터 추출 → Qdrant로 이관하는 스크립트 작성 용이

---

## pgvector 사용 예시

### 설치

```sql
-- PostgreSQL 16+ 기준
CREATE EXTENSION IF NOT EXISTS vector;
```

### 테이블 생성

```sql
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536)  -- OpenAI ada-002 차원
);

-- HNSW 인덱스 생성 (권장)
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

### 유사도 검색

```sql
-- 코사인 유사도 기준 상위 5개
SELECT id, content, 1 - (embedding <=> '[0.1, 0.2, ...]'::vector) AS similarity
FROM documents
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 5;
```

### 필터링 + 벡터 검색

```sql
-- 특정 조건 + 벡터 검색 조합
SELECT id, content
FROM documents
WHERE category = 'tech'
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 5;
```

---

## 스케일업 기준 (Qdrant 전환 검토)

다음 조건 중 하나라도 충족 시 Qdrant 전환 검토:

- [ ] 벡터 개수 50만 개 이상
- [ ] 벡터 검색 응답 시간 500ms 초과 지속
- [ ] 초당 검색 요청 50건 이상
- [ ] 멀티벡터, 희소벡터 등 고급 기능 필요

---

## 참고 링크

- [pgvector GitHub](https://github.com/pgvector/pgvector)
- [pgvector 성능 벤치마크](https://github.com/pgvector/pgvector#performance)
- [Qdrant 공식 문서](https://qdrant.tech/documentation/)
- [PostgreSQL 16 + pgvector 가이드](https://www.postgresql.org/about/news/pgvector-050-released-2712/)
