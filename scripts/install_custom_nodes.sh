#!/bin/bash

echo "==== Installing ComfyUI custom nodes ===="

# 이미지 내장 노드와 같은 폴더(/opt/ComfyUI/custom_nodes)에 받는다 — slim 이미지에서 base 의 노드
# 구성을 런타임에 채우는 용도라서다. 유저가 따로 까는 노드는 /workspace/ComfyUI/custom_nodes 로 간다.
cd /opt/ComfyUI/custom_nodes

xargs -n 1 git clone --recursive < /custom_nodes.txt

find /opt/ComfyUI/custom_nodes -name "requirements.txt" -exec pip install --no-cache-dir --constraint /pytorch-constraints.txt -r {} \;

find /opt/ComfyUI/custom_nodes -name "install.py" -exec python {} \;

echo "==== Custom nodes installation complete ===="
