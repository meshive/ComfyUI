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
    if [ "${STARTUP_LOGS_DUMPED:-0}" = "1" ]; then
        return
    fi
    STARTUP_LOGS_DUMPED=1

    local status=$?
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

# Setup ssh
setup_ssh() {
    if [[ $PUBLIC_KEY ]]; then
        echo "Setting up SSH..."
        mkdir -p ~/.ssh
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh

        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
            echo "RSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub
        fi

        if [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
            ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -q -N ''
            echo "DSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_dsa_key.pub
        fi

        if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
            ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -q -N ''
            echo "ECDSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub
        fi

        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -q -N ''
            echo "ED25519 key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
        fi

        service ssh start

        echo "SSH host keys:"
        for key in /etc/ssh/*.pub; do
            echo "Key: $key"
            ssh-keygen -lf $key
        done
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

has_model_files() {
    local target_path="$1"

    [ -d "$target_path" ] && [ -n "$(find "$target_path" -type f | head -n 1)" ]
}

configure_model_paths() {
    local target_models=""
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

    if has_model_files /ComfyUI/models; then
        target_models="/ComfyUI/models"
        echo "[Auto-Mount] 이미지 내장 모델 경로 발견: $target_models"
    elif [ -d /workspace/models ]; then
        target_models="/workspace/models"
        echo "[Auto-Mount] 모델 마운트 발견: $target_models"
    else
        echo '[Auto-Mount] /mnt 경로 하위에서 storage 패턴을 찾는 중...'
        if [ -d /mnt ]; then
            target_models=$(find /mnt -maxdepth 1 -name 'storage*' -type d | head -n 1 || true)
        fi
    fi

    if [ -z "$target_models" ]; then
        echo '[Auto-Mount] 경고: 모델 마운트 경로를 찾지 못했습니다.'
        return
    fi

    MODEL_MOUNT_PATH="$target_models"
    export MODEL_MOUNT_PATH
    ensure_model_dirs "$target_models"

    printf "comfyui:\n    base_path: %s\n    checkpoints: checkpoints/\n    loras: loras/\n    vae: vae/\n    configs: configs/\n    controlnet: controlnet/\n    upscale_models: upscale_models/\n    embeddings: embeddings/\n    clip: clip/\n    clip_vision: clip_vision/\n    diffusion_models: diffusion_models/\n    text_encoders: text_encoders/\n    audio_encoders: audio_encoders/\n    model_patches: model_patches/\n" "$target_models" > "$config_path"
    echo '[Auto-Mount] extra_model_paths.yaml 설정 완료'
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
            echo "[Preset] 경고: 모델 마운트 경로를 찾지 못해 PRESET_DOWNLOAD=$presets 를 건너뜁니다."
            echo "[Preset] 시스템 스토리지 보호를 위해 모델 마운트 없이 자동 다운로드하지 않습니다."
            return
        fi

        models_root="/workspace/models"
        echo "[Preset] 경고: 모델 마운트 없이 $models_root 로 다운로드합니다."
    fi

    if [ "${ALLOW_PRESET_DOWNLOAD_WITHOUT_MODEL_MOUNT,,}" != "true" ] && ! is_mounted_path "$models_root"; then
        echo "[Preset] 경고: $models_root 는 마운트 포인트가 아니라서 PRESET_DOWNLOAD=$presets 를 건너뜁니다."
        echo "[Preset] 시스템 스토리지 보호를 위해 모델 마운트가 확인된 경우에만 자동 다운로드합니다."
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

setup_ssh
start_jupyter
start_code_server
export_env_vars

echo "Start script(s) finished, pod is ready to use."

sleep infinity
