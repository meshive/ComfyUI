#!/bin/bash

export PYTHONUNBUFFERED=1
set -o pipefail

source /workspace/venv/bin/activate
cd /workspace/ComfyUI

mkdir -p /workspace/logs /workspace/ComfyUI/user
COMFYUI_LOG=/workspace/logs/comfyui_3000.log
ln -sf "$COMFYUI_LOG" /workspace/ComfyUI/user/comfyui_3000.log

/ensure_pytorch_stack.sh

echo "**** Starts ComfyUI, listening on port 3000, with additional arguments specified by COMFYUI_EXTRA_ARGS. ****"
(
    echo "**** ComfyUI process starting at $(date -Is) ****"
    python main.py --listen --port 3000 $COMFYUI_EXTRA_ARGS 2>&1
    status=$?
    echo "**** ComfyUI process exited at $(date -Is) with status ${status} ****"
    exit "$status"
) | tee -a "$COMFYUI_LOG" &
echo "$!" > /workspace/logs/comfyui_3000.pid
