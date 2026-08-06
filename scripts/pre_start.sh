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

    # 앱 코드는 이제 이미지가 /workspace/ComfyUI 에 갖고 있으므로 여기 남는 건 사실상
    # user/default/workflows 의 번들 예제뿐인데, 그건 아래 전용 블록이 처리한다 (이유는 거기
    # 주석). 그래서 현재 변형들에서 이 rsync 는 사실상 no-op 이다 — 이미지 레이아웃이 다시
    # 바뀔 때를 위한 방어로 남겨 둔다.
    # baked 모델은 /ComfyUI/models 에 그대로 두고 extra_model_paths.yaml 로 참조한다.
    rsync -au --remove-source-files --exclude=/models/ \
        --exclude=/user/default/workflows/ $EXCLUDE /ComfyUI/ /workspace/ComfyUI/

    # ── 번들 예제 workflow: 폴더가 아니라 **평탄한 파일**로 + 시드 마커 ────────────────
    #
    # 위 rsync 에서 이 서브트리만 뺀 이유: rsync 는 `flux/` 같은 디렉토리를 그대로 옮기는데,
    # base 변형에서 이 경로는 config LV = harvester 감시 루트다. harvester 의 수확 단위는
    # "감시 루트 직하 엔트리 1개 = 자산 1개"이고 디렉토리 자식은 서브트리 전체가 엔트리
    # 하나다 (`harvester.py::scan_root`) → 유저 워크스페이스에 zit/flux/qwen/ltx/wan 5개의
    # 가짜 config 자산이 생겼다 (2026-08-04 dev 실증).
    #
    # 그리고 그걸 막을 방법이 구조적으로 없다: 플랫폼 시드 억제(G2)는
    # `not scan.is_dir and len(hashed) == 1` 인 단일 파일 엔트리만 대상이다
    # (`harvester.py::_reconcile_entry`) — 디렉토리에 지문 하나를 대응시킬 수 없어서다.
    # exclude 패턴으로 거르는 것도 답이 아니다: 유저가 고친 예제까지 영원히 제외돼 config
    # 수확(G2)의 목적 자체가 무산된다 (`seed_k8s_templates.py` 의 config 선언 주석 참조).
    #
    # → 폴더당 JSON 이 어차피 1개뿐이므로 평탄하게 놓고 지문을 마커에 남긴다. 그러면 이미
    #   검증된 단일 파일 억제 경로가 그대로 먹는다 — harvester 도 서버도 무변경.
    #
    # 마커 규약은 K8sCS `asset_sidecar.py::WORKFLOW_SEED_SCRIPT` 와 harvester
    # `place_workflow_seed` 의 **미러**다 (= 이 이미지가 세 번째 writer). 드리프트 금지:
    #   · 대상 파일이나 마커가 있으면 쓰지 않는다 — 수정뿐 아니라 **삭제도 존중**한다
    #     (유저가 지운 예제를 재기동 rsync 가 부활시키던 기존 동작의 수정이기도 하다)
    #   · skip 할 때도 마커는 남긴다 ("이 slug 는 이 볼륨에서 이미 고려됐다"는 뜻)
    #   · 본문 = {"filename": ..., "sha256": <놓는 내용의 지문>}. 이 지문이
    #     `harvester.py::_seed_hashes` 의 유일한 근거다 — 빠뜨리면 놓자마자 자산이 된다
    #
    # 파일 → 마커 순서(두 기존 writer 와 동일)가 안전한 이유: harvester 는 2연속 동일 지문을
    # 요구하므로 파일이 처음 보인 사이클엔 hash 도 시드 판정도 하지 않는다. 판정은 최소
    # 1주기(기본 30s) 뒤고 마커는 그 전에 µs 단위로 쓰인다. 순서를 뒤집으면 µs 창은
    # 없어지지만 "마커만 있고 파일은 영영 안 놓임"이라는 영구 상태가 생긴다.
    #
    # slug 의 `bundled-` 접두사는 카탈로그 시드(slug = 번들 slug)와 이름 공간을 가르기
    # 위함이다. 서버(`GET /v1/assets/workflow-seeds`)는 known 을 단순 차집합으로만 쓰므로
    # 모르는 slug 는 무해하다.
    #
    # 이 블록은 어떤 경우에도 실패로 끝나지 않는다. `set -e` 자체는 자식 스크립트로 상속되지
    # 않지만(SHELLOPTS 미export), start.sh 는 `bash /pre_start.sh` 를 `set -e` 아래에서
    # 부르므로 **이 스크립트의 최종 exit status** 가 곧 start.sh 의 생사다. 여기서 죽으면
    # 유저가 pod 에 접근할 수단 없이 CrashLoopBackOff + GPU 과금만 계속된다 (상단 주석과
    # 같은 규율). `A || B && C` 는 `(A||B) && C` 이므로 조건부 실행을 || 로 엮지 않는다.
    SEED_SRC=/ComfyUI/user/default/workflows
    SEED_DST=/workspace/ComfyUI/user/default/workflows
    SEED_MESHIVE_DIR="$SEED_DST/.meshive"
    SEED_MARKER_DIR="$SEED_MESHIVE_DIR/seeded"

    write_seed_marker() {
        # 값은 전부 이미지가 굽는 파일명·지문(영숫자/`_`/`.`)이라 JSON escape 가 필요 없다.
        # 외부 문자열이 들어오게 되면 escape 를 먼저 넣을 것.
        local _marker=$1 _filename=$2 _sha=$3
        printf '{"filename": "%s", "sha256": "%s"}' "$_filename" "$_sha" \
            > "$_marker.tmp" 2>/dev/null || return 1
        mv -f "$_marker.tmp" "$_marker" 2>/dev/null || { rm -f "$_marker.tmp"; return 1; }
    }

    if [ -d "$SEED_SRC" ] && mkdir -p "$SEED_MARKER_DIR" 2>/dev/null; then
        # `.meshive/` 는 harvester BUILTIN_EXCLUDES 라 수확되지 않는다. 0777 은 방어적
        # 조치다 — asset-harvester 이미지는 `USER 65534` 이고 사이드카는 주입 루트가 있을
        # 때만 root 로 승격되므로(`asset_sidecar.py` 의 build_harvest_sidecar), root 가 만든
        # 0755 를 남기면 실행 중 시드 도착분(`place_workflow_seed` 의 mkstemp)이 EPERM 으로
        # 조용히 실패할 수 있다. 마운트 루트는 mount-perm init 이 이미 a+rwx 라 새 노출은 없다.
        chmod 0777 "$SEED_MESHIVE_DIR" "$SEED_MARKER_DIR" 2>/dev/null || true

        # 깊이를 고정하지 않고 `find` 로 전부 훑는다. 위 rsync 가 이 서브트리를 통째로
        # 제외하므로, `*/*.json` 처럼 깊이를 박아 두면 나중에 `workflows/foo.json` 을
        # 최상위에 추가한 사람의 파일이 **pod 에서 통째로 사라진다** (예전엔 rsync 가
        # 어쨌든 날라줬다). 평탄화로 family 이름 공간이 사라지는 대가로, 서로 다른
        # 위치의 같은 basename 은 뒤엣것이 skip 된다 — 그래서 skip 을 조용히 넘기지 않고
        # 아래에서 반드시 로그를 남긴다. 지금은 5개 stem 이 전부 유일하다.
        find "$SEED_SRC" -type f -name '*.json' 2>/dev/null | sort | while read -r src; do
            base=$(basename "$src")
            slug="bundled-${base%.json}"
            dest="$SEED_DST/$base"
            marker="$SEED_MARKER_DIR/$slug"
            # 지문은 **놓는 바이트 그대로**여야 한다 (harvester 는 dest 를 통째로 sha256
            # 한다). 어떤 정규화·재직렬화도 없이 그대로 복사하는 이유가 이것이다.
            sha=$(sha256sum "$src" 2>/dev/null | cut -d' ' -f1)
            if [ -z "$sha" ]; then
                echo "**** WARN workflow seed: cannot hash $src — skipped ****" >&2
                continue
            fi

            if [ -e "$dest" ] || [ -e "$marker" ]; then
                if [ ! -e "$marker" ]; then
                    write_seed_marker "$marker" "$base" "$sha" \
                        || echo "**** WARN workflow seed: marker write failed: $slug ****" >&2
                fi
                # 조용히 넘기지 않는다. 정상(유저가 지웠거나 재기동)이 대부분이지만, basename
                # 충돌로 예제 하나가 통째로 유실된 경우와 구분되는 유일한 단서가 이 로그다.
                echo "**** workflow seed skip (exists or already seeded): $base ****"
                continue
            fi

            # 원자적 배치: tmp 를 같은 LV 의 `.meshive/` 안에 만들어 mv 가 rename(2) 이
            # 되게 한다. 착지 디렉토리에 만들면 rename 직전에 죽었을 때 잔재가 수확된다.
            tmp="$SEED_MESHIVE_DIR/seed-$slug.tmp"
            if cp "$src" "$tmp" 2>/dev/null && chmod 0666 "$tmp" 2>/dev/null \
                    && mv -f "$tmp" "$dest" 2>/dev/null; then
                write_seed_marker "$marker" "$base" "$sha" \
                    || echo "**** WARN workflow seed: marker write failed: $slug ****" >&2
                echo "**** workflow seed placed: $base ****"
            else
                rm -f "$tmp" 2>/dev/null || true
                echo "**** WARN workflow seed: place failed: $base ****" >&2
            fi
        done   # `find | while` 는 서브셸이지만 이 루프는 밖으로 넘길 상태가 없다
    else
        echo "**** workflow seed: $SEED_SRC absent or marker dir not writable — skipped ****"
    fi

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
