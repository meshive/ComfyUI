#!/bin/bash
set -e  # Exit the script if any statement returns a non-true return value

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

# Start nginx service
start_nginx() {
    echo "Starting Nginx service..."
    service nginx start
}

dump_startup_logs() {
    # $? 는 함수 진입 직후에만 트랩을 유발한 종료 코드를 담는다. 아래 중복 방지 블록의
    # 대입문 뒤에서 읽으면 그 대입의 결과(항상 0)를 잡아 실패가 전부 "status 0" 으로 찍힌다.
    local status=$?

    if [ "${STARTUP_LOGS_DUMPED:-0}" = "1" ]; then
        return
    fi
    STARTUP_LOGS_DUMPED=1

    echo "**** start.sh exiting at $(date -Is) with status ${status} ****"
    if [ -f /workspace/logs/comfyui_3000.log ]; then
        echo "**** Last 200 lines of /workspace/logs/comfyui_3000.log ****"
        tail -n 200 /workspace/logs/comfyui_3000.log || true
    else
        echo "**** /workspace/logs/comfyui_3000.log not found ****"
    fi
}

trap dump_startup_logs EXIT TERM INT

# Execute script if exists
execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash ${script_path}
    fi
}

# Export env vars
export_env_vars() {
    echo "Exporting environment variables..."
    printenv | grep -E '^MESHIVE_|^PATH=|^_=' | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
    echo 'source /etc/rp_environment' >> ~/.bashrc
}

# Start jupyter
start_jupyter() {
    # Default to not using a password
    JUPYTER_PASSWORD=""

    # Allow a password to be set by providing the ACCESS_PASSWORD environment variable
    if [[ ${ACCESS_PASSWORD} ]]; then
        echo "Starting JupyterLab with the provided password..."
        JUPYTER_PASSWORD=${ACCESS_PASSWORD}
    else
        echo "Starting JupyterLab without a password... (ACCESS_PASSWORD environment variable is not set.)"
    fi
    
    mkdir -p /workspace/logs
    cd / && \
    nohup jupyter lab --allow-root \
        --no-browser \
        --port=8888 \
        --ip=* \
        --FileContentsManager.delete_to_trash=False \
        --ContentsManager.allow_hidden=True \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --ServerApp.token="${JUPYTER_PASSWORD}" \
        --ServerApp.allow_origin=* \
        --ServerApp.preferred_dir=/workspace &> /workspace/logs/jupyterlab.log &
    echo "JupyterLab started"
}

# Start code-server
start_code_server() {
    echo "Starting code-server..."
    mkdir -p /workspace/logs

    # Allow a password to be set by providing the ACCESS_PASSWORD environment variable
    if [[ -n "${ACCESS_PASSWORD}" ]]; then
        echo "Starting code-server with the provided password..."
        export PASSWORD="${ACCESS_PASSWORD}"
        nohup code-server /workspace --bind-addr 0.0.0.0:8080 \
            --auth password \
            --ignore-last-opened \
            --disable-workspace-trust \
            &> /workspace/logs/code-server.log &
    else
        echo "Starting code-server without a password... (ACCESS_PASSWORD environment variable is not set.)"
        nohup code-server /workspace --bind-addr 0.0.0.0:8080 \
            --auth none \
            --ignore-last-opened \
            --disable-workspace-trust \
            &> /workspace/logs/code-server.log &
    fi

    echo "code-server started"
}

ensure_model_dirs() {
    local target_models="$1"

    if [ -z "$target_models" ]; then
        return 0
    fi

    mkdir -p "$target_models/checkpoints" "$target_models/loras" "$target_models/vae" \
             "$target_models/controlnet" "$target_models/upscale_models" \
             "$target_models/embeddings" "$target_models/configs" "$target_models/clip" \
             "$target_models/clip_vision" "$target_models/diffusion_models" \
             "$target_models/text_encoders" "$target_models/audio_encoders" \
             "$target_models/model_patches" "$target_models/output" || true
}

read_model_base_path() {
    local config_path="$1"

    awk -F ':' '
        /^[[:space:]]*base_path[[:space:]]*:/ {
            value=$2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "$config_path" 2>/dev/null || true
}

is_mounted_path() {
    local target_path="$1"

    awk -v target="$target_path" '$2 == target { found=1 } END { exit(found ? 0 : 1) }' /proc/mounts
}

configure_model_paths() {
    local target_models=""
    # 데이터 폴더 쪽 설정 파일 — 앱 폴더(/opt/ComfyUI)가 아니므로 ComfyUI 가 알아서 읽지 않는다.
    # post_start.sh 가 있으면 --extra-model-paths-config 로 넘긴다.
    local config_path="/workspace/ComfyUI/extra_model_paths.yaml"

    if [ -f "$config_path" ]; then
        target_models="$(read_model_base_path "$config_path")"
        if [ -n "$target_models" ]; then
            MODEL_MOUNT_PATH="$target_models"
            export MODEL_MOUNT_PATH
            ensure_model_dirs "$target_models"
            echo "[Auto-Mount] existing extra_model_paths.yaml found: $target_models"
        else
            echo "[Auto-Mount] existing extra_model_paths.yaml found, but base_path could not be parsed."
        fi
        return
    fi

    # /ComfyUI/models 분기는 2026-09-22 에 제거됐다. 그 경로는 BAKE_PRESET 프리셋이
    # 굽던 가중치 전용이었고, 프리셋 빌드 자체가 Dockerfile 에서 사라졌다.
    # MODEL_MOUNT_PATH / ensure_model_dirs 계약은 그대로다 — download_model_presets() 가
    # 그걸 소비하므로 비워두면 수십 GB 가 시스템 스토리지로 떨어진다.
    if [ -d /workspace/models ]; then
        target_models="/workspace/models"
        echo "[Auto-Mount] Found model mount: $target_models"
    fi
    # 예전에는 여기 else 로 `find /mnt -maxdepth 1 -name 'storage*'` 프로브가 있었다.
    # RunPod 시절 잔재라 현행 K8s 규약에서는 절대 매치될 수 없다 — 유저 볼륨은 /mnt/data 에
    # 붙고 이 휴리스틱은 (alias 가 아니라) 마운트 경로를 본다. 매치되지 않으므로 늘 아래
    # `-z "$target_models"` 분기로 떨어졌고, 즉 동작은 그대로다. (2026-09-22 제거)

    if [ -z "$target_models" ]; then
        # 현재 모든 변형이 여기로 떨어진다 (2026-09-22 프리셋 굽기 제거 이후).
        # /ComfyUI 는 여전히 있지만(COPY workflows/ 가 거기 들어간다) /ComfyUI/models 는 없다.
        # ComfyUI 는 `--base-directory /workspace/ComfyUI`(post_start.sh)로 뜨므로 기본 모델 경로
        # (/workspace/ComfyUI/models/*)가 곧 LV(또는 유저 볼륨) 마운트 지점이라 이 파일 없이
        # 그대로 동작한다 — semantic path 로 선언되지 않은 폴더(clip 등)도 folder_paths 가
        # 기본 경로로 등록하므로 잃는 기능이 없다. 동봉 configs yaml 은 이미지 쪽 설정
        # (/opt/ComfyUI/extra_model_paths.yaml)이 두 번째 경로로 붙인다.
        #
        # MODEL_MOUNT_PATH 를 비워두면 안 된다: ALLOW_PRESET_DOWNLOAD_WITHOUT_MODEL_MOUNT=true 로
        # 켰을 때 download_model_presets() 가 마운트가 아닌 /workspace/models 로 떨어져 수십 GB 를
        # 시스템 스토리지에 받는다. (다만 그 함수의 tmp_dir=$models_root/.tmp 는 8개 role 밖이라
        # 여전히 ephemeral 이다 — 프리셋 다운로드를 실제로 쓰게 되면 PRESET_TMP_DIR 을 마운트된
        # 경로로 지정할 것.)
        echo '[Auto-Mount] No models baked into the image - using ComfyUI native model paths'
        MODEL_MOUNT_PATH="/workspace/ComfyUI/models"
        export MODEL_MOUNT_PATH
        ensure_model_dirs "$MODEL_MOUNT_PATH"
        return
    fi

    MODEL_MOUNT_PATH="$target_models"
    export MODEL_MOUNT_PATH
    ensure_model_dirs "$target_models"

    printf "comfyui:\n    base_path: %s\n    checkpoints: checkpoints/\n    loras: loras/\n    vae: vae/\n    configs: configs/\n    controlnet: controlnet/\n    upscale_models: upscale_models/\n    embeddings: embeddings/\n    clip: clip/\n    clip_vision: clip_vision/\n    diffusion_models: diffusion_models/\n    text_encoders: text_encoders/\n    audio_encoders: audio_encoders/\n    model_patches: model_patches/\n" "$target_models" > "$config_path"
    echo '[Auto-Mount] Wrote extra_model_paths.yaml'
}

download_model_presets() {
    local presets="${PRESET_DOWNLOAD:-}"

    if [ -z "$presets" ]; then
        return
    fi

    if [ ! -f /download_presets.sh ]; then
        echo "[Preset] /download_presets.sh not found. Skipping PRESET_DOWNLOAD=$presets"
        return
    fi

    local models_root="${MODEL_MOUNT_PATH:-}"
    if [ -z "$models_root" ]; then
        if [ "${ALLOW_PRESET_DOWNLOAD_WITHOUT_MODEL_MOUNT,,}" != "true" ]; then
            echo "[Preset] Warning: no model mount found - skipping PRESET_DOWNLOAD=$presets"
            echo "[Preset] Models are downloaded only to a mounted volume, to protect system storage."
            return
        fi

        models_root="/workspace/models"
        echo "[Preset] Warning: no model mount - downloading to $models_root instead."
    fi

    if [ "${ALLOW_PRESET_DOWNLOAD_WITHOUT_MODEL_MOUNT,,}" != "true" ] && ! is_mounted_path "$models_root"; then
        echo "[Preset] Warning: $models_root is not a mount point - skipping PRESET_DOWNLOAD=$presets"
        echo "[Preset] Models are downloaded only once a mounted volume is confirmed, to protect system storage."
        return
    fi

    ensure_model_dirs "$models_root"

    local tmp_dir="${PRESET_TMP_DIR:-$models_root/.tmp/preset-downloads}"
    mkdir -p "$tmp_dir"

    echo "[Preset] downloading presets into model mount: $models_root"
    MODELS_ROOT="$models_root" TMP_DIR="$tmp_dir" /download_presets.sh --quiet "$presets"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

start_nginx

execute_script "/pre_start.sh" "Running pre-start script..."

configure_model_paths

echo "Pod Started"

execute_script "/post_start.sh" "Running post-start script..."

download_model_presets &

# setup_ssh 는 제거됐다 (2026-09-22). $PUBLIC_KEY 가 설정되어야만 동작했는데
# 플랫폼 어느 코드도 그 변수를 설정하지 않아 한 번도 타지 않는 경로였다
# (WebServerBackend/K8sControlServer/WebFrontend 전수 확인). Pod SSH 접속은
# files/ssh/ 의 노드-로컬 exec 게이트웨이(execd -> CRI)를 쓰며 컨테이너 안의
# sshd 와 무관하므로, 이 함수가 없어도 플랫폼 SSH 는 그대로 동작한다.
start_jupyter
start_code_server
export_env_vars

echo "Start script(s) finished, pod is ready to use."

sleep infinity
