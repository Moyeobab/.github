# 참고 문서: RunPod vLLM 배포 방식 상세

> 이 문서는 RunPod Serverless에서 vLLM을 배포하는 다양한 방식을 상세히 설명합니다.
> 본문에서는 방식 1(vLLM Worker)만 사용하며, 향후 커스텀 로직이 필요할 때 참고용으로 활용합니다.

---

## 배포 방식 비교

| 항목        | 방식 1 (vLLM Worker)   | 방식 2 (커스텀 Handler) | 방식 3 (FastAPI)   |
| ----------- | ---------------------- | ----------------------- | ------------------ |
| 설정 난이도 | 쉬움                   | 중간                    | 어려움             |
| 커스텀 로직 | 불가                   | 가능                    | 자유로움           |
| 콜드 스타트 | 빠름 (캐시됨)          | 느림 (모델 다운로드)    | 느림               |
| 유지보수    | RunPod 관리            | 직접 관리               | 직접 관리          |
| 추천 상황   | MVP, 빠른 테스트       | 전처리/후처리 필요      | 복잡한 API 구조    |

**현재 권장:** 방식 1 (MVP 단계에서 빠르게 시작, 필요 시 방식 2로 전환)

---

## 방식 1: RunPod vLLM Worker (OpenAI 호환) - 권장

RunPod Hub의 사전 빌드된 vLLM Worker 사용. 설정만으로 바로 배포 가능.

| 구성     | 설명                                                              |
| -------- | ----------------------------------------------------------------- |
| 흐름     | Spring Boot → HTTP → RunPod Endpoint → vLLM Worker (RunPod 관리)  |
| API 형식 | OpenAI 호환 (base URL만 변경)                                     |

**배포 절차:**
1. RunPod Console → Serverless → vLLM Worker 선택
2. Model: `Qwen/Qwen2.5-7B-Instruct` 입력
3. Advanced 설정: `MAX_MODEL_LEN`: 8192, `GPU_MEMORY_UTILIZATION`: 0.9
4. GPU 선택: L4 (24GB)
5. Create Endpoint → Endpoint ID 발급

**장점:** 설정 간단, 관리 불필요, 바로 사용 가능
**단점:** 커스텀 로직 추가 어려움

---

## 방식 2: 커스텀 Handler (직접 vLLM 제어)

Docker 이미지에 vLLM 직접 설치하여 RunPod에 배포. 전처리/후처리 로직 자유롭게 추가 가능.

| 구성      | 설명                                                                    |
| --------- | ----------------------------------------------------------------------- |
| 흐름      | Spring Boot → HTTP → RunPod Endpoint → 커스텀 Docker (vLLM 직접 실행)   |
| 필요 파일 | handler.py (runpod SDK + vLLM), Dockerfile                              |

**배포 절차:**
1. handler.py + Dockerfile 작성
2. Docker 이미지 빌드 및 Docker Hub 푸시
3. RunPod Console → Serverless → New Endpoint
4. Docker Image URL 입력
5. GPU 선택 → Create Endpoint

**장점:** 전처리/후처리 자유, vLLM 파라미터 완전 제어
**단점:** Docker 이미지 빌드/관리 필요

### 커스텀 Handler 배포 상세 절차

| 단계 | 작업 내용             | 담당자             | 상세 절차                                          | 소요 시간 | 비고               |
| ---- | --------------------- | ------------------ | -------------------------------------------------- | --------- | ------------------ |
| 1    | handler.py 작성       | AI 개발자          | runpod SDK + vLLM 로딩 코드 작성                   | 30분      | 모델 전역 로딩     |
| 2    | Dockerfile 작성       | AI 개발자 + DevOps | AI: 모델/패키지 요구사항, DevOps: Docker 최적화    | 20분      | 협업               |
| 3    | Docker 이미지 빌드    | DevOps             | `docker build -t {dockerhub}/vllm-worker:v1 .`     | 30분      | 모델 포함 시 ~20GB |
| 4    | Docker Hub 푸시       | DevOps             | `docker push {dockerhub}/vllm-worker:v1`           | 20분      | 네트워크 속도 의존 |
| 5    | RunPod 콘솔 접속      | DevOps             | Serverless → New Endpoint                          | 1분       |                    |
| 6    | Docker 이미지 설정    | DevOps             | Container Image에 Docker Hub URL 입력              | 2분       |                    |
| 7    | GPU/Worker 설정       | DevOps             | L4 선택, Min: 0, Max: 2                            | 2분       |                    |
| 8    | Endpoint 생성         | DevOps             | Create Endpoint → Endpoint ID 발급                 | 2분       |                    |
| 9    | Backend 환경변수 설정 | DevOps             | EC2에 Endpoint URL + API Key 환경변수 설정         | 3분       | .env 또는 systemd  |
| 10   | Backend 재시작        | DevOps             | `sudo systemctl restart spring-boot`               | 2분       |                    |
| 11   | 연동 테스트           | DevOps             | API 호출 테스트                                    | 3분       |                    |

**총 소요 시간:** 약 2시간 (최초 배포 시)
**업데이트 배포:** 약 1시간 (Docker 이미지 재빌드 + 푸시)

### handler.py 기본 구조

```python
import runpod
from vllm import LLM, SamplingParams

# Worker 시작 시 1회 로딩 (전역)
llm = LLM(model="/models/qwen", gpu_memory_utilization=0.9)

def handler(event):
    prompt = event["input"]["prompt"]
    params = SamplingParams(temperature=0.7, max_tokens=512)
    output = llm.generate([prompt], params)
    return {"response": output[0].outputs[0].text}

runpod.serverless.start({"handler": handler})
```

### Dockerfile 예시

```dockerfile
FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0

# 모델 다운로드 (빌드 시 1회)
RUN pip install vllm runpod huggingface_hub
RUN python -c "from huggingface_hub import snapshot_download; \
    snapshot_download('Qwen/Qwen2.5-7B-Instruct', local_dir='/models/qwen')"

COPY handler.py /handler.py
CMD ["python", "/handler.py"]
```

---

## 방식 3: FastAPI 래퍼 (복잡한 API 구조)

FastAPI로 REST API 구성 후 RunPod에 배포. 여러 엔드포인트, 복잡한 라우팅 필요 시.

| 구성      | 설명                                                                     |
| --------- | ------------------------------------------------------------------------ |
| 흐름      | Spring Boot → HTTP → RunPod Endpoint → FastAPI + vLLM                    |
| 필요 파일 | app.py (FastAPI + vLLM), handler.py (runpod 래핑), Dockerfile            |

**배포 절차:**
1. FastAPI 앱 + handler.py + Dockerfile 작성
2. Docker 이미지 빌드 및 Docker Hub 푸시
3. RunPod Console → Serverless → New Endpoint
4. Docker Image URL 입력
5. GPU 선택 → Create Endpoint

**장점:** 복잡한 API 구조, 여러 기능 통합 가능
**단점:** 구조 복잡, 관리 포인트 증가

---

## Spring Boot 연동 설정

```properties
# application.properties
runpod.endpoint.url=https://api.runpod.ai/v2/{ENDPOINT_ID}/openai/v1
runpod.api.key=${RUNPOD_API_KEY}
```

---

## 참고 링크

- [RunPod Serverless 문서](https://docs.runpod.io/serverless)
- [vLLM 공식 문서](https://docs.vllm.ai/)
- [RunPod vLLM Worker](https://github.com/runpod-workers/worker-vllm)
