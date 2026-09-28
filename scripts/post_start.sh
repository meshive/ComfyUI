#!/bin/bash

export PYTHONUNBUFFERED=1
set -o pipefail

source /venv/bin/activate

# 앱 코드는 /opt/ComfyUI(이미지), 데이터는 /workspace/ComfyUI 다 — Dockerfile 의 ComfyUI 설치 주석 참조.
COMFYUI_APP=/opt/ComfyUI
COMFYUI_DATA=/workspace/ComfyUI
cd "$COMFYUI_APP"

# 유저 볼륨이 /workspace 나 /workspace/ComfyUI 에 붙으면 데이터 폴더가 비어 있는 채로 시작하므로 여기서
# 만든다. custom_nodes 는 특히 빠지면 안 된다: ComfyUI 는 기동 때 custom_nodes 경로마다 os.listdir 을
# 부르고, 폴더가 없으면 예외로 죽는다 (main.py execute_prestartup_script).
mkdir -p /workspace/logs "$COMFYUI_DATA"/{models,custom_nodes,input,output,user}
COMFYUI_LOG=/workspace/logs/comfyui_3000.log
ln -sf "$COMFYUI_LOG" "$COMFYUI_DATA/user/comfyui_3000.log"

# 내장 custom node 를 데이터 쪽 custom_nodes 에 심링크로 건다. ComfyUI 는 그 폴더 하나에서만 노드를 읽는다 —
# /opt/ComfyUI/custom_nodes 를 두 번째 경로로 더하면 같은 노드가 두 번 로드된다. 이미지의
# /workspace/ComfyUI/custom_nodes 에는 이미 걸려 있고(Dockerfile 의 호환 폴더), 여기서는 볼륨이 그 폴더를
# 덮은 경우를 채운다.
#   - 같은 이름이 이미 있으면(깨진 링크 포함) 건드리지 않는다 — 유저가 자기 버전을 둔 것이다.
#   - Manager 로 끈 노드(.disabled/<이름>, <이름>.disabled)는 다시 걸지 않는다.
#   - 이미지에서 사라진 내장 노드를 가리키던 링크는 지운다 — /opt 를 가리키는 링크, 즉 여기서 건 것만.
link_builtin_custom_nodes() {
    local dir="$COMFYUI_DATA/custom_nodes" src name link
    for src in "$COMFYUI_APP"/custom_nodes/*; do
        name=$(basename "$src")
        [ "$name" = "__pycache__" ] && continue
        if [ -e "$dir/$name" ] || [ -L "$dir/$name" ] \
                || [ -e "$dir/.disabled/$name" ] || [ -e "$dir/$name.disabled" ]; then
            continue
        fi
        ln -s "$src" "$dir/$name" \
            || echo "**** WARN: could not link built-in custom node $name into $dir ****" >&2
    done
    for link in "$dir"/*; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            case "$(readlink "$link")" in
                "$COMFYUI_APP"/custom_nodes/*) rm -f "$link" ;;
            esac
        fi
    done
}
link_builtin_custom_nodes

/ensure_pytorch_stack.sh

# 데이터 쪽 extra_model_paths.yaml — start.sh 의 configure_model_paths 가 쓴 것(프리셋 이미지·/workspace/models
# 마운트)이거나 유저가 볼륨에 둔 것. /workspace/ComfyUI 가 앱 폴더이던 때는 ComfyUI 가 알아서 읽었지만 이제
# 앱 폴더는 /opt/ComfyUI 라 직접 넘긴다. 이미지 쪽 설정(/opt/ComfyUI/extra_model_paths.yaml)은 ComfyUI 가
# 스스로 읽는다.
EXTRA_PATHS_ARGS=()
if [ -f "$COMFYUI_DATA/extra_model_paths.yaml" ]; then
    EXTRA_PATHS_ARGS=(--extra-model-paths-config "$COMFYUI_DATA/extra_model_paths.yaml")
fi

echo "**** Starts ComfyUI, listening on port 3000, with additional arguments specified by COMFYUI_EXTRA_ARGS. ****"
(
    echo "**** ComfyUI process starting at $(date -Is) ****"
    # --temp-directory 는 미리보기 같은 임시 파일을 로컬(/opt/ComfyUI/temp)에 둔다. 데이터 폴더를 따르게 두면
    # NFS 볼륨에 쌓이고, ComfyUI 는 기동할 때 temp 를 통째로 지우므로 같은 볼륨을 쓰는 다른 Pod 의 것까지
    # 지운다.
    # --database-url 도 같은 이유로 로컬에 둔다. v0.37.0 부터 sqlite DB 기본 위치가 유저 폴더
    # (= 데이터 폴더, NFS 일 수 있음)인데, 같은 볼륨을 쓰는 Pod 가 둘이면 DB 잠금이 부딪치고 SQLite 의
    # "database is locked" 는 ComfyUI 를 종료시킨다. DB 는 기본 꺼진 에셋 색인용이라 Pod 마다 따로여도 된다.
    # 유저가 COMFYUI_EXTRA_ARGS 로 다시 주면 뒤에 오는 그 값이 이긴다.
    python main.py --listen --port 3000 \
        --base-directory "$COMFYUI_DATA" \
        --temp-directory "$COMFYUI_APP" \
        --database-url "sqlite:///$COMFYUI_APP/user/comfyui.db" \
        "${EXTRA_PATHS_ARGS[@]}" \
        $COMFYUI_EXTRA_ARGS 2>&1
    status=$?
    echo "**** ComfyUI process exited at $(date -Is) with status ${status} ****"
    exit "$status"
) | tee -a "$COMFYUI_LOG" &
echo "$!" > /workspace/logs/comfyui_3000.pid
