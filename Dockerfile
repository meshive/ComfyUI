# Set the base image
ARG BASE_IMAGE
# 단계 이름 `image` 는 파일 맨 아래 빌드 검사 단계와 최종 단계가 이 단계를 가리키려고 붙인다.
FROM ${BASE_IMAGE} AS image

# Set the shell and enable pipefail for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ⚠️ **ARG 선언 위치가 곧 캐시 경계다. 첫 소비자 바로 위에서만 선언할 것.**
#
# BuildKit 은 스코프에 살아있는 **모든** build arg 를 그 아래 모든 RUN 의
# 환경에 넣고, 그 환경이 캐시 키에 들어간다 — 그 RUN 이 arg 를 참조하든 말든,
# bake 가 값을 넘기든 말든. 예전에는 8개를 여기 상단에 몰아 선언했고, 그래서 arg 를
# 하나도 안 쓰는 아래 `printf` 레이어조차 히스토리에 이렇게 기록됐다:
#   RUN |8 PYTHON_VERSION=3.13 ... SKIP_CUSTOM_NODES= ... BAKE_PRESET= /bin/bash ... printf
# (`docker buildx bake --print base-12-8` 은 6개만 넘기는데도 8개가 전부 박힌다 —
#  선언만 해도 들어간다는 뜻이다.)
#
# 대가는 2026-09-22 에 실측했다: COMFYUI_VERSION 한 줄만 올려도 그 아래 15GB 가 전부
# 재빌드되고, base/slim/프리셋 5종이 서로 레이어를 **하나도** 공유하지 못했다
# (cu130 7개 태그 단순합 247.50GB 중 유니크 231.69GB, base↔프리셋 공유 레이어 0개).
#
# 런타임에만 쓰이는 값(TORCH_VERSION 등)은 파일 **맨 아래**에서 ENV 로 굳힌다.
# ENV 도 아래 RUN 들의 캐시 키에 들어가므로, 상단에 두면 ARG 를 내린 의미가 없다.
# 새 ARG 를 추가할 때도 이 규칙을 지킬 것.

# Set basic environment variables
ENV SHELL=/bin/bash 
ENV PYTHONUNBUFFERED=True 
ENV DEBIAN_FRONTEND=noninteractive

# 로그/툴 출력을 영어 UTF-8 로 고정한다. Meshive 는 글로벌 플랫폼이고 컨테이너
# stdout 은 유저가 FE(PodBox)에서 그대로 읽는다. C.UTF-8 은 glibc 내장이라 locale-gen
# 이 필요 없다 — 예전에 여기 있던 `echo "en_US.UTF-8 UTF-8" > /etc/locale.gen` 은
# locale-gen 을 한 번도 호출하지 않아 실제로는 아무 locale 도 생성하지 않았고
# LANG 도 비어 있어 컨테이너는 POSIX locale 로 돌았다. (2026-09-22 정리)
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

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

# apt 재시도 — archive.ubuntu.com 은 라운드로빈이고 그중 일부 노드가 개별 .deb 에
# `400 Bad Request` 를 돌려주는 일이 있다. 기본값(재시도 0)이면 그 한 파일 때문에 20GB
# 짜리 빌드 전체가 5/33 단계에서 죽는다 — 2026-08-08 에 3회 연속으로 겪었고 매번 패키지와
# 미러 IP 가 달랐다. 재시도는 대개 다른 백엔드로 붙어 성공한다.
RUN printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\n' \
        > /etc/apt/apt.conf.d/80-retries

# Update and upgrade
RUN apt-get update --yes && \
    apt-get upgrade --yes

# Install essential packages
RUN apt-get install --yes --no-install-recommends \
        git wget curl bash nginx-light rsync sudo binutils ffmpeg lshw nano tzdata file build-essential cmake nvtop \
        libgl1 libglib2.0-0 clang libomp-dev ninja-build \
        openssh-server ca-certificates && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install the UV tool from astral-sh
# ⚠️ 버전을 URL 에 **고정**한다. `https://astral.sh/uv/install.sh` 는 언제나 최신
# 릴리즈를 주고 BuildKit 은 받아온 파일의 content digest 를 캐시 키에 넣으므로,
# uv 가 릴리즈될 때마다 이 레이어와 **그 아래 전부**가 깨진다.
# 2026-08-24 빌드가 실제로 이걸로 터졌다: 위 apt 계열 레이어는 2026-08-08 캐시를
# 16일 만에 그대로 재사용했는데 이 ADD 에서 miss 가 나 아래 13.16GB 가 통째로
# 재빌드됐다. 그날 바뀐 소스는 46개 레이어 중 42번째에 들어가는
# custom_extensions/ JS 파일 하나뿐이었다.
# 0.12.3 은 현재 배포 중인 이미지에 실제로 들어있는 바로 그 스크립트다
# (sha256 a7e3924ea1cd06bf1518c577d635c624ae2e2db030e0fc8ff8cf426224384e17, 71225B)
# — 즉 이 핀은 동작을 바꾸지 않는다. 올릴 때는 이 줄을 의도적으로 고쳐서 올린다.
ADD https://astral.sh/uv/0.12.3/install.sh /uv-installer.sh
RUN sh /uv-installer.sh && rm /uv-installer.sh
ENV PATH="/root/.local/bin/:$PATH"

# Install Python and create virtual environment
ARG PYTHON_VERSION
RUN uv python install ${PYTHON_VERSION} --default --preview && \
    uv venv --seed /venv
# venv 는 /venv 에 영구히 둔다. 예전에는 pre_start.sh 가 매 기동마다 /workspace/venv 로 rsync 복사했고
# PATH 도 그쪽을 먼저 봤는데, /workspace 는 K8s pod 에서 마운트가 아니라 그 복사본(12.18GiB)이 통째로
# 컨테이너 쓰기 레이어(ephemeral)에 쌓였다. 복사를 없앤 지금 /workspace/venv 는 존재하지 않으므로
# PATH 에서도 빼야 한다 — 남겨두면 유저가 /workspace 에 venv 를 만드는 순간 /venv 를 가로챈다.
ENV PATH="/venv/bin:$PATH"

# pip 잠금은 파일 두 개로 나눈다. 잠그는 이유와 다시 만드는 법은 constraints/cu130.txt 헤더에 있다.
# 타깃별 파일은 bake 가 넘긴다 — cu130 만 잠그고, 레거시 타깃은 constraints/none.txt (잠금 없음).
#   - 기반 잠금(PIP_BASE_LOCK_FILE, 여기): 바로 아래 기반 패키지 RUN 이 까는 것만 담는다. torch 레이어
#     **위**에 있으므로 작게 두고, 기반 패키지를 일부러 올릴 때만 바꾼다.
#   - 전체 잠금(PIP_LOCK_FILE): torch 아래, ComfyUI RUN 바로 위에서 들어온다. ComfyUI·custom node 를
#     올리면 이 파일도 다시 만들어야 하는데(ComfyUI requirements 가 frontend 등을 == 로 고정한다), 그
#     위치여야 그때도 torch 레이어(압축 ~2.8GB) 캐시가 살고 노드가 그 레이어를 다시 받지 않는다. 한 파일을
#     여기 두면 ComfyUI 를 올릴 때마다 torch 까지 새 레이어가 된다 (2026-09-29 리뷰).
# 공통 규칙:
#   - `@` 가 있는 줄(직접 URL)은 constraint 로 줄 수 없어 빼고 넘긴다. 그 줄은 빌드 마지막 검사 단계가
#     설치 목록 전체를 전체 잠금과 정확히 대조할 때 잡는다.
#   - PIP_CONSTRAINT 는 RUN 안에서만 준다. ENV 로 두면 pod 안에서 유저가 하는 pip 설치까지 묶인다.
#   - torch 설치 RUN 에는 주지 않는다. 그 RUN 은 download.pytorch.org 인덱스만 보는데, 잠긴 버전 중 그
#     인덱스에 없는 것이 있으면 해석이 실패한다. torch 셋은 /pytorch-constraints.txt 가 맡고, torch 가
#     버전을 정확히 고정하지 않는 의존성은 기반 RUN 이 먼저 깐다 (아래 sympy·networkx).
ARG PIP_BASE_LOCK_FILE=constraints/none.txt
COPY ${PIP_BASE_LOCK_FILE} /pip-base-lock.txt
RUN sed -E '/^[[:space:]]*(#|$)/d; / @ /d' /pip-base-lock.txt > /pip-base-constraints.txt && \
    echo "[build] pip base lock ${PIP_BASE_LOCK_FILE}: $(wc -l < /pip-base-constraints.txt) constraints"

# Install essential Python packages and dependencies.
#
# ⚠️ triton 을 여기서 명시적으로 깔지 말 것. torch 의 **필수 의존성**이라 아래 torch
# 설치가 정확한 핀 버전을 알아서 깔아준다 — torch-2.8.0+cu128 메타데이터:
#   Requires-Dist: triton==3.4.0; platform_system == "Linux" and platform_machine == "x86_64"
# 예전에는 "custom node 가 필요로 해서" 여기서 먼저 깔았는데, 그러면 PyPI 최신 triton 이
# 깔린 뒤 torch 가 그걸 핀 버전으로 갈아엎고, 그 과정에서 하위 레이어 파일을 덮어쓰니
# overlayfs 가 copy-up 을 강제해 **triton 이 이미지에 두 번** 들어갔다.
# 2026-09-22 실측(base-torch2.8.0-cu128): 명시 설치 레이어 722.8MB + torch 레이어 566.2MB,
# 앞의 722.8MB 는 전부 죽은 바이트였다 (압축 기준 약 215MB).
# 부수 효과로 빌드 시점마다 중간 triton 버전이 달라져 재현성도 깨졌다.
#
# sympy·networkx 는 torch 의존성인데 torch 가 버전을 `>=` 로만 요구한다. 여기서 잠근 버전으로 먼저 깔아
# 두면 아래 torch RUN(잠금 없음, `-U` 없음)이 충족된 것으로 보고 그대로 둔다 — 안 그러면 torch 레이어를
# 다시 빌드할 때 그날 인덱스의 새 버전이 들어온다. 위 triton 과 달리 torch 가 갈아엎지 않으므로 이미지에
# 두 번 들어가지 않는다 (나머지 자유 의존성 filelock·typing-extensions·setuptools·jinja2·fsspec 은 이미
# 이 목록의 의존성으로 들어온다, 2026-09-29 실측).
RUN PIP_CONSTRAINT=/pip-base-constraints.txt pip install --no-cache-dir -U \
    pip setuptools wheel \
    jupyterlab jupyterlab_widgets ipykernel ipywidgets \
    huggingface_hub hf_transfer \
    numpy scipy matplotlib pandas scikit-learn seaborn requests tqdm pillow pyyaml \
    sympy networkx

# Install the PyTorch stack. TORCH_VERSION="nightly" triggers the nightly wheel
# index; every other value installs pinned wheels from the stable index. All
# targets including cu130 are pinned today -- the nightly path is kept as an
# escape hatch for the next time a stable wheel is broken on new hardware (it
# was used for cu130 while torch 2.10.0's bundled cuBLAS mishandled sm_120).
# Either way, the constraints file is generated from the *actually installed*
# versions so the downstream custom-node installs don't accidentally pull a
# different stack.
ARG TORCH_VERSION
# torchaudio must match torch exactly; torchvision uses its own
# 0.{torch minor+15}.{patch} version line and is passed separately.
ARG TORCHVISION_VERSION=0.23.0
ARG CUDA_VERSION
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

# 전체 pip 잠금 — ComfyUI·Manager requirements, custom node requirements, install.py 안의 pip 에 적용되고,
# 빌드 마지막 검사 단계가 설치 목록 전체를 이 파일과 대조한다. torch 아래에 두는 이유는 위 기반 잠금 주석.
ARG PIP_LOCK_FILE=constraints/none.txt
COPY ${PIP_LOCK_FILE} /pip-lock.txt
RUN sed -E '/^[[:space:]]*(#|$)/d; / @ /d' /pip-lock.txt > /pip-constraints.txt && \
    echo "[build] pip lock ${PIP_LOCK_FILE}: $(wc -l < /pip-constraints.txt) constraints"

# Install ComfyUI and ComfyUI Manager.
# 앱 코드는 /opt/ComfyUI — **볼륨이 붙는 자리(/workspace) 밖**에 둔다. 데이터 폴더(models·input·output·
# user·custom_nodes)는 여전히 /workspace/ComfyUI 이고, post_start.sh 가 `--base-directory` 로 ComfyUI 에
# 알려 준다. 템플릿 semantic path 선언(WSB seed_k8s_templates.py)이 전부 그 데이터 폴더 아래라 플랫폼 쪽은
# 그대로다.
#
# 앱 위치의 이력: 처음엔 /ComfyUI 에 만들고 pre_start.sh 가 매 기동마다 /workspace/ComfyUI 로 rsync 했다
# (1.38GiB 가 쓰기 레이어에 쌓임). 그다음엔 /workspace/ComfyUI 에 바로 구웠는데, 유저가 볼륨을 /workspace
# (RunPod 관례이자 콘솔의 마운트 경로 안내 예시)나 /workspace/ComfyUI 에 붙이면 앱 트리가 통째로 가려져
# `main.py` 를 못 찾고 ComfyUI 만 죽었다 — Jupyter·code-server 는 살아 있어 Pod 는 정상처럼 보였다
# (2026-09-27). 플랫폼은 그 배치를 정상으로 본다: 조상 경로 볼륨이 하위 semantic path 전부의 저장소가 된다.
#
# user/ 는 ComfyUI sqlite DB 자리다. post_start.sh 와 호환 shim 이 `--database-url` 로 여기
# (/opt/ComfyUI/user/comfyui.db)를 준다 — v0.37.0 기본값인 유저 폴더(= 데이터 폴더)는 NFS 일 수 있어서다
# (같은 볼륨을 쓰는 Pod 끼리 DB 잠금이 부딪친다). 이 폴더는 ComfyUI 도 만들지만 자리를 분명히 해 둔다.
#
# ComfyUI release tag to check out. Pinning makes it obvious which version a
# given image shipped, and bumping this value invalidates the clone layer's
# build cache so a rebuild actually picks the new version up. Set to "master"
# to track the tip instead.
# 선언이 여기 있으므로 이 값을 올려도 위쪽(apt/uv/python/torch) 캐시는 살아있다.
ARG COMFYUI_VERSION=v0.37.4
# ComfyUI-Manager 도 커밋을 고정한다. 예전에는 기본 브랜치 HEAD 를 받았다.
#   - 왜: 2026-09-23 하루에 빌드 4번이 서로 다른 커밋을 받았고(16989582 → 30fc9660 → db76cf00 → 73bbe810),
#     같이 낼 cu128/cu130 후보끼리도 달랐다. 그날 차이는 노드 DB 뿐이었지만, 9/18 에는 보안 관련 동작 변경
#     (#3298 비-loopback 리스너의 flagged 노드 설치 제한, #3296 UI 인젝션 수정)이 검토 없이 따라 들어왔다.
#   - 값: 검증된 rc0928a 이미지에 실제로 들어간 커밋이다 (그 이미지 안에서 `git rev-parse HEAD`).
#   - `reset --hard` 인 이유는 custom_nodes.txt 와 같다. 브랜치(main)에 붙은 채 upstream 보다 뒤인 평범한
#     상태라 pod 안에서 Manager 의 자기 업데이트(`git pull`)가 그대로 된다. detach 하면 Manager 는 "항상
#     업데이트 있음"으로 보고, 업데이트할 때 기본 브랜치로 강제 전환한다 (manager_core.py).
#   - URL 은 ltdrdata 그대로 둔다. repo 는 Comfy-Org 로 옮겨져 GitHub 리다이렉트로 받는다. 그래도 Manager
#     노드 DB 의 자기 항목이 ltdrdata URL 이고, 이미지 안 .git/config 도 검증본과 같게 유지된다. 리다이렉트가
#     끊겨 다른 repo 를 받게 되면 그 repo 에 이 SHA 가 없어 빌드가 멈춘다.
#   - 올릴 때: docker-bake.hcl 의 COMFYUI_MANAGER_SHA 를 바꾸고 이미지를 다시 검증한다.
ARG COMFYUI_MANAGER_SHA=9c29dc68a488fd56e15f152807579009d627bfef
RUN export PIP_CONSTRAINT=/pip-constraints.txt && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    git checkout "${COMFYUI_VERSION}" && \
    echo "ComfyUI pinned to ${COMFYUI_VERSION} ($(git rev-parse --short HEAD))" && \
    mkdir -p user && \
    pip install --no-cache-dir --constraint /pytorch-constraints.txt -r requirements.txt && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git custom_nodes/ComfyUI-Manager && \
    git -C custom_nodes/ComfyUI-Manager reset --hard --quiet "${COMFYUI_MANAGER_SHA}" && \
    echo "ComfyUI-Manager pinned to $(git -C custom_nodes/ComfyUI-Manager rev-parse --short HEAD)" && \
    cd custom_nodes/ComfyUI-Manager && \
    pip install --no-cache-dir --constraint /pytorch-constraints.txt -r requirements.txt

COPY custom_nodes.txt /custom_nodes.txt

# custom_nodes 설치를 3개 RUN 으로 나눴다. **실행 순서는 기존과 완전히 동일**하다
# (clone 전체 → requirements 전체 → install.py 전체). 저장소를 그룹으로 쪼개면 pip
# 해석 순서가 바뀌므로 그렇게 하지 않았다. 나누는 이유는 pull 병렬성이다:
# containerd 는 max_concurrent_downloads=3 / max_concurrent_unpacks=1 인데
# (2026-09-22 gpu-dev 실측) 6.0GB 짜리 단일 레이어는 다운로드 슬롯 하나만 쓰면서
# 나머지 둘을 놀린다. 같은 노드에서 잰 CloudFront 처리량은 1스트림 14.7~19.5MiB/s,
# 3스트림 46.4~49.8MiB/s, 6스트림 65.7MiB/s 로 **스트림당 대역이 상한**이었다.
ARG SKIP_CUSTOM_NODES
# custom_nodes.txt 는 "<url> <sha>" 형식이다 (핀 사유는 그 파일 헤더 참조).
# `xargs -n 1 git clone` 을 못 쓰는 이유: SHA 를 두 번째 URL 로 넘겨버린다.
#
# 핀 적용은 `checkout --detach` 가 아니라 **`reset --hard`** 를 쓴다. detach 하면
# ComfyUI-Manager 가 보는 상태가 바뀌어(브랜치 없음) 업데이트 경로가 달라지는데,
# reset 은 기본 브랜치 ref 를 그 커밋으로 되돌리므로 "브랜치에 붙어 있고 upstream 보다
# N 커밋 뒤" 라는 평범한 상태가 되고 Manager 의 `git pull` 이 그대로 fast-forward 된다.
#
# `set -e` + 파이프 아닌 리다이렉트(`< /custom_nodes.txt`)인 이유: while 루프를 현재 셸에서
# 돌려야 clone/reset 실패가 RUN 을 실패시킨다. 기존 `xargs` 도 실패를 전파했으므로(exit 123)
# 그 성질을 유지하는 것이다 — 파이프로 넘기면 서브셸이 되어 조용히 성공한다.
# `|| [ -n "$url" ]` 는 마지막 줄에 개행이 없어도 처리하기 위한 것이다.
RUN if [ -z "$SKIP_CUSTOM_NODES" ]; then \
        set -e; \
        cd /opt/ComfyUI/custom_nodes; \
        while read -r url sha _rest || [ -n "$url" ]; do \
            case "$url" in ''|'#'*) continue ;; esac; \
            dir=$(basename "$url" .git); \
            if [ -z "$sha" ]; then \
                echo "[build] WARNING: $dir has no pinned SHA, using default branch HEAD" >&2; \
                git clone --quiet "$url" "$dir"; \
            else \
                echo "[build] $dir @ $sha"; \
                git clone --quiet "$url" "$dir"; \
                git -C "$dir" reset --hard --quiet "$sha"; \
            fi; \
            git -C "$dir" submodule update --init --recursive --quiet; \
        done < /custom_nodes.txt; \
    else \
        echo "Skipping custom nodes installation because SKIP_CUSTOM_NODES is set"; \
    fi

# requirements 설치 실패를 삼키지 않는다. 예전의 `find ... -exec pip install ... \;` 는 pip 가 실패해도
# find 가 0 으로 끝나 빌드가 조용히 성공했다 (`-exec ... \;` 의 종료코드는 명령 결과와 무관하고 `+` 형태만
# 전파한다 — 2026-09-23 실측). 그래서 파일마다 설치하고 실패를 모아 끝에 RUN 을 실패시킨다.
#   - 순서는 예전과 같은 `find` 순회 순서다. 정렬하지 않는다 — 같은 모듈 폴더를 공유하는 배포판
#     (onnxruntime ↔ onnxruntime-gpu, opencv 3종)은 나중에 깔린 쪽 파일이 남으므로 순서가 결과를 바꾼다.
#   - comfyui-prompt-reader-node 의 git 서브모듈 stable_diffusion_prompt_reader/requirements.txt 는
#     건너뛴다. 독립 GUI 앱용 목록이고 `Pillow~=10.3.0` 이 cp313 휠이 없어 소스 빌드가 실패한다 — 예전
#     빌드도 매번 여기서 조용히 실패했고 그 파일에서는 아무것도 깔리지 않았다. 노드 자체는 이미지의 Pillow
#     로 로드된다 (2026-09-23 노드 로드 검사).
RUN if [ -z "$SKIP_CUSTOM_NODES" ]; then \
        export PIP_CONSTRAINT=/pip-constraints.txt; \
        failed=""; \
        while IFS= read -r -d '' req; do \
            case "$req" in \
                */comfyui-prompt-reader-node/stable_diffusion_prompt_reader/requirements.txt) \
                    echo "[build] skip $req (standalone app requirements)"; continue ;; \
            esac; \
            echo "[build] pip install -r $req"; \
            pip install --no-cache-dir --constraint /pytorch-constraints.txt -r "$req" || failed="$failed $req"; \
        done < <(find /opt/ComfyUI/custom_nodes -name requirements.txt -print0); \
        if [ -n "$failed" ]; then echo "[build] requirements install failed:$failed" >&2; exit 1; fi; \
        # TensorRT 의 Windows 크로스빌드용 builder resource 를 버린다 (2026-09-22 실측
        # 1.947GB, 8개 파일: win_sm75/80/86/89/90/100/120/ptx). 리눅스 컨테이너에서
        # Windows 엔진을 굽는 경로는 존재하지 않으므로 쓰이지 않는다. **이 파일들을 만든
        # RUN 과 같은 RUN 에서** 지워야 레이어에 안 남는다 — 다음 RUN 에서 지우면 whiteout
        # 만 생기고 바이트는 그대로 배포된다. glob 이 안 맞아도 `rm -f` 는 0 을 반환하므로
        # tensorrt 가 안 깔린 경우에도 안전하다.
        rm -f /venv/lib/python*/site-packages/tensorrt_libs/libnvinfer_builder_resource_win_*.so.*; \
    fi

# install.py 도 같은 방식으로 실패를 모은다 (실행 방식·순서는 예전 `-exec python {} \;` 와 같다).
# PIP_CONSTRAINT 를 export 하는 이유: install.py 가 서브프로세스로 부르는 pip(os.system)은 명령줄
# --constraint 를 못 받지만 환경변수는 물려받는다.
# ⚠️ 종료코드로 못 잡는 실패가 남는다. ComfyUI-Frame-Interpolation 의 install.py 는 cupy 설치(cupy-wheel
#    소스 빌드)가 실패해도 os.system 결과를 버리고 0 으로 끝난다. 그래서 cupy 를 쓰는 VFI 노드 4개(GMFSS
#    Fortuna·M2M·Sepconv·STMFNet)는 실행할 때 실패한다 — 라이브 이미지도 같은 알려진 상태다. 이 실패는
#    빌드가 잡지 못한다. 대신 설치 목록이 잠금과 달라지는 실패는 빌드 마지막 잠금 대조가 잡는다.
RUN if [ -z "$SKIP_CUSTOM_NODES" ]; then \
        export PIP_CONSTRAINT=/pip-constraints.txt; \
        failed=""; \
        while IFS= read -r -d '' inst; do \
            echo "[build] python $inst"; \
            python "$inst" || failed="$failed $inst"; \
        done < <(find /opt/ComfyUI/custom_nodes -name install.py -print0); \
        if [ -n "$failed" ]; then echo "[build] install.py failed:$failed" >&2; exit 1; fi; \
    fi && \
    # 빌드 타임 pip 캐시 제거(2.82GB). 위 pip 은 전부 --no-cache-dir 이지만 custom node 의 install.py 가
    # 서브프로세스로 부르는 pip 은 그걸 상속하지 않아 여기서만 쌓인다 (예: ComfyUI-Frame-Interpolation
    # 의 os.system("... -m pip install cupy ...")). 같은 RUN 이어야 레이어에 안 남고, `fi` 뒤여야
    # SKIP_CUSTOM_NODES 인 slim-* 타겟에서도 실행된다. `|| true` 를 붙이면 안 된다 —
    # `A || true && C` 는 `(A||true) && C` 라 위 if 블록의 실패까지 삼켜 빌드가 조용히 성공한다.
    echo "[build] pruning pip cache: ${PIP_CACHE_DIR}" && \
    rm -rf "${PIP_CACHE_DIR:?}"

# Custom node dependencies may pull a different PyTorch wheel from PyPI, so the
# CUDA-specific stack has to be re-asserted after those installs.
#
# ⚠️ 예전에는 여기서 조건 없이 `pip install --force-reinstall` 을 돌렸다. 그러면 드리프트가
# 없어도 /venv 의 torch 파일을 전부 다시 쓰는데, 그 파일들은 하위 레이어에 있으므로
# overlayfs 가 통째로 copy-up 한다 → **torch 사본이 이미지에 두 번 들어간다.**
# 2026-09-22 실측: cu128 은 L20 3.984GB + L25 4.016GB 가 서로 다른 digest 로 둘 다
# 배포됐고(실제로 쓰이는 건 L25 뿐), cu130 은 L23 2.773GB + L28 2.803GB 였다.
#
# 게다가 그 재설치는 할 일이 없었다 — custom_nodes 레이어(6.0GB, 26,072 파일)를 전수
# 조사한 결과 torch/torchvision/torchaudio/nvidia-*/triton 파일이 **하나도 없다**
# (유일한 매치는 무관한 nvidia_ml_py.dist-info 10KB). 위 `--constraint` 가 이미 제
# 역할을 하고 있다는 뜻이다.
#
# 그래서 **무조건 재설치 대신 검증 후 필요할 때만 복구**한다. 사후 조건은 동일하고
# (torch 가 고정된 CUDA 휠과 일치), 평시에는 이 레이어가 수 KB 로 줄어든다. 비교 대상은
# 최초 설치 직후 기록해 둔 /pytorch-constraints.txt 라 버전 표기 방식과 무관하며
# nightly 분기에서도 그대로 동작한다. import 자체가 깨져도, 파일이 없어도 복구 경로로 간다.
# 이 레이어가 언젠가 다시 GB 급으로 커지면 그건 custom node 가 스택을 건드렸다는 신호다.
RUN if python -c "import sys, torch, torchvision, torchaudio; \
        want = dict(l.strip().split('==') for l in open('/pytorch-constraints.txt') if l.strip()); \
        got = {'torch': torch.__version__, 'torchvision': torchvision.__version__, 'torchaudio': torchaudio.__version__}; \
        sys.exit(0 if want == got else 1)"; then \
        echo "[build] pytorch stack intact after custom-node installs; skipping re-install"; \
    elif [ "${TORCH_VERSION}" = "nightly" ]; then \
        echo "[build] pytorch stack drifted; re-asserting nightly wheels"; \
        pip install --no-cache-dir --pre --force-reinstall \
            torch torchvision torchaudio \
            --index-url "https://download.pytorch.org/whl/nightly/${CUDA_VERSION}"; \
    else \
        echo "[build] pytorch stack drifted; re-asserting pinned wheels"; \
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

# Stage frontend-only custom extensions. Only meshive-autoload remains; the
# per-preset *-autoload extensions were removed with the preset baking.
COPY custom_extensions/ /custom_extensions/

# 이미지 안 경로를 ComfyUI 에 알려 주는 설정. ComfyUI 는 `--base-directory /workspace/ComfyUI` 로 뜨므로
# 기본 경로가 전부 데이터 폴더를 가리킨다 — 동봉 config yaml(models/configs)은 이 파일이 두 번째 경로로
# 덧붙인다. main.py 가 **앱 폴더의** extra_model_paths.yaml 을 자동으로 읽는다 (내용·사유는 파일 주석).
# 이미지 내장 custom node 는 여기 넣지 않는다 — 데이터 쪽 custom_nodes 의 링크로 읽힌다(아래 호환 폴더).
COPY config/extra_model_paths.yaml /opt/ComfyUI/extra_model_paths.yaml

# meshive-autoload 를 이미지 내장 custom node 폴더(/opt/ComfyUI/custom_nodes)에 설치한다 — ComfyUI 는
# 데이터 쪽 custom_nodes 에 걸린 링크로 이 폴더를 읽는다. 열 대상을 빌드 시점에 고정하지 않고 런타임 시드 마커
# (`.meshive/seeded/` 중 `bundled-` 접두사가 **아닌** 것 = asset set 스타터)에서
# 찾으므로, 붙인 asset set 의 workflow 를 열고 없으면 조용히 no-op 이 된다.
#
# 2026-09-22: BAKE_PRESET 기반 프리셋 굽기를 제거했다. 프리셋 5종은 2026-09-04 에
# 퇴역됐고(WSB seed_k8s_templates.py RETIRED_OFFICIAL_IMAGES) Quick Deploy 는 base
# 이미지 + input asset 으로 대체됐다. 퇴역 사유 자체가 크기였다 — 16~31GB 단일
# 모델 레이어가 콜드 pull 15분을 넘겨 real 배포 사고(tx 73127)를 냈다.
RUN cp -r /custom_extensions/meshive-autoload /opt/ComfyUI/custom_nodes/meshive-autoload &&     rm -rf /custom_extensions

# 옛 경로 호환 — /workspace/ComfyUI 를 옛 앱 폴더처럼 보이게 굽는다. 볼륨이 /workspace 나 /workspace/ComfyUI
# 를 덮지 않을 때만 보인다(덮으면 그 볼륨이 데이터 폴더가 되고, 기본 기동은 이 모양에 기대지 않는다).
# real 에 이 경로를 앱 폴더로 전제하는 유저 부트스트랩이 있다 — main.py 실행, comfy/cli_args.py 검사,
# custom_nodes 에 자기 노드를 심링크로 걸고 같은 이름의 내장 노드를 치우는 것까지 한다. 그래서:
#   - main.py            : --base-directory /workspace/ComfyUI 로 /opt/ComfyUI/main.py 를 실행하는 shim
#   - custom_nodes/      : 실제 폴더. 내장 노드마다 /opt/ComfyUI/custom_nodes/<이름> 심링크 (쓰기·교체 가능).
#                          ComfyUI 는 이 폴더 하나에서만 노드를 읽는다 — 볼륨이 이 폴더를 덮으면 post_start.sh
#                          가 같은 링크를 볼륨 쪽에 건다.
#   - 그 밖의 앱 파일·폴더: /opt/ComfyUI/<이름> 심링크 (comfy/, server.py, requirements.txt ...)
# 데이터 폴더(models·input·output·user)와 앱 쪽 설정 파일(extra_model_paths.yaml)은 만들지 않는다 — models/*
# 등은 LV 마운트 지점이라 실제 폴더여야 하고, 설정 파일을 노출하면 start.sh 가 그걸 데이터 쪽 설정으로
# 읽는다. 점 파일(.git 등)은 glob 에 안 걸려 빠진다.
COPY config/compat_main.py /workspace/ComfyUI/main.py
RUN set -e; \
    mkdir -p /workspace/ComfyUI/custom_nodes; \
    for entry in /opt/ComfyUI/*; do \
        name=$(basename "$entry"); \
        case "$name" in \
            main.py|custom_nodes|models|input|output|user|temp|extra_model_paths.yaml) continue ;; \
        esac; \
        ln -s "$entry" "/workspace/ComfyUI/$name"; \
    done; \
    for node in /opt/ComfyUI/custom_nodes/*; do \
        ln -s "$node" "/workspace/ComfyUI/custom_nodes/$(basename "$node")"; \
    done

# Welcome Message
# The greeting text lives inside meshive.txt (blank separator line and
# trailing newline included) so the banner does not depend on `echo -e`
# escape handling, which is shell-dependent and was collapsing the newline.
COPY logo/meshive.txt /etc/meshive.txt
RUN echo 'cat /etc/meshive.txt' >> /root/.bashrc

# 런타임 전용 ENV. 파일 맨 아래에 둔다 — ENV 도 그 아래 RUN 들의 캐시 키에
# 들어가므로 위에 두면 ARG 를 내려 얻은 캐시 이득이 그대로 사라진다. 여기 아래로는 RUN 이 없다.
# 소비자: ensure_pytorch_stack.sh (TORCH_VERSION/TORCHVISION_VERSION/CUDA_VERSION),
# download_presets.sh (PRESET_DOWNLOAD). PYTORCH_STACK_ID 는 진단용 기록이다.
# Comma-separated list of presets to download into the model mount at runtime.
ARG DEFAULT_PRESET_DOWNLOAD=""
ENV TORCH_VERSION=${TORCH_VERSION}
ENV TORCHVISION_VERSION=${TORCHVISION_VERSION}
ENV CUDA_VERSION=${CUDA_VERSION}
ENV PYTORCH_STACK_ID="python-${PYTHON_VERSION}-torch-${TORCH_VERSION}-torchvision-${TORCHVISION_VERSION}-${CUDA_VERSION}"
ENV PRESET_DOWNLOAD=${DEFAULT_PRESET_DOWNLOAD}

# Set entrypoint to the start script
CMD ["/start.sh"]

# ── 빌드 마지막 검사 (별도 단계) ─────────────────────────────────────────────────────────────
# 위 이미지를 그대로 받아 세 가지를 확인하고, 하나라도 실패하면 빌드 전체를 실패시킨다. 별도 단계에서 하는
# 이유: ComfyUI 를 한 번 띄우면 로그·DB·캐시 같은 부산물이 생기는데, 그걸 이미지 레이어에 남기지 않으려는
# 것이다. 최종 이미지는 이 단계가 만든 표지 파일 하나만 받는다 (아래 마지막 `FROM image`).
#   1) 노드 로드: `main.py --quick-test-for-ci` 로 이미지 안 custom node 를 전부 불러 IMPORT FAILED 가
#      없는지 본다 (2026-09-29 rc0928a 에서 26개 로드, 25초). 로드가 /venv 를 바꾸면(런타임 자동 설치)
#      그것도 실패로 본다 — 그러면 모든 pod 가 기동마다 설치를 하게 된다.
#   2) 잠금 대조: 설치 목록(`pip freeze --all`, torch 셋 제외)이 PIP_LOCK_FILE 과 정확히 같은지 본다.
#      잠금이 비었거나(none.txt) custom node 를 안 까는 slim 타깃이면 건너뛴다.
#   3) 모듈 폴더를 공유하는 배포판의 승자: onnxruntime ↔ onnxruntime-gpu, opencv 3종은 같은 폴더를 쓰고
#      나중에 깔린 쪽 파일이 남는다. 버전이 같으면 2) 는 통과하므로, 실제로 남은 쪽을 따로 본다 — GPU 빌드의
#      CUDAExecutionProvider 와 opencv-contrib 모듈(rc0928a 실측 상태). 설치 순서는 find 의 디렉터리 순회
#      순서라 빌더 파일시스템이 바뀌면 뒤집힐 수 있다 (2026-09-29 리뷰). slim 타깃은 건너뛴다.
# 알려진 한계: 실행할 때만 import 하는 의존성(예: Frame-Interpolation 의 cupy)은 1) 로 못 잡는다.
FROM image AS node-check
ARG SKIP_CUSTOM_NODES
ARG PIP_LOCK_FILE=constraints/none.txt
RUN set -e; \
    pip freeze --all > /tmp/freeze-before.txt; \
    cd /opt/ComfyUI; \
    timeout 900 python main.py --cpu --quick-test-for-ci --base-directory /workspace/ComfyUI \
        > /tmp/node-check.log 2>&1 || { tail -n 80 /tmp/node-check.log; exit 1; }; \
    if grep -n "IMPORT FAILED" /tmp/node-check.log; then tail -n 80 /tmp/node-check.log; exit 1; fi; \
    echo "[node-check] custom node entries loaded: $(awk '/Import times for custom nodes/,0' /tmp/node-check.log | grep -c seconds)"; \
    pip freeze --all > /tmp/freeze-after.txt; \
    if ! diff /tmp/freeze-before.txt /tmp/freeze-after.txt; then \
        echo "[node-check] loading custom nodes changed /venv" >&2; exit 1; \
    fi; \
    if [ -z "$SKIP_CUSTOM_NODES" ] && grep -q -v -E '^[[:space:]]*(#|$)' /pip-lock.txt; then \
        grep -v -E '^(torch|torchvision|torchaudio)==' /tmp/freeze-after.txt | sort > /tmp/lock-actual.txt; \
        sed -E '/^[[:space:]]*(#|$)/d' /pip-lock.txt | sort > /tmp/lock-expected.txt; \
        if ! diff /tmp/lock-expected.txt /tmp/lock-actual.txt; then \
            echo "[lock-check] installed packages differ from ${PIP_LOCK_FILE} (regenerate: see its header)" >&2; exit 1; \
        fi; \
        echo "[lock-check] installed packages match ${PIP_LOCK_FILE} ($(wc -l < /tmp/lock-expected.txt) lines)"; \
    fi; \
    if [ -z "$SKIP_CUSTOM_NODES" ]; then \
        python -c "import sys, onnxruntime, cv2; p = onnxruntime.get_available_providers(); \
            contrib = hasattr(cv2, 'ximgproc'); \
            print('[node-check] onnxruntime providers:', p, '| opencv-contrib:', contrib); \
            sys.exit(0 if 'CUDAExecutionProvider' in p and contrib else 1)" \
        || { echo "[node-check] onnxruntime-gpu or opencv-contrib files were overwritten by a sibling package" >&2; exit 1; }; \
    fi; \
    touch /node-check.ok

# 최종 이미지 = 위 `image` 단계 + 검사 통과 표지. 검사 단계를 빌드에 끌어들이는 게 이 COPY 의 역할이다
# (BuildKit 은 최종 단계가 참조하는 단계만 빌드한다). CMD·ENV 등 설정은 `image` 에서 그대로 이어받는다.
FROM image
COPY --from=node-check /node-check.ok /etc/meshive/node-check.ok
