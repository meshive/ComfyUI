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
variable "COMFYUI_VERSION" {
    default = "v0.37.4"
}

# ComfyUI-Manager 커밋. 핀 사유와 `reset --hard` 방식은 Dockerfile 의 같은 이름 ARG 주석에 있다.
# 값은 검증된 base-torch2.11.0-cu130-rc0928a 이미지에 들어간 커밋이다 (2026-09-25 "update DB", v3.42).
# 올릴 때는 이 값을 바꾸고 빌드한다. Manager requirements 가 바뀌어 pip 해석이 실패하거나 마지막 잠금
# 대조가 실패하면, constraints/cu130.txt 헤더의 절차로 잠금을 다시 만든다.
variable "COMFYUI_MANAGER_SHA" {
    default = "9c29dc68a488fd56e15f152807579009d627bfef"
}

# code-server 버전. Dockerfile 이 install.sh 에 `--version` 으로 넘긴다. 예전에는 넘기지 않아 빌드하는 날의 최신
# release 가 들어왔다 — 릴리스가 거의 매주 나온다 (2026-08-10 4.132.0 ~ 09-26 4.139.1 사이 8개). code-server 는
# Pod 8080 으로 외부에 열리고 ACCESS_PASSWORD 로 비밀번호 인증을 건다 (scripts/start.sh 의 start_code_server).
# 그래서 인증·동작이 검토 없이 바뀌면 안 된다.
# 값은 라이브 base-torch2.11.0-cu130 (amd64 2091783d…, = rc0928a) 이미지에 실제로 든 버전이다 (2026-09-30 그 이미지의
# code-server 레이어에서 실측: 4.139.1, Code 1.139.1).
# Dockerfile 에는 기본값이 없다 — 설치 RUN 과 node-check 두 곳이 이 값을 쓰므로 여기 하나만 둔다.
# 올릴 때는 이 값을 바꾸고 이미지를 다시 검증한다 (ACCESS_PASSWORD 유무별 로그인 동작 포함). 빌드 마지막 node-check
# 단계가 설치된 버전을 이 값과 대조한다.
variable "CODE_SERVER_VERSION" {
    default = "4.139.1"
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
        COMFYUI_MANAGER_SHA = COMFYUI_MANAGER_SHA
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
