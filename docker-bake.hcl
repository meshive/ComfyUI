variable "DOCKERHUB_REPO_NAME" {
    default = "meshive/comfyui"
}

variable "PYTHON_VERSION" {
    default = "3.13"
}
variable "TORCH_VERSION" {
    default = "2.8.0"
}
variable "TORCHVISION_VERSION" {
    default = "0.23.0"
}
# Blackwell (RTX 5090, RTX PRO 5000/6000) cu130 targets. These used to track
# PyTorch nightly because the torch 2.10.0 stable cu130 wheel shipped a cuBLAS
# build with a known sm_120 CUBLAS_STATUS_INVALID_VALUE bug that broke even
# simple GEMMs. Stable releases past 2.10.0 are now on the cu130 index, so we
# pin instead: nightly made every rebuild a different torch, which made any
# regression impossible to reproduce.
#
# 2.11.0 is the ceiling, not the newest stable. torch/torchvision go higher
# (2.13.0 / 0.28.0) but torchaudio -- which ComfyUI's requirements.txt pulls in
# -- has no cu130 wheel above 2.11.0, and the Dockerfile installs torchaudio at
# ${TORCH_VERSION}. Raising torch past 2.11.0 therefore requires decoupling the
# torchaudio pin first. The "nightly" sentinel still works if it is ever needed
# again.
variable "TORCH_VERSION_CU130" {
    default = "2.11.0"
}
variable "TORCHVISION_VERSION_CU130" {
    default = "0.26.0"
}

# ComfyUI release tag baked into every target. Bump this to ship a newer
# ComfyUI; "master" tracks the tip instead of a release.
#
# 하한이 있는 태그: **v0.30.0 미만으로 내리면 `minimax-h3` 자산 세트의 동봉 workflow 가
# 죽는다** — H3 네이티브 노드(`comfy_extras/nodes_minimax_h3.py`, `comfy/ldm/minimax/*`)가
# v0.30.0 에서 처음 들어왔다(0.29.x 의 `comfy_api_nodes/nodes_minimax.py` 는 유료 API 노드라
# 로컬 가중치와 무관). 세트 정의는 WSB `scripts/seed_data/comfyui_specs/minimax-h3.json`.
#
# v0.28.3 → v0.31.0 (2026-08-08): requirements.txt 차이는 frontend/workflow-templates/
# embedded-docs/comfy-kitchen/comfy-aimdo 버전 bump 뿐 — 새 의존성도, torch 제약 변경도 없다.
#
# v0.31.0 → v0.37.0 (2026-09-23): 성격이 같다 — frontend 1.48.7→1.52.7,
# workflow-templates 0.11.34→0.11.66, embedded-docs 0.5.9→0.5.12, av>=16→>=17,
# comfy-kitchen 0.2.28→0.2.35, comfy-aimdo 0.4.13→0.5.5. 새 의존성 없음, torch 제약 불변.
# ⚠️ torchaudio 는 v0.37.0 requirements 에 **아직 있다**(미릴리스 master 에서만 빠졌다)
#    — 위 TORCH_VERSION_CU130 의 2.11.0 상한은 이번 bump 로 풀리지 않는다.
# COMFYUI_VERSION 은 태그 문자열에 안 들어가므로 이 bump 는 기존 태그를 덮어쓴다 —
# 즉 seed 템플릿 행 교체가 없고, 위 TORCH_VERSION bump 런북은 해당되지 않는다.
#
# v0.37.0 → v0.37.4 (2026-09-28): 패치 태그 4개(GitHub Release 는 v0.37.0 까지만 있다).
# requirements 차이는 comfyui-workflow-templates 0.11.66→0.11.69 뿐, manager_requirements 동일.
#
# v0.37.4 → v0.38.2 (2026-10-02): v0.38.0 은 모델 코드 변경(H3 VAE·Qwen Image 2.1·Flux·Wan·Krea2,
# comfy/ops.py·model_management)이 들어간 마이너 릴리스이고, v0.38.1·v0.38.2 는 유료 API 노드·템플릿뿐이다.
# requirements 차이: frontend 1.52.7→1.53.6, workflow-templates 0.11.69→0.11.74, comfy-kitchen
# 0.2.35→0.2.36, **torchaudio 제거**. manager_requirements 동일, 새 의존성 없음.
# ⚠️ torchaudio 가 ComfyUI requirements 에서 빠졌지만 Dockerfile 이 torch 와 같은 버전으로 계속 설치한다
#    (custom node 용). 위 TORCH_VERSION_CU130 의 2.11.0 상한을 풀려면 Dockerfile 쪽 torchaudio 고정부터 풀어야 한다.
# 프론트 1.53.6 에서 우리 확장이 기대는 지점(missingModel 스토어·missing-model-* data-testid·
# Comfy.Workflow.Draft.v2 키·createNewTemporary)이 그대로인 것을 프론트 소스 태그 대조로 확인했다.
# 바뀐 pip 잠금 6줄은 constraints/cu130.txt 헤더에 적었다.
#
# v0.38.2 → v0.41.2 (2026-10-16): FLUX 3 Image Klein 네이티브 지원(v0.41.0, `Flux3LayoutPrompt`·
# `ReferenceMultiLatent`·CLIPLoader type `flux3`)이 이유다. **v0.41.2 미만으로 내리면 WSB `flux3-klein`
# 자산 세트의 동봉 workflow 가 맞지 않는다** — v0.41.0 은 템플릿 0.11.84(출시 당일 판, 모델 파일명이 다름),
# v0.41.2 가 세트에 동봉한 판과 같은 0.11.86 을 고정한다. v0.41.1·v0.41.2 는 템플릿·유료 API 노드뿐이다.
# requirements 차이: frontend 1.53.6→1.55.17, workflow-templates 0.11.74→0.11.86, embedded-docs
# 0.5.12→0.5.14, comfy-kitchen 0.2.36→0.2.37, comfy-aimdo 0.5.5→0.5.6. manager_requirements 동일, 새 의존성 없음.
# 프론트 1.55.17 에서 우리 확장이 기대는 지점(missingModel 스토어·missing-model-* data-testid·
# Comfy.Workflow.Draft.v2 키·createNewTemporary·Comfy.TutorialCompleted 시작 분기)이 그대로인 것을 프론트 소스
# 태그 대조로 확인했다. missingModel 스토어에 표시용 visibleMissingModelCandidates(경고 끄기 설정)가 생겼지만
# 우리가 읽는 missingModelCandidates 는 그대로이고, 행 컴포넌트 MissingModelRow.vue 는 바뀌지 않았다.
# 바뀐 pip 잠금 8줄은 constraints/cu130.txt 헤더에 적었다.
#
# v0.41.2 → v0.42.1 (2026-10-21): MOSS-Image 네이티브 지원(v0.42.0, ComfyUI#17095·#17099 — CLIPLoader type
# `moss_image`·`MOSSImageLayoutPrompt`)이 이유다. **v0.42.0 미만으로 내리면 WSB `moss-image` 자산 세트가
# 열리지 않는다.** v0.42.1 은 MOSS 템플릿 실행 중 크래시 수정(#17169 TextGenerate 정리·#17178)이 더 들어간 판이다.
# 2026-10-18 rc1018a 는 이 값을 master `c06bf5f5` 로 덮어써 빌드했고 레포에는 남기지 않았다. v0.42.1 은 그 커밋을
# 포함한다(그 뒤 10커밋). requirements 차이: frontend 1.55.17→1.55.18, workflow-templates 0.11.86→0.11.89,
# comfy-kitchen 0.2.37→0.2.39. manager_requirements 동일, 새 의존성 없음. 프론트 1.55.18 은 billing 백포트 1건
# (#21222)과 locale 뿐이라 우리 확장이 기대는 지점은 그대로다.
# ⚠️ workflow-templates 0.11.89 의 FLUX 3 Klein 템플릿 4개는 새 하이픈 파일명(`flux3-image-klein-int8-convrot`
#    등, workflow_templates#1353)을 가리킨다. WSB `flux3-klein` 세트는 0.11.86 판(밑줄 이름)이다. 세트에 동봉한
#    workflow 는 맞지만, 템플릿 창에서 내장 Klein 템플릿을 열면 모델 누락으로 보인다(rc1018a 부터 이미 같은 상태).
#
# v0.42.1 → v0.44.1 (2026-11-06): 최신 GitHub Release 는 v0.44.0(2026-11-04)이다. v0.44.1(2026-11-06, 49b61c3c)은
# release/v0.44 브랜치에 찍힌 패치 태그로 v0.44.0 의 후손이고 GitHub Release 는 없다. v0.44.1 을 쓰는 이유는 최신
# 태그라서다 — v0.44.0 과의 차이는 API 파트너 노드(comfy_api_nodes 의 Pika·Kling·Gemini·OpenAI·Qwen·Tencent HY LLM,
# node_id 는 추가만)와 requirements 의 workflow-templates 0.11.101→0.11.103 뿐이다. core·CLI 인자·
# manager_requirements.txt 는 v0.44.0 과 같다. 시드 workflow 의 출처 템플릿 28개 중 0.11.101→0.11.103 에서 바뀐 것은
# MOSS 2개(t2i·bboxes)와 qwen_image_edit_2509 뿐이고, 그것도 MarkdownNote 의 링크(ModelScope 저장소·입력 이미지)만
# 더해졌다 — 모델·노드·위젯은 같고, 시드 동봉 workflow 는 바이트 고정이라 영향이 없다.
# v0.42.2~v0.42.5·v0.43.1·v0.43.2 도 사이드 브랜치에만 찍힌 패치 태그라 v0.44.0 의 조상이 아니지만, 그 커밋의 PR 은
# 전부 v0.44.0 에 들어 있다.
# requirements 차이(v0.42.1 → v0.44.1): frontend 1.55.18→1.57.6, workflow-templates 0.11.89→0.11.103, embedded-docs
# 0.5.14→0.5.16, comfy-kitchen 0.2.39→0.2.40, comfy-aimdo 0.5.6→0.6.0, `Pillow`→`Pillow>=10.1.0`(하한만 — 잠긴
# 12.3.0 이 만족). 새 의존성 없음, torch 줄 그대로. v0.44.0 이 kitchen 의 새 함수(group_norm_stats3d)와 aimdo 의 새 API
# (write_device_to_file)를 부르므로 두 패키지는 짝을 맞춰야 한다. manager_requirements.txt 는 여전히
# comfyui_manager==4.2.2 지만 이 이미지는 그 파일을 쓰지 않는다(아래 COMFYUI_MANAGER_VERSION). 새로 생긴
# agent_requirements.txt 는 `--enable-agent` 일 때만 쓰여 깔지 않는다. CLI 인자는 `--enable-agent`·
# `--disable-product-tips` 추가뿐이고 삭제된 node_id 도 없다. 바뀐 pip 잠금 줄은 constraints/cu130.txt 헤더에 적었다.
# ⚠️ 같은 seed 라도 결과가 달라지는 세트가 있다 (예상된 변화):
#    - Flux2 VAE(헤더에 `bn.running_mean` 이 있는 VAE)가 kitchen 융합 경로를 타고(#17196) 기본 작업 dtype 이
#      fp16 우선이 된다(RTX 5090 에서 bf16→fp16) — flux2-dev·flux2-klein-4b·flux3-klein·moss-image. VAEComputeDtype
#      노드나 `--bf16-vae` 로 dtype 은 되돌릴 수 있지만 융합 경로는 남아 v0.42.1 과 비트 단위로 같아지지 않는다.
#    - TextGenerate 의 top-p 경계 수정(#17221)과 MTP auto 의 tree 조정(#17273) — sampling 을 켠 TextGenerate
#      (moss-image·qwen-image-2.1 t2i/edit·krea2-turbo)와 TextGenerateLTX2Prompt(ltx-2.5)의 프롬프트 확장 결과가
#      달라진다. flux3-klein 은 top_k 1·mtp off 라 영향이 없다.
# TextGenerate 는 TextGenerateV2(#17492)가 생기며 "Generate Text (DEPRECATED)"(is_deprecated) 로 남는다. 등록된
# 노드라 자동 교체는 없고 표시만 바뀐다 — 시드 workflow 6개가 이 노드를 쓴다.
# 프론트 1.57.6 에서 우리 확장이 기대는 지점(missingModel 스토어·missing-model-* data-testid·Comfy.Workflow.Draft.v2
# 키·createNewTemporary·Comfy.TutorialCompleted 시작 분기·actionBarButtons)이 그대로인 것을 프론트 소스 태그 대조로
# 확인했다. 달라진 점: toast 가 design-system toast 로 바뀌고 extensionManager.toast.add 는 레거시 shim 으로 남는다
# (동작함), 노드 properties.models 의 `directory: null` 항목을 프론트가 버린다(zDeclaredModelFile). 또 client_id 없는
# /prompt 를 한 번 받으면 유저 폴더에 used_headlessly 표지가 생기고 run bar 에 'Deploy to Comfy API' 버튼이 뜬다
# (서버 플래그 deploy_to_cloud — `--feature-flag` 로 못 끈다). 이 버튼은 손대지 않았다. 기동 로그의 Comfy Org 제품 안내
# 줄(product tips)은 Dockerfile 런타임 ENV 의 COMFYUI_DISABLE_PRODUCT_TIPS=1 로 끈다.
#
# v0.44.1 → v0.45.1 (2026-11-11): MiniMax-H3-Image 네이티브 지원(v0.45.0, ComfyUI#17655 — `MiniMaxH3ImageConditioning`,
# comfy/ldm/minimax 의 model·vae·sampling)이 이유다. **v0.45.0 미만으로 내리면 WSB `minimax-h3-image` 자산 세트의 동봉
# workflow 가 열리지 않는다**(2026-11-11 기준 is_active false). v0.45.1(2026-11-10, 02457b8c)은 v0.45.0(989d93d0, GitHub
# Release)의 후손 패치 태그이고, 차이는 API 파트너 노드(LTX AlphaGen·Reframe·SDR to HDR·Upscale, MiniMax H3 Image API)와
# workflow-templates 0.11.105→0.11.106 뿐이다. 0.11.106 의 H3-Image 템플릿 2개는 세트 동봉 판과 바이트가 같다.
# master 의 #17675(CreateVideo chroma_subsampling 에 "none" 복구)는 v0.45.1 에 없다 — 시드 workflow 는 그 위젯을 쓰지 않는다.
# requirements 차이(v0.44.1 → v0.45.1): frontend 1.57.6→1.58.5, workflow-templates 0.11.103→0.11.106, comfy-kitchen
# 0.2.40→0.2.41. 새 의존성 없음, torch 줄 그대로. manager_requirements.txt 는 같고(comfyui_manager==4.2.2), agent_requirements.txt
# 는 comfy-agent 의 버전 표기만 빠졌다(깔지 않는다). CLI 인자는 같고 삭제된 node_id 도 없다(추가 22개).
# ⚠️ 결과가 달라질 수 있어 생성 회귀가 필요한 세트:
#    - Qwen 3.x 경로 변경(#17361 병렬 Linear 가중치 합치기·#17625·#17620 fp8 텍스트 생성 크래시 수정·#17582 영상 입력) —
#      Qwen3.5 로 TextGenerate 를 돌리는 flux3-klein·moss-image·qwen-image-2.1·minimax-h3-image.
#    - #17655 가 comfy/ldm/minimax/model.py·vae.py 를 고쳤다 — minimax-h3(영상).
#    - #17635(greedy 디코딩에도 반복·존재 패널티 적용)은 시드 workflow 의 TextGenerate 11개가 전부 sampling on 이라 해당 없다.
# 프론트 1.58.5 에서 우리 확장이 기대는 지점(missingModel 스토어·missing-model-download/-all/-gated-access data-testid·
# Comfy.Workflow.Draft.v2 키·createNewTemporary·loadGraphData 시그니처·workspaceStore 의 toast·setting·actionBarButtons·
# Comfy.TutorialCompleted)이 그대로인 것을 프론트 소스 태그 대조로 확인했다. 바뀐 점: 누락 모델 행·카드는 클래스만 바뀌었고,
# 테마 변수 --warning-/--success-/--destructive-background 가 없어지고 나머지 옛 변수는 _deprecated-aliases.css 로 옮겨졌다 —
# ComfyUI-MeshiveInjection v1.4.4 가 이미 대체값을 둔다. 시작 경로에 URL 의 폴더 workflow 열기(useFolderWorkflowsUrlLoader)가
# 생겼지만 그 파라미터가 있을 때만 탄다.
variable "COMFYUI_VERSION" {
    default = "v0.45.1"
}

# 내장 ComfyUI-Manager(pip 패키지 comfyui_manager) 버전. Dockerfile 이 ComfyUI 와 같은 RUN 에서
# `comfyui_manager==<이 값>` 으로 깔고, post_start.sh 가 `--enable-manager` 로 켠다.
#
# 2026-11-06 전에는 레거시 ComfyUI-Manager v3.42 를 custom node 로 clone 했다(COMFYUI_MANAGER_SHA 9c29dc68,
# rc0928a 검증 커밋). 지금 ComfyUI 는 Manager 를 이 pip 패키지로 내장한다. `--enable-manager` 로 띄우면 이름에
# 'comfyui-manager' 가 든 레거시 사본은 폴더 이름만으로 로드가 막힌다(comfyui_manager.should_be_disabled, 로그는
# INFO 'Blocked by policy' 한 줄) — 유저 볼륨에 남은 옛 사본도 마찬가지다.
#
# **4.2.2(ComfyUI v0.45.1 의 manager_requirements.txt 고정값, v0.44.0 부터 같다)가 아니라 4.3 인 이유:**
#   - Pod 의 ComfyUI 는 `--listen`(0.0.0.0,::) 이라 Manager 가 비-loopback 으로 본다. 4.2.2 새 UI 의 노드 설치는 맨 앞
#     'middle+' 검사에서 network_mode=personal_cloud 가 아니면 **전부** 막힌다(glob/manager_server.py do_install).
#     4.3 은 stable CNR 설치만 'middle' 로 내려 허용한다. nightly 설치·Registry 에 없는(git) 노드 설치, update all,
#     스냅샷 복원은 4.3 도 'middle+' 다. v3.42 는 update all·스냅샷 복원을 'middle' 로, nightly·git 노드 설치를 노드 DB 기준
#     위험도로 허용했다. 같은 수준으로 쓰려고 post_start.sh 와 옛 경로 shim 이 /seed_manager_config.py 로 config.ini 에
#     network_mode=personal_cloud 를 시드한다 (Git URL 직접 설치·pip 설치는 allow_* 플래그가 따로 필요하고 새 UI 에는 그
#     화면이 없다).
#   - 보안 수정 #3297(레거시 UI HTML/URL 주입 방지, 관리자 설정 보존)·#3299(비-loopback 리스너의 flagged CNR 설치 제한)가
#     4.3 에만 있다. v3.42 에 이미 든 #3296·#3298 의 v4 판이라, 4.2.2 로 가면 지금보다 보안 수정이 빠진다.
#   - upstream 의 핀 상향 PR(Comfy-Org/ComfyUI#16410, 4.2.2→4.3)은 아직 머지되지 않았다(2026-11-06 OPEN).
# 4.3 의존성은 4.2.2 와 같고 packaging·nh3>=0.3.7 만 더한다 — 전부 잠금에 이미 있다.
# ComfyUI 는 Manager 버전을 검사하지 않는다(main.py 는 find_spec('comfyui_manager') 만 본다).
# 올릴 때는 이 값과 constraints/cu130.txt 의 comfyui-manager 줄을 같이 바꾸고 이미지를 다시 검증한다.
variable "COMFYUI_MANAGER_VERSION" {
    default = "4.3"
}

# code-server 버전. Dockerfile 이 install.sh 에 `--version` 으로 넘긴다. 예전에는 넘기지 않아 빌드하는 날의 최신
# release 가 들어왔다 — 릴리스가 거의 매주 나온다 (2026-08-10 4.132.0 ~ 09-26 4.139.1 사이 8개). code-server 는
# Pod 8080 으로 외부에 열리고 ACCESS_PASSWORD 로 비밀번호 인증을 건다 (scripts/start.sh 의 start_code_server).
# 그래서 인증·동작이 검토 없이 바뀌면 안 된다.
# 처음 고정한 4.139.1 은 라이브 base-torch2.11.0-cu130 (amd64 2091783d…, = rc0928a) 이미지에 실제로 든 버전이었다
# (2026-09-30 그 이미지의 code-server 레이어에서 실측: 4.139.1, Code 1.139.1).
#
# 4.139.1 → 4.145.0 (2026-11-06): 사이 릴리스 6개(4.140.0~4.145.0). 올린 이유는 보안 수정이다 — 8080 이 Pod 밖으로 열린다.
#   - 4.141.1: 번들 Node.js 를 24.22.1 로 올려 Brotli 디코더 원격 코드 실행 버그(CVE-2026-111497)를 고쳤고, 압축된
#     요청 본문(Content-Encoding br·gzip·deflate)은 풀지 않고 거부한다.
#   - 4.145.0: 내장 프록시로 가는 웹소켓 요청에서도 code-server 쿠키를 지우고(HTTP 요청은 이미 지웠다), 쿠키에 HttpOnly 를
#     붙여 프록시된 앱의 JS 가 쿠키를 읽지 못하게 했다.
# 동작 변경: 4.141.1 부터 `--flag=false` 형태와 설정 파일의 불리언 false 가 실제로 적용된다(start.sh 는 이 형태를 안 쓴다).
# 4.144.0 은 웹소켓 origin 검사에서 host 에 포트가 없으면 X-Forwarded-Port 로 폴백하고 기본 포트(:443)를 같게 본다 —
# 템플릿은 8080 직결이지만 이미지 nginx(8081)는 X-Forwarded-Port 를 붙이므로 그 경로의 터미널·에디터 WS 도 확인한다.
# Dockerfile 에는 기본값이 없다 — 설치 RUN 과 node-check 두 곳이 이 값을 쓰므로 여기 하나만 둔다.
# 올릴 때는 이 값을 바꾸고 이미지를 다시 검증한다 (ACCESS_PASSWORD 유무별 로그인 동작 포함). 빌드 마지막 node-check
# 단계가 설치된 버전을 이 값과 대조한다.
variable "CODE_SERVER_VERSION" {
    default = "4.145.0"
}

# ⚠️ **로컬 검증 전용이다. 이걸 붙인 태그를 릴리즈로 push 하지 말 것.**
#
# 접미사를 붙여 라이브 태그를 안 건드리고 빌드하려는 의도였는데, 실제로는 그 접미사가
# **정식 태그로 승격**되곤 했다(-rc1 → -r2 → -r3). 플랫폼 seed 의 upsert 키가
# (namespace, name, image) 라서 이미지 문자열이 바뀌면 **새 템플릿 행**이 생기고, 추천
# 연결(template_open_asset)은 구행에만 남아 신행이 빈 채로 카탈로그에 뜬다
# (2026-08-05 real 장애). 2026-08-06 에 base 2종을 plain 으로 되돌려 그 축을 닫았다.
#
# 로컬에서 확인만 하고 버릴 이미지에 쓴다. 릴리즈는 접미사 없는 태그로 push 하고,
# 그 바이트가 정식이다.
variable "EXTRA_TAG" {
    default = ""
}

function "tag" {
    params = [tag, cuda]
    result = ["${DOCKERHUB_REPO_NAME}:${tag}-torch${TORCH_VERSION}-${cuda}${EXTRA_TAG}"]
}

function "tag_cu130_base" {
    params = [name]
    result = ["${DOCKERHUB_REPO_NAME}:${name}-torch${TORCH_VERSION_CU130}-cu130${EXTRA_TAG}"]
}

target "_common" {
    dockerfile = "Dockerfile"
    context = "."
    args = {
        PYTHON_VERSION     = PYTHON_VERSION
        TORCH_VERSION      = TORCH_VERSION
        TORCHVISION_VERSION = TORCHVISION_VERSION
        COMFYUI_VERSION    = COMFYUI_VERSION
        COMFYUI_MANAGER_VERSION = COMFYUI_MANAGER_VERSION
        CODE_SERVER_VERSION = CODE_SERVER_VERSION
    }
}

target "_cu124" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:12.4.1-devel-ubuntu22.04"
        CUDA_VERSION       = "cu124"
    }
}

target "_cu125" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:12.5.1-devel-ubuntu24.04"
        CUDA_VERSION       = "cu125"
    }
}

target "_cu126" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:12.6.3-devel-ubuntu24.04"
        CUDA_VERSION       = "cu126"
    }
}

target "_cu128" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:12.8.1-devel-ubuntu24.04"
        CUDA_VERSION       = "cu128"
    }
}

target "_cu129" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE         = "nvidia/cuda:12.9.1-devel-ubuntu24.04"
        CUDA_VERSION       = "cu129"
    }
}

target "_cu130" {
    inherits = ["_common"]
    args = {
        BASE_IMAGE          = "nvidia/cuda:13.0.3-devel-ubuntu24.04"
        CUDA_VERSION        = "cu130"
        TORCH_VERSION       = TORCH_VERSION_CU130
        TORCHVISION_VERSION = TORCHVISION_VERSION_CU130
        # pip 잠금 두 파일 (기반 RUN 용 / 그 아래 전체). 사유·재생성 절차는 각 파일 헤더, 둘로 나눈
        # 이유는 Dockerfile 의 PIP_BASE_LOCK_FILE 주석. 다른 타깃은 레거시라 잠그지 않는다
        # (Dockerfile 기본값 constraints/none.txt).
        PIP_BASE_LOCK_FILE  = "constraints/cu130-base.txt"
        PIP_LOCK_FILE       = "constraints/cu130.txt"
    }
}

target "_no_custom_nodes" {
    args = {
        SKIP_CUSTOM_NODES = "1"
    }
}

target "base-12-4" {
    inherits = ["_cu124"]
    tags = tag("base", "cu124")
}

target "base-12-5" {
    inherits = ["_cu125"]
    tags = tag("base", "cu125")
}

target "base-12-6" {
    inherits = ["_cu126"]
    tags = tag("base", "cu126")
}

target "base-12-8" {
    inherits = ["_cu128"]
    tags = tag("base", "cu128")
}

target "base-12-9" {
    inherits = ["_cu129"]
    tags = tag("base", "cu129")
}

target "base-13-0" {
    inherits = ["_cu130"]
    tags = tag_cu130_base("base")
}

target "slim-12-4" {
    inherits = ["_cu124", "_no_custom_nodes"]
    tags = tag("slim", "cu124")
}

target "slim-12-5" {
    inherits = ["_cu125", "_no_custom_nodes"]
    tags = tag("slim", "cu125")
}

target "slim-12-6" {
    inherits = ["_cu126", "_no_custom_nodes"]
    tags = tag("slim", "cu126")
}

target "slim-12-8" {
    inherits = ["_cu128", "_no_custom_nodes"]
    tags = tag("slim", "cu128")
}

target "slim-12-9" {
    inherits = ["_cu129", "_no_custom_nodes"]
    tags = tag("slim", "cu129")
}

target "slim-13-0" {
    inherits = ["_cu130", "_no_custom_nodes"]
    tags = tag_cu130_base("slim")
}
