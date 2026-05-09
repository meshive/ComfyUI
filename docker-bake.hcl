variable "DOCKERHUB_REPO_NAME" {
    default = "meshive/comfyui"
}

variable "PYTHON_VERSION" {
    default = "3.12"
}
variable "TORCH_VERSION" {
    default = "2.8.0"
}
variable "TORCHVISION_VERSION" {
    default = "0.23.0"
}
variable "TORCH_VERSION_CU130" {
    default = "2.10.0"
}
variable "TORCHVISION_VERSION_CU130" {
    default = "0.25.0"
}

variable "EXTRA_TAG" {
    default = ""
}

function "tag" {
    params = [tag, cuda]
    result = ["${DOCKERHUB_REPO_NAME}:${tag}-torch${TORCH_VERSION}-${cuda}${EXTRA_TAG}"]
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
        BASE_IMAGE         = "nvidia/cuda:13.0.0-devel-ubuntu24.04"
        CUDA_VERSION       = "cu130"
        TORCH_VERSION      = TORCH_VERSION_CU130
        TORCHVISION_VERSION = TORCHVISION_VERSION_CU130
    }
}

target "_no_custom_nodes" {
    args = {
        SKIP_CUSTOM_NODES = "1"
    }
}

# Z Image Turbo preset — bake the full model set into the image so startup does
# not need to download models into the runtime volume.
target "_zit" {
    args = {
        ENABLE_ZIT_AUTOLOAD = "1"
        BAKE_ZIT_MODELS     = "1"
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
    tags = ["${DOCKERHUB_REPO_NAME}:base-torch${TORCH_VERSION_CU130}-cu130${EXTRA_TAG}"]
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
    tags = ["${DOCKERHUB_REPO_NAME}:slim-torch${TORCH_VERSION_CU130}-cu130${EXTRA_TAG}"]
}

target "zit-12-8" {
    inherits = ["_cu128", "_zit"]
    tags = tag("zit", "cu128")
}
