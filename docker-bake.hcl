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
variable "COMFYUI_VERSION" {
    default = "v0.37.0"
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
