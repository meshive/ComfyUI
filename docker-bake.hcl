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
# Blackwell (RTX 5090, RTX PRO 5000/6000) cu130 targets ship on PyTorch nightly.
# torch 2.10.0 stable cu130 wheel ships a cuBLAS build with a known sm_120
# CUBLAS_STATUS_INVALID_VALUE bug that breaks even simple GEMMs; nightly ships a
# newer bundled cuBLAS that supports sm_120. The "nightly" sentinel triggers
# the nightly install path in the Dockerfile; the actual installed version is
# captured at build time into the constraints file.
variable "TORCH_VERSION_CU130" {
    default = "nightly"
}
variable "TORCHVISION_VERSION_CU130" {
    default = "nightly"
}

variable "EXTRA_TAG" {
    default = ""
}

function "tag" {
    params = [tag, cuda]
    result = ["${DOCKERHUB_REPO_NAME}:${tag}-torch${TORCH_VERSION}-${cuda}${EXTRA_TAG}"]
}

# Tag helper for cu130 targets that use the TORCH_VERSION_CU130 stack.
function "tag_cu130" {
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
        BASE_IMAGE          = "nvidia/cuda:13.0.0-devel-ubuntu24.04"
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
    tags = tag_cu130("base")
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
    tags = tag_cu130("slim")
}

# Blackwell-ready (cu130) workflow preset bundles. Each image ships with the
# matching auto-load extension and a pre-baked model set.
target "zit-13-0" {
    inherits = ["_cu130", "_preset_zit"]
    tags = tag_cu130("zit")
}

target "flux-13-0" {
    inherits = ["_cu130", "_preset_flux"]
    tags = tag_cu130("flux")
}

target "qwen-13-0" {
    inherits = ["_cu130", "_preset_qwen"]
    tags = tag_cu130("qwen")
}

target "ltx-13-0" {
    inherits = ["_cu130", "_preset_ltx"]
    tags = tag_cu130("ltx")
}

target "wan-13-0" {
    inherits = ["_cu130", "_preset_wan"]
    tags = tag_cu130("wan")
}
