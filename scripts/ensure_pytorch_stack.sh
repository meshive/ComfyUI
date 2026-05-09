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

: "${TORCH_VERSION:?TORCH_VERSION is required}"
: "${TORCHVISION_VERSION:?TORCHVISION_VERSION is required}"
: "${CUDA_VERSION:?CUDA_VERSION is required}"

python -m pip install --no-cache-dir --force-reinstall \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCH_VERSION}" \
    --index-url "https://download.pytorch.org/whl/${CUDA_VERSION}"

printf "%s\n" "${PYTORCH_STACK_ID:-python-unknown-torch-${TORCH_VERSION}-torchvision-${TORCHVISION_VERSION}-${CUDA_VERSION}}" > /workspace/venv/.pytorch-stack-id

check_stack
echo "**** PyTorch stack repaired ****"
