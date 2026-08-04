#!/bin/bash
set -e

echo "**** Checking PyTorch stack compatibility ****"

check_stack() {
    python - <<'PY'
import sys

try:
    import torch
    import torchvision
    import torchaudio
except Exception as exc:
    print(f"PyTorch stack import failed: {exc!r}", file=sys.stderr)
    sys.exit(1)

print(f"torch={torch.__version__}")
print(f"torchvision={torchvision.__version__}")
print(f"torchaudio={torchaudio.__version__}")
print(f"torch_cuda={torch.version.cuda}")
PY
}

if check_stack; then
    echo "**** PyTorch stack OK ****"
    exit 0
fi

echo "**** PyTorch stack is broken; reinstalling CUDA-specific wheels ****"

# 주의: /venv 는 이제 읽기 전용 이미지 레이어에 있다. --force-reinstall 은 기존 패키지를 먼저
# rename 하는데 overlayfs 에서 lower 레이어 파일 rename 은 copy-up 을 강제하므로, 이 경로가
# 발동하면 구 torch(~5GB) + 신 torch(~5GB) = 피크 ~10GB 가 ephemeral 에 실린다. 평상시 ephemeral
# 이 ~0 이라 25Gi 한도 안에서 안전하고, post_start.sh 에 `set -e` 가 없어 실패해도 pod 은 산다.
# 드물게만 타는 escape hatch 라 수용한다 — 발동 여부는 위 "stack is broken" 로그로 알 수 있다.

: "${TORCH_VERSION:?TORCH_VERSION is required}"
: "${TORCHVISION_VERSION:?TORCHVISION_VERSION is required}"
: "${CUDA_VERSION:?CUDA_VERSION is required}"

python -m pip install --no-cache-dir --force-reinstall \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCH_VERSION}" \
    --index-url "https://download.pytorch.org/whl/${CUDA_VERSION}"

printf "%s\n" "${PYTORCH_STACK_ID:-python-unknown-torch-${TORCH_VERSION}-torchvision-${TORCHVISION_VERSION}-${CUDA_VERSION}}" > /venv/.pytorch-stack-id

check_stack
echo "**** PyTorch stack repaired ****"
