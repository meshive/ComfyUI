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
variable "COMFYUI_VERSION" {
    default = "v0.28.3"
}

variable "EXTRA_TAG" {
    default = ""
}

function "tag" {
    params = [tag, cuda]
    result = ["${DOCKERHUB_REPO_NAME}:${tag}-torch${TORCH_VERSION}-${cuda}${EXTRA_TAG}"]
}

# Tag helper for the cu130 preset bundles. Uses the user-facing variant name as
# the bare tag, deliberately without a version suffix: these are product names
# people pull by.
#
# 이름은 반드시 DB `k8s_template.image` 가 참조하는 문자열과 일치해야 한다. 여기서 만든 태그를
# 템플릿이 안 가리키면 아무리 빌드해도 유저에게 반영되지 않는다. 실제로 zit/flux/wan 세 개가
# 그렇게 어긋나 있었고(bake 는 zit-bf16/flux1-schnell/wan22-i2v-fp8 를 만드는데 템플릿은
# *-torchnightly-cu130 을 가리켜, 그 이름의 이미지는 Docker Hub 에 한 번도 올라간 적이 없다)
# 아래에서 템플릿 쪽 이름으로 맞췄다. "torchnightly" 는 nightly 를 쓰던 시절의 흔적이라 지금은
# 부정확하지만, 이름을 바꾸려면 템플릿 image 갱신(시드+테스트+DB 3종)을 함께 해야 하므로 별건이다.
function "tag_cu130" {
    params = [variant]
    result = ["${DOCKERHUB_REPO_NAME}:${variant}${EXTRA_TAG}"]
}

# Tag helper for the cu130 base/slim images. Mirrors the cu12.x `tag` scheme
# (e.g. "base-torch2.8.0-cu128") but reads TORCH_VERSION_CU130, since the
# global TORCH_VERSION does not apply to cu130 targets. Keeping the version in
# the tag means bumping torch publishes a new tag instead of silently
# overwriting the previous one.
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

# Workflow preset bundles. Each preset installs the matching auto-load
# extension and bakes its model set into the image so startup needs no
# downloads. Composed with a _cuXXX base.
target "_preset_zit" {
    args = { BAKE_PRESET = "zit" }
}

target "_preset_flux" {
    args = { BAKE_PRESET = "flux" }
}

target "_preset_qwen" {
    args = { BAKE_PRESET = "qwen" }
}

target "_preset_ltx" {
    args = { BAKE_PRESET = "ltx" }
}

target "_preset_wan" {
    args = { BAKE_PRESET = "wan" }
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

# Blackwell-ready (cu130) workflow preset bundles. Each image ships with the
# matching auto-load extension and a pre-baked model set. The tag uses the
# user-facing model variant name. RC 빌드처럼 라이브 태그를 건드리지 않고 올리고 싶으면
# EXTRA_TAG 환경변수로 접미사를 붙인다 (예: EXTRA_TAG=-rc1 docker buildx bake --push ltx-13-0).
target "zit-13-0" {
    inherits = ["_cu130", "_preset_zit"]
    tags = tag_cu130("zit-torchnightly-cu130")
}

target "flux-13-0" {
    inherits = ["_cu130", "_preset_flux"]
    tags = tag_cu130("flux-torchnightly-cu130")
}

target "qwen-13-0" {
    inherits = ["_cu130", "_preset_qwen"]
    tags = tag_cu130("qwen-image-fp8")
}

target "ltx-13-0" {
    inherits = ["_cu130", "_preset_ltx"]
    tags = tag_cu130("ltx-2b")
}

target "wan-13-0" {
    inherits = ["_cu130", "_preset_wan"]
    tags = tag_cu130("wan-torchnightly-cu130")
}
