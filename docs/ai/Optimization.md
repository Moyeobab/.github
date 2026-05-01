## 음식점 추천
<h3>1. 사용자 행동 기반 지표</h3>

지표 | 의미
-- | --
Selection Time | 최종 선택까지 걸린 시간
Re-recommend Rate | “다시 추천” 클릭 비율
Option Scroll Depth | 몇 개 후보까지 봤는지
Abandon Rate | 추천 후 이탈


<h3>2. 시스템 추론 성능 지표</h3>

구간 | 목표
-- | --
후보 생성 | < 200ms
랭킹 계산 | < 50ms
전체 추천 | < 300~500ms


<!-- notionvc: 18edf1b0-8d96-46ca-9744-caf2204c59c2 -->

<br><br>
# 챗봇

## 1) 기존 챗봇 모델 추론 성능 지표 (Baseline)

### 🔍 선정 기준
기준 | 설명
-- | --
품질 | - Recall@K : 검색된 문서가 정담 포함 <br> - Groundedness : 답변이 근거 기반인가 <br> - Relevance : 응답 품질 및 사용자 의도 일치도
지연시간 | - TTFT : 체감 응답 속도 <br> - Generation Latency : 답변 생성 속도 <br> - End-to-End Latency : 전체 응답 시간
자원 효율/비용 | - GPU 메모리 요구량 <br> - 동시 처리량 <br> - 운영 안정성

### 📝 비교 모델 요약

항목 | Qwen2-4B-Instruct | Qwen2.5-7B-AWQ
-- | -- | --
파라미터 수 | 4B | 7B
Precision | FP16 / BF16 | INT4(AWQ)
모델 크기 | ~8 GB | ~4.5–5 GB (양자화)
KV Cache 포함 실사용 | 10–12 GB | 8–10 GB
권장 GPU | T4, L4, A10, A100 | L4, A10, A100
8GB GPU | 불안정 | 일부 가능
16GB GPU | 안정적 | 안정적
동시 세션(대략) | 6–10 | 3–6

## 📝 품질 성능 비교
### 테스트 환경/조건
- LLM Serving : vLLM
- GPU : T4에서 4B, 7B 실행
- CPU : Embedding, Reranker
- Embedding : `BAAI/bge-m3`
- Reranker : `BAAI/bge-reranker-v2-m3`


## 데이터 조건
- 임의로 생성한 20개의 식당 데이터 (A~T)
- 식당당 문서 수 : 3개
 - {ID}_info
 - {ID}_menu
 - {ID}_review
- menu/price, facility, mood, time, review, multi(연속적인 질문) 각각 20씩 총 120개의 질문

## RAG 파이프라인 조건
- Hybrid Retrieval
 - BM24 + Vector similarity
 - 가중치 : 0.45 / 0.55
- 식당 ID 필터
 - 질문에서 식당 ID(A~T) 추출
 - 해당 식당 문서만 후보로 허용

- Rerank
 - Top-N: 20
 - 최종 컨텍스트: Top-3 문서만 LLM에 전달

<br>

Metric | 4B | 7B-AWQ | 해석
-- | -- | -- | --
Recall@K | 1.000 | 1.000 | 검색 정확도 동일
Groundedness | 0.967 | 1.000 | 7B가 수치 근거, 조건 해석에서 더 안정적
Relevance | 0.844 | 0.854 | 7B가 자연스러움, 문장 완성도 약간 높음 

### 해석
- 두 모델 모두 사실성, 근거성은 비슷함.


## 📝 속도 및 지연시간 비교
Metric | 4B | 7B-AWQ | 해석
-- | -- | -- | --
Retrieval | 0.41s | 0.43s | 거의 동일
TTFT (First Token) | 0.16s | 038s | 4B가 2배 이상 빠름 → UX에 중요
Generation latency | 1.79s | 2.03s | 4B가 우위
End-to-End | 4.68s | 5.12s | 4B가 약 9% 빠름
Generated tokens | 4965 | 5264 | 4B가 비용 효율적
Rerank (top20) | 2.48s | 2.65s | 4B가 더 빠름

### 해석
**TTFT는 4B가 더 빠름 -> 스트리밍 응답, 대화형 UX에서 중요**
- RAG 구조세엇 rerank, 검색이 병목 상태.

<br>

## 최종 선택
### `Qwen/Qwen3-4B-Instruct-2507`

- RAG 품질 지표 동일
- 체감 UX에서 우수
- GPU 비용, 동시성, 스케일링에서 유리
- 운영 안정성 높음


---

<br> 

## 2) 식별된 성능 병목 요소와 원인 분석

### 관찰된 현상 (서비스 관점)
### (1) 동시 요청 시 tail latency (p95/p99) 급증
- llm 추론이 GPU 단일 자원에 묶여 있고 동시 요청이 늘어나면 실제 병렬 처리보다 대기열 증가로 이어진다.

### (2) 재요청/중복 요청으로 부하가 자기증폭
- 응답이 늦어질수록 사용자 재클릭으로 동일 요청이 다시 GPU로 들어가며 불필요한 추론 반복 발생한다.

### 구조적 병목 
### (1) Reranker 지연이 크고 동시성에서 CPU 병목
- reranker를 CPU로 topN=20 -> 2~3초

### (2) RAG 품질 후처리
- 중국어 섞임 감지 후 재시도 -> 추가 생성/처리 발생

<br>

## 3) 적용할 최적화 기법의 구체적 계획
### (1) In-flight 제한
- GPU당 동시 요청 수를 제한함
- 초기값 
 - max_inflight = 12

### (2) 동일 요청 합치기
- 키 : (user_id, normalized_question, rid) 해시
- 동일 키가 in-flight면 기존 결과 공유

### (3) Rerank 조건부 적용 + topN 축소
- rid가 파싱된 경우: rerank off 또는 topN=6

<br> 

## 4) 기대 성능지표
- Latency
 - p50: 1.5 ~ 2.5s
 - p95: 3 ~ 5s (동시 요청 상황)
- Throughput
 - 4B 기준: 안정 2~4 QPS / 피크 5~7 QPS
- Tail latency 안정성
 - p99 / p50 비율 4배 이내
- 재요청률 감소
 - 10~30% → 5% 이하



<br><br>

## OCR

## 1. 인프라 선정

### 1) 사용자 시나리오 및 요구사항

본 OCR 기능은 사용자가 영수증 이미지를 업로드한 뒤

**수 초~수십 초 내에 정산에 활용 가능한 구조화 JSON 결과를 받는 것을 목표**로 한다.

서비스 관점에서의 주요 요구사항은 다음과 같다.

- 단일 요청 기준 **복잡한 영수증도 안정적으로 처리 가능**
- p95 기준 응답 지연이 과도하게 증가하지 않을 것
- 소규모 초기 서비스 단계에서 **비용 대비 성능 효율**이 높을 것
- GPU 자원을 사용하는 AI 추론 환경을 **유연하게 교체·확장 가능**할 것


### 2) 후보 인프라 및 GPU 타입 비교

초기 성능 평가 단계에서 다음과 같은 GPU 인스턴스를 후보로 검토하였다.

- **AWS T4**
    - 장점: 접근성 높음, 비용 비교적 저렴
    - 단점: 멀티모달(Vision+Language) 추론 시 지연이 큼
        
        → 실측 기준 영수증 1장 처리 15~20초
        
- **RTX A5000**
    - 장점: 충분한 VRAM과 높은 연산 성능
    - 단점: 비용 대비 성능 효율이 낮음
- **NVIDIA L4 (RunPod)**
    - 장점:
        - T4 대비 유의미한 추론 속도 개선
        - 멀티모달 추론에 최적화된 최신 아키텍처
        - 비용 대비 성능 우수


### 3) 최종 선택: RunPod NVIDIA L4

위 비교 결과를 바탕으로,

**RunPod의 NVIDIA L4 인스턴스를 최종 선택**하였다.

- **선정 근거**
    - 동일 모델(Qwen3-VL 4B) 기준
        - T4 대비 **약 30~40% 이상 추론 시간 단축**
        - 복잡한 영수증에서도 **약 10초 내 JSON 응답 확보**
    - 초기 서비스 단계에서 요구되는
        - 성능 안정성
        - 비용 효율성
        - 운영 유연성
            
            를 균형 있게 만족
            
- **스토리지 설정**
    - 모델 가중치, 추론 캐시를 고려하여
        - **디스크 용량 100GB**로 설정
    - 대형 멀티모달 모델 가중치 및 런타임 캐시(vLLM/torch cache 등)를 안정적으로 유지하면서, 반복 실험·재처리·디버깅 과정에서도 용량 부족 없이 운영 가능하도록 구성

---

## 2. OCR 모델 성능 지표 비교 (Qwen3-VL 4B vs Gemma-3-4B Vision, NVIDIA L4 기준)

<img width="574" height="316" alt="result" src="https://github.com/user-attachments/assets/0735da26-96eb-4ce9-a136-81cfc4ddd27a" />

※ 본 평가는 다양한 난이도의 영수증 20장으로 구성된 소규모 평가셋을 기반으로 한 비교 실험 결과임

### 1) 모델 테스트 환경
<ul>
<li>
<p><strong>모델</strong>: Qwen3-VL 4B</p>
</li>
<li>
<p><strong>기능</strong>: 영수증 이미지 입력 → 텍스트/라인아이템 추출(메뉴/수량/단가/금액/총액) → JSON 응답</p>
</li>
<li>
<p><strong>입력 데이터</strong>: 실제 영수증 이미지</p>
<p>(텍스트량·항목 수·레이아웃·촬영 품질이 다양한 데이터셋)</p>
</li>
<li>
<p><strong>측정 지표</strong>:</p>
<ul>
<li>End-to-end latency (요청 → JSON 응답까지)</li>
<li>복잡 영수증 기준 worst-case 응답 시간</li>
<li>OCR 텍스트 인식 정확도 (CER / WER 기준)</li>
<li>라인아이템 추출 정확도 (메뉴/수량/단가/금액 필드 기준)</li>
<li>JSON 파싱 성공률 (Schema validation pass rate)</li>
</ul>
</li>
</ul>
<hr>
<h3>2) Baseline 1: AWS T4</h3>
<p><strong>환경</strong>: AWS GPU T4</p>
<p><strong>결과(실측)</strong>:</p>
<p>영수증 1장 처리 <strong>15~20초</strong></p>
<p><strong>해석</strong></p>
<ul>
<li>실서비스 목표 대비 큰 격차 존재</li>
<li>긴 대기시간으로 인해 사용자 체감 품질 저하 및 이탈 가능성 높음</li>
<li>동시 요청 발생 시 요청 큐가 빠르게 적체되며 <strong>tail latency(p95/p99)</strong> 가 심각하게 악화될 가능성</li>
<li>해당 환경에서는 멀티모달(Vision+Language) 추론을 안정적으로 제공하기 어렵다고 판단</li>
</ul>
<hr>
<h3>3) Baseline 2: RunPod L4</h3>
<p><strong>환경</strong>: RunPod GPU L4</p>
<p><strong>결과(관측)</strong>:</p>
<p>복잡한 영수증 1건 기준 <strong>JSON 응답까지 약 10초</strong></p>
<p><strong>해석</strong></p>
<ul>
<li>
<p>T4 대비 GPU 성능 향상으로 전체 추론 시간이 유의미하게 감소했으며,</p>
<p><strong>복잡한 영수증에서도 10초 내 응답을 안정적으로 확보</strong></p>
</li>
<li>
<p>멀티모달 OCR을 단일 모델(Qwen3-VL 4B)로 수행하는 구조임을 고려할 때,</p>
<p>현재 성능은 <strong>초기 서비스 및 실사용이 가능한 baseline</strong>으로 판단됨</p>
</li>
<li>
<p>추가로,</p>
<ul>
<li>
<p>영수증 영역 크롭 및 해상도 상한 적용 등 <strong>입력 전처리</strong></p>
</li>
<li>
<p>출력 포맷 고정 및 불필요한 생성 억제 등 <strong>추론 경로 최적화</strong></p>
<p>를 적용할 경우,<strong>복잡한 영수증 기준 응답 시간을 p95 8초 이내로 단축하는 것이 충분히 가능할 것으로 판단</strong></p>
</li>
</ul>
</li>
</ul>
<hr>
<h2>3. 식별된 성능 병목 요소와 원인 분석</h2>
<h3>1) 관찰된 현상</h3>
<ul>
<li><strong>영수증마다 처리 시간이 크게 달라짐</strong></li>
<li><strong>복잡한 영수증일수록 시간이 더 소요됨</strong>
<ul>
<li>항목 수가 많음(라인아이템 다수)</li>
<li>글자 밀도 높음, 표 형태, 할인/부가세/결제수단 정보 등 텍스트 블록 증가</li>
<li>사진 품질(기울어짐/반사/저조도/블러)에 따라 OCR 난이도 증가</li>
</ul>
</li>
</ul>
<h3>2) 병목 요소</h3>
<p><strong>입력 이미지 크기/정보량 과다 → 전처리 + 비전 인코딩 비용 증가</strong></p>
<ul>
<li>고해상도 이미지 일수록
<ul>
<li>디코딩/리사이즈 비용 증가</li>
<li>비전 인코더가 처리해야 하는 패치/토큰 수 증가</li>
</ul>
</li>
<li>영수증 외 배경/테이블/그림자/주변 물체가 많으면 “불필요한 시각 정보”가 모델 입력에 포함됨</li>
</ul>
<p><strong>복잡한 레이아웃 → 모델이 더 많은 토큰/추론 스텝을 사용</strong></p>
<ul>
<li>항목이 많으면 출력 토큰도 증가 (추론 시간이 출력 길이에 비례)</li>
<li>표/열 정렬이 흐트러진 영수증은 모델이 구조를 잡기 어려워 반복/오류 수정성 출력이 늘 수 있음</li>
</ul>
<p><strong>GPU 메모리/연산 여유 부족 또는 비효율적 실행 경로</strong></p>
<ul>
<li>T4(연산/VRAM)에서 15~20초로 길어진 것은
<ul>
<li>단순히 “모델이 느리다”가 아니라</li>
<li>해당 환경에서 <strong>비전+언어 추론이 충분히 가속되지 못했거나</strong>, 배치/커널 최적화가 부족했을 가능성</li>
</ul>
</li>
<li>L4에서 크게 빨라진 것은 “동일 코드라도 GPU 성능/메모리 대역”에 강하게 의존함을 의미</li>
</ul>
<p><strong>Tail latency 문제</strong></p>
<ul>
<li>
<p>평균이 아니라 “어려운 영수증”에서 시간이 크게 튐</p>
<p>→ 서비스 운영에서는 이 구간(p95/p99)이 UX를 망가뜨림</p>
</li>
</ul>
<hr>
<h2>4. 적용할 최적화 기법의 구체적 계획</h2>
<h3>1) 영수증 이미지 전처리: 불필요 정보 제거 + 입력 표준화</h3>
<ul>
<li>목표:
<ul>
<li>모델이 처리해야 할 “시각 토큰”과 노이즈를 줄여 <strong>추론 시간 변동 폭을 축소</strong></li>
</ul>
</li>
<li>적용 항목:
<ol>
<li><strong>해상도 상한 적용</strong>: 긴 변 기준 1000px로 리사이즈
<ul>
<li>글자 판독 가능한 최소 해상도는 유지하면서 비용을 줄임</li>
</ul>
</li>
<li><strong>영수증 영역 크롭(ROI)</strong>: 배경 제거(테이블, 손, 주변 물체)
<ul>
<li>간단한 방법: contour 기반 문서 검출/사각형 보정</li>
</ul>
</li>
<li><strong>기울어짐 보정(Deskew)</strong>: 심한 케이스만 조건부 적용</li>
</ol>
</li>
<li>기대 이유(서비스 맥락):
<ul>
<li>
<p>복잡한 영수증일수록 “정보량(텍스트/배경/레이아웃)”이 커서 시간이 늘어남</p>
<p>→ 전처리로 “모델이 봐야 할 정보”를 줄이면 <strong>복잡도에 따른 시간 증가 폭이 완화</strong>됨</p>
</li>
<li>
<p>특히 p95/p99 같은 “어려운 케이스”에 효과가 큼</p>
</li>
</ul>
</li>
</ul>
<h3>2)결과 검증 기반 조건부 2-pass 추론: 정확도 및 안정성 개선</h3>
<ul>
<li>
<p>목표:</p>
<ul>
<li>
<p>단일 추론에서 발생하는 <strong>라인아이템 누락·중복·금액 불일치·세금 필드 혼동</strong>과 같은 오류를 자동으로 보정하여</p>
<p>JSON 파싱 성공률 및 필드 단위 정확도(메뉴/수량/단가/금액)를 향상</p>
</li>
<li>
<p>평균 응답 시간 증가를 최소화하면서, <strong>복잡 영수증 기준 p95 품질을 개선</strong></p>
</li>
</ul>
</li>
<li>
<p>적용 개념:</p>
<ul>
<li>
<p>1차 추론 결과를 즉시 반환하지 않고,</p>
<p>경량 검증 로직(validator)을 통해 구조적·산술적 일관성을 검사</p>
</li>
<li>
<p>검증 실패가 감지된 경우에만,</p>
<p>동일 LLM을 활용한 수정 전용 2-pass 추론(Self-correction)을 조건부로 수행</p>
</li>
</ul>
</li>
<li>
<p>1차 결과 검증 항목:</p>
<ul>
<li><strong>Schema 검증</strong>
<ul>
<li>필수 필드 누락(items, total_amount, paid_amount 등)</li>
<li>타입 오류(숫자 필드 문자열화, 음수 금액 등)</li>
</ul>
</li>
<li><strong>산술 일관성 검증</strong>
<ul>
<li><code>sum(item.amount) == total_amount</code> 불일치</li>
<li><code>unit_price × quantity ≠ amount</code> 케이스</li>
</ul>
</li>
<li><strong>도메인 규칙 검증</strong>
<ul>
<li>과세가액/부가세/공급가 등의 요약 정보가 items에 포함된 경우</li>
</ul>
</li>
</ul>
</li>
<li>
<p>조건부 2-pass 수정 추론 방식:</p>
<ul>
<li>입력:
<ul>
<li>원본 영수증 이미지(또는 OCR 텍스트)</li>
<li>1차 추론 JSON</li>
<li>validator가 생성한 <strong>오류 요약 정보</strong></li>
</ul>
</li>
<li>출력:
<ul>
<li>자연어 설명 없이 <strong>수정된 JSON만 반환</strong></li>
<li>사전 정의된 schema 및 산술 제약을 만족하도록 강제</li>
</ul>
</li>
<li>특징:
<ul>
<li>“다시 추출”이 아닌 <strong>“오류를 만족하도록 수정”에 초점</strong></li>
<li>출력 토큰 수를 제한하여 추가 지연 및 비용 최소화</li>
</ul>
</li>
</ul>
</li>
<li>
<p>기대 효과(서비스 관점):</p>
<ul>
<li>오류가 집중되는 <strong>복잡·저품질 영수증</strong>에서 정확도 회복</li>
<li>JSON 파싱 실패로 인한 재요청/수동 처리 감소</li>
<li>평균 latency는 유지하면서, <strong>p95/p99 품질을 안정적으로 개선</strong></li>
<li>운영 단계에서 “실패 케이스만 비용을 더 쓰는 구조”로 확장성 확보</li>
</ul>
</li>
</ul>
<hr>
<h2>5. 최적화 적용 후 기대 성능 지표</h2>
<h3>1) 기대 성능 지표 요약</h3>
<ul>
<li>대상 환경: RunPod GPU L4 기준</li>
<li>모델: Qwen3-VL 4B</li>
<li>최적화 적용 범위:
<ul>
<li>입력 이미지 전처리(해상도 상한, ROI 크롭, Deskew)</li>
<li>결과 검증 기반 조건부 2-pass 추론</li>
</ul>
</li>
</ul>

지표 | Baseline | 최적화 적용 후(기대)
-- | -- | --
평균 응답 시간 | ~9초 | 6~8초
p95 응답 시간 | ~10초 | ≤ 8초
p99 응답 시간 | 10초 이상 | ≤ 8초
JSON 파싱 성공률 | 100% | 100%
라인아이템 필드 정확도 | 90.9% | 95~98%


<hr>
<h3>2) 응답 시간 및 성능 변동성(p95/p99) 개선 기대</h3>
<ul>
<li>입력 이미지 전처리를 통해
<ul>
<li>비전 인코더가 처리해야 하는 시각 토큰 수를 제한</li>
<li>영수증 외 불필요한 배경 정보를 제거</li>
</ul>
</li>
<li>그 결과,
<ul>
<li>평균 응답 시간뿐 아니라</li>
<li>*복잡·저품질 영수증에서 발생하던 tail latency(p95/p99)가 크게 완화될 것으로 기대됨</li>
</ul>
</li>
</ul>
<p>→ 서비스 관점에서는</p>
<p>“평균은 빠르지만 가끔 매우 느린 시스템”에서</p>
<p>“대부분의 요청이 예측 가능한 시간 안에 끝나는 시스템”으로의 전환을 의미</p>
<hr>
<h3>3) 처리량(Throughput) 측면의 기대 효과</h3>
<ul>
<li>단건 요청 기준 추론 시간이 단축됨에 따라,
<ul>
<li>동일 GPU 자원에서 단위 시간당 처리 가능한 요청 수 증가</li>
</ul>
</li>
<li>조건부 2-pass 구조를 적용함으로써:
<ul>
<li>전체 요청 중 일부(오류 케이스)에만 추가 추론 비용 발생</li>
<li>평균 처리량 감소 없이 정확도 개선 효과 확보</li>
</ul>
</li>
</ul>
<p><strong>기대 효과</strong></p>
<ul>
<li>단일 GPU(L4) 기준:
<ul>
<li>동시 요청 수 증가 시에도 안정적인 처리 가능</li>
<li>요청 큐 적체 및 지연 전파(ripple effect) 감소</li>
</ul>
</li>
<li>향후:
<ul>
<li>요청량 증가 시 <strong>수평 확장(GPU scale-out)</strong> 전략과의 결합 용이</li>
</ul>
</li>
</ul>
<hr>
<h3>4) 정확도·안정성 관점의 기대 효과</h3>
<ul>
<li>
<p>결과 검증 및 self-correction 구조를 통해:</p>
<ul>
<li>
<p>JSON 스키마 오류</p>
</li>
<li>
<p>금액 산술 불일치</p>
</li>
<li>
<p>세금/요약 필드 혼동</p>
<p>와 같은 <strong>실서비스에서 치명적인 오류 유형을 체계적으로 감소</strong></p>
</li>
</ul>
</li>
<li>
<p>이는 단순한 모델 정확도 향상을 넘어,</p>
<ul>
<li>
<p>재요청</p>
</li>
<li>
<p>수동 검증</p>
</li>
<li>
<p>운영 리스크</p>
<p>를 줄이는 <strong>서비스 안정성 개선 효과</strong>로 이어짐</p>
</li>
</ul>
</li>
</ul>
<!-- notionvc: fc4d7380-fbfd-4be5-8a93-3f28fc4091de -->