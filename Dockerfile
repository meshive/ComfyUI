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
ENV PATH="/workspace/venv/bin:/venv/bin:$PATH"

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

# Keep the PyTorch stack on one official wheel index so torch,
# torchvision, torchaudio, and triton are ABI-compatible.
RUN pip install --no-cache-dir \
    torch==${TORCH_VERSION} \
    torchvision==${TORCHVISION_VERSION} \
    torchaudio==${TORCH_VERSION} \
    --index-url https://download.pytorch.org/whl/${CUDA_VERSION}

RUN printf "torch==%s\ntorchvision==%s\ntorchaudio==%s\n" \
    "${TORCH_VERSION}" "${TORCHVISION_VERSION}" "${TORCH_VERSION}" > /pytorch-constraints.txt

# Install ComfyUI and ComfyUI Manager
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && \
    pip install --no-cache-dir --constraint /pytorch-constraints.txt -r requirements.txt && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager && \
    cd custom_nodes/ComfyUI-Manager && \
    pip install --no-cache-dir --constraint /pytorch-constraints.txt -r requirements.txt

COPY custom_nodes.txt /custom_nodes.txt

RUN if [ -z "$SKIP_CUSTOM_NODES" ]; then \
        cd /ComfyUI/custom_nodes && \
        xargs -n 1 git clone --recursive < /custom_nodes.txt && \
        find /ComfyUI/custom_nodes -name "requirements.txt" -exec pip install --no-cache-dir --constraint /pytorch-constraints.txt -r {} \; && \
        find /ComfyUI/custom_nodes -name "install.py" -exec python {} \; ; \
    else \
        echo "Skipping custom nodes installation because SKIP_CUSTOM_NODES is set"; \
    fi

# Custom node dependencies may pull a different PyTorch wheel from PyPI.
# Re-assert the CUDA-specific stack after those installs.
RUN pip install --no-cache-dir --force-reinstall \
    torch==${TORCH_VERSION} \
    torchvision==${TORCHVISION_VERSION} \
    torchaudio==${TORCH_VERSION} \
    --index-url https://download.pytorch.org/whl/${CUDA_VERSION} && \
    printf "%s\n" "$PYTORCH_STACK_ID" > /venv/.pytorch-stack-id

# Install Runpod CLI
#RUN wget -qO- cli.runpod.net | sudo bash

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

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

# Bake workflow templates into the image so they appear in the user's
# ComfyUI workflow browser on first launch (pre_start.sh rsyncs /ComfyUI
# into /workspace/ComfyUI on first boot, preserving the user/ tree).
COPY workflows/ /ComfyUI/user/default/workflows/

# Stage frontend-only custom extensions (e.g. zit-autoload). Activated below
# only for variants that opt in, so base/slim images don't auto-load a workflow
# whose models they don't have.
COPY custom_extensions/ /custom_extensions/

# Install the matching auto-load extension when a preset is requested.
# /workspace/models is a runtime volume mount, so baked files live under
# /ComfyUI/models/ which pre_start.sh layers over the user's mount on first boot.
RUN if [ -n "$BAKE_PRESET" ]; then \
        if [ ! -d "/custom_extensions/${BAKE_PRESET}-autoload" ]; then \
            echo "Unknown BAKE_PRESET=${BAKE_PRESET} (no /custom_extensions/${BAKE_PRESET}-autoload)" >&2; \
            exit 1; \
        fi; \
        cp -r "/custom_extensions/${BAKE_PRESET}-autoload" "/ComfyUI/custom_nodes/${BAKE_PRESET}-autoload"; \
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
COPY logo/meshive.txt /etc/meshive.txt
RUN echo 'cat /etc/meshive.txt' >> /root/.bashrc
RUN echo 'echo -e "\nNice to meet you and We are Meshive administrator, Thank you."' >> /root/.bashrc

# Set entrypoint to the start script
CMD ["/start.sh"]
