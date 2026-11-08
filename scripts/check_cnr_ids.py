"""node-check: custom_nodes_cnr.txt 의 `cnr=<id>` 를 내장 Manager 가 실제로 그 id 로 읽는지 확인한다.

Manager 의 identify_node_pack_from_path 는 `/v2/customnode/installed` 가 쓰는 함수다. 여기서 cnr_id 가 비면
프론트 Nodes Manager 가 이미지에 든 팩을 '미설치'로 보인다(사유는 custom_nodes_cnr.txt 헤더).
사용: COMFYUI_PATH=/opt/ComfyUI python check_cnr_ids.py /custom_nodes_cnr.txt
"""
import os
import sys

sys.path.insert(0, "/opt/ComfyUI")
from comfyui_manager.glob import manager_core  # noqa: E402

BASE = "/opt/ComfyUI/custom_nodes"


def main(path: str) -> int:
    checked, bad = 0, []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if not parts or parts[0].startswith("#"):
                continue
            token = next((p for p in parts[1:] if p.startswith("cnr=")), None)
            checked += 1
            if token is None:
                bad.append(f"{parts[0]}: no cnr=<id> on the line")
                continue
            want = token[len("cnr="):]
            name = os.path.basename(parts[0])
            name = name[:-4] if name.endswith(".git") else name
            info = manager_core.identify_node_pack_from_path(os.path.join(BASE, name))
            got = info[2] if info else None
            if got != want:
                bad.append(f"{name}: Manager cnr_id={got!r}, custom_nodes_cnr.txt cnr={want!r}")
    print(f"[node-check] registry ids seen by Manager: {checked - len(bad)}/{checked}")
    if checked == 0:
        print("[node-check] no cnr= entries found in custom_nodes_cnr.txt", file=sys.stderr)
        return 1
    if bad:
        print("\n".join(bad), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
