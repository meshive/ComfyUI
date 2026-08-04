#!/bin/bash

export PYTHONUNBUFFERED=1

echo "**** Setting the timezone based on the TIME_ZONE environment variable. If not set, it defaults to Etc/UTC. ****"
export TZ=${TIME_ZONE:-"Etc/UTC"}
echo "**** Timezone set to $TZ ****"
echo "$TZ" | sudo tee /etc/timezone > /dev/null
sudo ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
sudo dpkg-reconfigure -f noninteractive tzdata

# venv 와 앱 트리는 이제 이미지가 최종 위치에 갖고 있다 — 런타임 복사가 없다.
#
# 예전에는 여기서 /venv(12.18GiB) 를 /workspace/venv 로, /ComfyUI 를 /workspace/ComfyUI 로 rsync 했다.
# RunPod 에서는 /workspace 가 영구 네트워크 볼륨이라 "이미지 → 볼륨" 이동으로 말이 됐지만, 우리 K8s pod
# 에서는 /workspace 자체가 마운트가 아니고 그 하위 10개 경로(models 8종·output·user/default/workflows)만
# LV 다. 그래서 복사본 13.56GiB 가 통째로 컨테이너 쓰기 레이어(= system storage)에 쌓였고, 매 기동마다
# 30초를 썼다. 지금은 Dockerfile 이 venv 를 /venv 에, 앱 트리를 /workspace/ComfyUI 에 바로 만든다.
#
# venv 를 /workspace 로 옮기지 않은 이유: /venv 는 어떤 볼륨 마운트에도 가려질 수 없다.
# 앱 트리는 models/output/workflows 마운트의 부모여야 해서 /workspace/ComfyUI 에 있어야만 한다.
#
# 아래는 그 레이아웃이 깨졌을 때 원인을 남기는 진단 로그다. exit 하지 않는다 — start.sh 는 `set -e` 이고
# Jupyter/code-server/SSH 기동이 이 스크립트 뒤에 있어서, 여기서 죽으면 유저가 pod 에 접근할 수단이
# 전혀 없는 채로 CrashLoopBackOff 가 되고 GPU 과금만 계속된다. 열화된 채로 뜨는 편이 낫다.
[ -x /venv/bin/python ] || \
    echo "**** WARN: /venv/bin/python missing — image layout broken ****" >&2
[ -f /workspace/ComfyUI/main.py ] || \
    echo "**** WARN: /workspace/ComfyUI shadowed by a volume mount — this image bakes the app tree there ****" >&2

echo "**** syncing ComfyUI to workspace, please wait ****"
if [ -d /ComfyUI ]; then
    EXCLUDE=""
    if [ -d /workspace/ComfyUI/output ]; then
        EXCLUDE="--exclude=output/"
        echo "**** Excluding existing output folder ****"
    fi

    # 앱 코드는 이제 이미지가 /workspace/ComfyUI 에 갖고 있으므로, 여기 남는 건 사실상
    # user/default/workflows 의 번들 예제(수 MB)뿐이다. 이건 계속 런타임 복사여야 한다 —
    # base 변형에서 그 경로는 config LV 마운트라, 예제가 LV 위에 착지해야 유저에게 보인다
    # (이미지에 구우면 마운트가 가려버린다). pre-baked 변형은 마운트가 없어 어느 쪽이든 보인다.
    # baked 모델은 /ComfyUI/models 에 그대로 두고 extra_model_paths.yaml 로 참조한다.
    rsync -au --remove-source-files --exclude=/models/ $EXCLUDE /ComfyUI/ /workspace/ComfyUI/

    # Clean up emptied source dirs but keep /ComfyUI/models intact for image
    # variants that bake models there.
    find /ComfyUI -mindepth 1 -type d -empty \
        -not \( -path '/ComfyUI/models' -o -path '/ComfyUI/models/*' \) \
        -delete 2>/dev/null || true

else
    echo "Skip: /ComfyUI does not exist."
fi


if [ "${INSTALL_SAGEATTENTION,,}" = "true" ]; then
    if pip show sageattention > /dev/null 2>&1; then
        echo "**** SageAttention2 is already installed. Skipping installation. ****"
    else
        echo "**** SageAttention2 is not installed. Installing, please wait.... (This may take a long time, approximately 5+ minutes.) ****"
        git clone https://github.com/thu-ml/SageAttention.git /SageAttention
        cd /SageAttention
        export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32
        python setup.py install
        echo "**** SageAttention2 installation completed. ****"
    fi
fi

if [ "${INSTALL_CUSTOM_NODES,,}" = "true" ]; then
    if [ -f /install_custom_nodes.sh ]; then
        echo "**** INSTALL_CUSTOM_NODES is set. Running /install_custom_nodes.sh ****"
        /install_custom_nodes.sh
    else
        echo "**** /install_custom_nodes.sh not found. Skipping. ****"
    fi
fi
