# Set the base image
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Set the shell and enable pipefail for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set basic environment variables
ARG PYTHON_VERSION
ARG TORCH_VERSION
# torchaudio must match torch exactly; torchvision uses its own
# 0.{torch minor+15}.{patch} version line and is passed separately.
ARG TORCHVISION_VERSION=0.23.0
ARG CUDA_VERSION
ARG SKIP_CUSTOM_NODES
# ComfyUI release tag to check out. Pinning makes it obvious which version a
# given image shipped, and bumping this value invalidates the clone layer's
# build cache so a rebuild actually picks the new version up. Set to "master"
# to track the tip instead.
ARG COMFYUI_VERSION=v0.28.3
# Comma-separated list of presets to download into the model mount at runtime.
ARG DEFAULT_PRESET_DOWNLOAD=""
# Selects a bundled workflow preset to bake into the image. When non-empty,
# the matching auto-load extension and model set are both installed at build
# time so first launch needs no downloads. One of:
#   "" (none) | zit | flux | qwen | ltx | wan
ARG BAKE_PRESET=""

ENV TORCH_VERSION=${TORCH_VERSION}
ENV TORCHVISION_VERSION=${TORCHVISION_VERSION}
ENV CUDA_VERSION=${CUDA_VERSION}
ENV PYTORCH_STACK_ID="python-${PYTHON_VERSION}-torch-${TORCH_VERSION}-torchvision-${TORCHVISION_VERSION}-${CUDA_VERSION}"
ENV PRESET_DOWNLOAD=${DEFAULT_PRESET_DOWNLOAD}

# Set basic environment variables
ENV SHELL=/bin/bash 
ENV PYTHONUNBUFFERED=True 
ENV DEBIAN_FRONTEND=noninteractive

# Set the default workspace directory
ENV RP_WORKSPACE=/workspace

# Override the default huggingface cache directory.
ENV HF_HOME="${RP_WORKSPACE}/.cache/huggingface/"

# Faster transfer of models from the hub to the container
ENV HF_HUB_ENABLE_HF_TRANSFER=1
ENV HF_XET_HIGH_PERFORMANCE=1

# Shared python package cache
ENV VIRTUALENV_OVERRIDE_APP_DATA="${RP_WORKSPACE}/.cache/virtualenv/"
ENV PIP_CACHE_DIR="${RP_WORKSPACE}/.cache/pip/"
ENV UV_CACHE_DIR="${RP_WORKSPACE}/.cache/uv/"

# modern pip workarounds
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV PIP_ROOT_USER_ACTION=ignore

# Set TZ and Locale
ENV TZ=Etc/UTC

# Set working directory
WORKDIR /

# Update and upgrade
RUN apt-get update --yes && \
    apt-get upgrade --yes

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

# Install essential packages
RUN apt-get install --yes --no-install-recommends \
        git wget curl bash nginx-light rsync sudo binutils ffmpeg lshw nano tzdata file build-essential cmake nvtop \
        libgl1 libglib2.0-0 clang libomp-dev ninja-build \
        openssh-server ca-certificates && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install the UV tool from astral-sh
ADD https://astral.sh/uv/install.sh /uv-installer.sh
RUN sh /uv-installer.sh && rm /uv-installer.sh
ENV PATH="/root/.local/bin/:$PATH"

# Install Python and create virtual environment
RUN uv python install ${PYTHON_VERSION} --default --preview && \
    uv venv --seed /venv
# venv 는 /venv 에 영구히 둔다. 예전에는 pre_start.sh 가 매 기동마다 /workspace/venv 로 rsync 복사했고
# PATH 도 그쪽을 먼저 봤는데, /workspace 는 K8s pod 에서 마운트가 아니라 그 복사본(12.18GiB)이 통째로
# 컨테이너 쓰기 레이어(ephemeral)에 쌓였다. 복사를 없앤 지금 /workspace/venv 는 존재하지 않으므로
# PATH 에서도 빼야 한다 — 남겨두면 유저가 /workspace 에 venv 를 만드는 순간 /venv 를 가로챈다.
ENV PATH="/venv/bin:$PATH"

# Install essential Python packages and dependencies. triton is required by
# many ComfyUI custom nodes (xformers, attention kernels) on CUDA wheels, so we
# install it explicitly rather than relying on the PyTorch wheel's transitive
# dependency.
RUN pip install --no-cache-dir -U \
    pip setuptools wheel \
    jupyterlab jupyterlab_widgets ipykernel ipywidgets \
    huggingface_hub hf_transfer \
    numpy scipy matplotlib pandas scikit-learn seaborn requests tqdm pillow pyyaml \
    triton

# Install the PyTorch stack. TORCH_VERSION="nightly" triggers the nightly wheel
# index; every other value installs pinned wheels from the stable index. All
# targets including cu130 are pinned today -- the nightly path is kept as an
# escape hatch for the next time a stable wheel is broken on new hardware (it
# was used for cu130 while torch 2.10.0's bundled cuBLAS mishandled sm_120).
# Either way, the constraints file is generated from the *actually installed*
# versions so the downstream custom-node installs don't accidentally pull a
# different stack.
RUN if [ "${TORCH_VERSION}" = "nightly" ]; then \
        pip install --no-cache-dir --pre \
            torch torchvision torchaudio \
            --index-url "https://download.pytorch.org/whl/nightly/${CUDA_VERSION}"; \
    else \
        pip install --no-cache-dir \
            torch==${TORCH_VERSION} \
            torchvision==${TORCHVISION_VERSION} \
            torchaudio==${TORCH_VERSION} \
            --index-url "https://download.pytorch.org/whl/${CUDA_VERSION}"; \
    fi

# Capture the actually-installed versions so custom-node requirements use the
# same nightly build (otherwise a transitive `torch>=X` could pull a different
# wheel from PyPI).
RUN python -c "import torch, torchvision, torchaudio; \
    open('/pytorch-constraints.txt', 'w').write( \
        f'torch=={torch.__version__}\ntorchvision=={torchvision.__version__}\ntorchaudio=={torchaudio.__version__}\n')"

# Install ComfyUI and ComfyUI Manager.
# 앱 트리를 최종 위치인 /workspace/ComfyUI 에 바로 만든다. 예전에는 /ComfyUI 에 만들고 pre_start.sh 가
# 매 기동마다 rsync 로 옮겼는데, /workspace 자체는 마운트가 아니라 그 1.38GiB 가 ephemeral 에 쌓였다.
# models/ 하위 8개 role·output·user/default/workflows 는 런타임에 LV 로 덮이지만 그건 의도된 동작이고,
# 나머지(comfy/, custom_nodes/, main.py 등)는 이미지 레이어에 남아 쓰기 레이어를 먹지 않는다.
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    git checkout "${COMFYUI_VERSION}" && \
    echo "ComfyUI pinned to ${COMFYUI_VERSION} ($(git rev-parse --short HEAD))" && \
    pip install --no-cache-dir --constraint /pytorch-constraints.txt -r requirements.txt && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager && \
    cd custom_nodes/ComfyUI-Manager && \
    pip install --no-cache-dir --constraint /pytorch-constraints.txt -r requirements.txt

COPY custom_nodes.txt /custom_nodes.txt

RUN if [ -z "$SKIP_CUSTOM_NODES" ]; then \
        cd /workspace/ComfyUI/custom_nodes && \
        xargs -n 1 git clone --recursive < /custom_nodes.txt && \
        find /workspace/ComfyUI/custom_nodes -name "requirements.txt" -exec pip install --no-cache-dir --constraint /pytorch-constraints.txt -r {} \; && \
        find /workspace/ComfyUI/custom_nodes -name "install.py" -exec python {} \; ; \
    else \
        echo "Skipping custom nodes installation because SKIP_CUSTOM_NODES is set"; \
    fi && \
    # 빌드 타임 pip 캐시 제거(2.82GB). 위 pip 은 전부 --no-cache-dir 이지만 custom node 의 install.py 가
    # 서브프로세스로 부르는 pip 은 그걸 상속하지 않아 여기서만 쌓인다 (예: ComfyUI-Frame-Interpolation
    # 의 os.system("... -m pip install cupy ...")). 같은 RUN 이어야 레이어에 안 남고, `fi` 뒤여야
    # SKIP_CUSTOM_NODES 인 slim-* 타겟에서도 실행된다. `|| true` 를 붙이면 안 된다 —
    # `A || true && C` 는 `(A||true) && C` 라 위 if 블록의 실패까지 삼켜 빌드가 조용히 성공한다.
    echo "[build] pruning pip cache: ${PIP_CACHE_DIR}" && \
    rm -rf "${PIP_CACHE_DIR:?}"

# Custom node dependencies may pull a different PyTorch wheel from PyPI.
# Re-assert the CUDA-specific stack after those installs. Uses the same
# nightly / stable branching as the initial install.
RUN if [ "${TORCH_VERSION}" = "nightly" ]; then \
        pip install --no-cache-dir --pre --force-reinstall \
            torch torchvision torchaudio \
            --index-url "https://download.pytorch.org/whl/nightly/${CUDA_VERSION}"; \
    else \
        pip install --no-cache-dir --force-reinstall \
            torch==${TORCH_VERSION} \
            torchvision==${TORCHVISION_VERSION} \
            torchaudio==${TORCH_VERSION} \
            --index-url "https://download.pytorch.org/whl/${CUDA_VERSION}"; \
    fi && \
    # Re-capture installed versions and update the stack-id with the resolved torch version.
    # 참고: 이 stack-id 를 읽던 pre_start.sh 의 workspace-venv 불일치 검사는 제거됐다
    # (venv 가 /venv 에 고정돼 불일치가 성립하지 않는다). 지금은 진단용 기록일 뿐 소비자가 없다.
    python -c "import torch, torchvision, torchaudio; \
        open('/pytorch-constraints.txt', 'w').write( \
            f'torch=={torch.__version__}\ntorchvision=={torchvision.__version__}\ntorchaudio=={torchaudio.__version__}\n')" && \
    python -c "import torch, torchvision; \
        stack_id = f'python-${PYTHON_VERSION}-torch-{torch.__version__}-torchvision-{torchvision.__version__}-${CUDA_VERSION}'; \
        open('/venv/.pytorch-stack-id', 'w').write(stack_id + '\n')"

# Install Runpod CLI
#RUN wget -qO- cli.runpod.net | sudo bash

# Install code-server. 설치기가 남기는 .deb(195MB)는 이미지에 굳을 이유가 없다 —
# 같은 RUN 에서 지워야 레이어에 안 남는다.
RUN curl -fsSL https://code-server.dev/install.sh | sh && \
    rm -rf /root/.cache/code-server

EXPOSE 22 3000 8080 8888

# NGINX Proxy
COPY proxy/nginx.conf /etc/nginx/nginx.conf
COPY proxy/snippets /etc/nginx/snippets
COPY proxy/readme.html /usr/share/nginx/html/readme.html

# Remove existing SSH host keys
RUN rm -f /etc/ssh/ssh_host_*

# Copy the README.md
COPY README.md /usr/share/nginx/html/README.md

# Start Scripts
COPY --chmod=755 scripts/start.sh /
COPY --chmod=755 scripts/pre_start.sh /
COPY --chmod=755 scripts/post_start.sh /

COPY --chmod=755 scripts/download_presets.sh /
COPY --chmod=755 scripts/install_custom_nodes.sh /
COPY --chmod=755 scripts/ensure_pytorch_stack.sh /

# Bake workflow templates into the image so they appear in the user's ComfyUI
# workflow browser on first launch. 스테이징 경로(/ComfyUI)에 두고 pre_start.sh 가
# 런타임에 /workspace/ComfyUI 로 옮긴다 — base 변형에서는 그 경로가 config LV 마운트라
# 예제가 LV 위에 착지해야 유저에게 보이고(이미지에 구우면 마운트가 가려버린다),
# pre-baked 변형에서는 마운트가 없어 어느 쪽이든 보인다.
#
# ⚠️ 옮기는 주체는 **rsync 가 아니라 pre_start.sh 의 전용 시드 블록**이다 (rsync 는 이
#    서브트리를 명시적으로 제외한다). 여기 아래 폴더 구조는 pod 에 그대로 재현되지 않는다 —
#    JSON 만 뽑아 감시 루트 직하에 **평탄하게** 놓고 `.meshive/seeded/` 에 지문 마커를
#    남긴다. 디렉토리째 놓으면 harvester 가 폴더 하나를 유저 자산 하나로 수확해 버리고
#    (감시 루트 직하 엔트리 = 자산 1개), 그건 시드 마커로 억제할 수 없기 때문이다.
#    → 사유·계약은 pre_start.sh 의 해당 블록 주석 참조.
#    예제를 추가할 때: basename 이 **전역 유일**해야 한다 (평탄화로 폴더 이름 공간이
#    사라진다). 깊이는 자유 — pre_start.sh 가 `find` 로 훑는다.
COPY workflows/ /ComfyUI/user/default/workflows/

# Stage frontend-only custom extensions (e.g. zit-autoload). Activated below
# only for variants that opt in, so base/slim images don't auto-load a workflow
# whose models they don't have.
COPY custom_extensions/ /custom_extensions/

# Install the matching auto-load extension when a preset is requested.
# 확장은 앱 트리(/workspace/ComfyUI/custom_nodes)로 들어간다 — custom_nodes 는 마운트가 아니다.
# 반면 baked 모델은 아래에서 /ComfyUI/models/ 에 남긴다: /workspace/ComfyUI/models/* 의 8개 role 은
# 런타임에 LV 로 덮이므로 거기 두면 shadow 되어 사라진다. start.sh 의 configure_model_paths() 가
# /ComfyUI/models 를 찾아 extra_model_paths.yaml 로 노출시킨다.
RUN if [ -n "$BAKE_PRESET" ]; then \
        if [ ! -d "/custom_extensions/${BAKE_PRESET}-autoload" ]; then \
            echo "Unknown BAKE_PRESET=${BAKE_PRESET} (no /custom_extensions/${BAKE_PRESET}-autoload)" >&2; \
            exit 1; \
        fi; \
        cp -r "/custom_extensions/${BAKE_PRESET}-autoload" "/workspace/ComfyUI/custom_nodes/${BAKE_PRESET}-autoload"; \
    fi && \
    rm -rf /custom_extensions

# Bake the model set for the selected preset. Models are multi-GB so we retry
# transient network failures to keep CI builds from flaking on connection drops.
RUN set -e; \
    dl() { wget -q --show-progress --retry-connrefused --tries=3 --waitretry=5 -O "$2" "$1"; }; \
    case "$BAKE_PRESET" in \
        "") echo "No preset baking";; \
        zit) \
            mkdir -p /ComfyUI/models/text_encoders \
                     /ComfyUI/models/diffusion_models \
                     /ComfyUI/models/vae \
                     /ComfyUI/models/loras \
                     /ComfyUI/models/model_patches; \
            dl https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors \
               /ComfyUI/models/text_encoders/qwen_3_4b.safetensors; \
            dl https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors \
               /ComfyUI/models/diffusion_models/z_image_turbo_bf16.safetensors; \
            dl https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors \
               /ComfyUI/models/vae/ae.safetensors; \
            dl https://huggingface.co/tarn59/pixel_art_style_lora_z_image_turbo/resolve/main/pixel_art_style_z_image_turbo.safetensors \
               /ComfyUI/models/loras/pixel_art_style_z_image_turbo.safetensors; \
            dl https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union.safetensors \
               /ComfyUI/models/model_patches/Z-Image-Turbo-Fun-Controlnet-Union.safetensors; \
            ;; \
        flux) \
            mkdir -p /ComfyUI/models/diffusion_models \
                     /ComfyUI/models/text_encoders \
                     /ComfyUI/models/vae; \
            dl https://huggingface.co/Comfy-Org/flux1-schnell/resolve/main/flux1-schnell.safetensors \
               /ComfyUI/models/diffusion_models/flux1-schnell.safetensors; \
            dl https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors \
               /ComfyUI/models/text_encoders/clip_l.safetensors; \
            dl https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors \
               /ComfyUI/models/text_encoders/t5xxl_fp16.safetensors; \
            dl https://huggingface.co/Comfy-Org/Lumina_Image_2.0_Repackaged/resolve/main/split_files/vae/ae.safetensors \
               /ComfyUI/models/vae/ae.safetensors; \
            ;; \
        qwen) \
            mkdir -p /ComfyUI/models/diffusion_models \
                     /ComfyUI/models/text_encoders \
                     /ComfyUI/models/vae \
                     /ComfyUI/models/loras; \
            dl https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_fp8_e4m3fn.safetensors \
               /ComfyUI/models/diffusion_models/qwen_image_fp8_e4m3fn.safetensors; \
            dl https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors \
               /ComfyUI/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors; \
            dl https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors \
               /ComfyUI/models/vae/qwen_image_vae.safetensors; \
            dl https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V1.0.safetensors \
               /ComfyUI/models/loras/Qwen-Image-Lightning-8steps-V1.0.safetensors; \
            ;; \
        ltx) \
            mkdir -p /ComfyUI/models/checkpoints \
                     /ComfyUI/models/text_encoders; \
            dl https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltx-video-2b-v0.9.safetensors \
               /ComfyUI/models/checkpoints/ltx-video-2b-v0.9.safetensors; \
            dl https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors \
               /ComfyUI/models/text_encoders/t5xxl_fp16.safetensors; \
            ;; \
        wan) \
            mkdir -p /ComfyUI/models/diffusion_models \
                     /ComfyUI/models/text_encoders \
                     /ComfyUI/models/vae \
                     /ComfyUI/models/loras; \
            dl https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors \
               /ComfyUI/models/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors; \
            dl https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors \
               /ComfyUI/models/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors; \
            dl https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors \
               /ComfyUI/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors; \
            dl https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors \
               /ComfyUI/models/vae/wan_2.1_vae.safetensors; \
            dl https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors \
               /ComfyUI/models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors; \
            dl https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors \
               /ComfyUI/models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors; \
            ;; \
        *) echo "Unknown BAKE_PRESET=${BAKE_PRESET}" >&2; exit 1;; \
    esac

# Welcome Message
# The greeting text lives inside meshive.txt (blank separator line and
# trailing newline included) so the banner does not depend on `echo -e`
# escape handling, which is shell-dependent and was collapsing the newline.
COPY logo/meshive.txt /etc/meshive.txt
RUN echo 'cat /etc/meshive.txt' >> /root/.bashrc

# Set entrypoint to the start script
CMD ["/start.sh"]
