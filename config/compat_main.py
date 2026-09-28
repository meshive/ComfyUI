"""옛 경로 호환 shim — Dockerfile 이 /workspace/ComfyUI/main.py 로 복사한다.

앱 코드는 /opt/ComfyUI 로 옮겼다 (Dockerfile 의 ComfyUI 설치 주석 참조). 그런데 `python
/workspace/ComfyUI/main.py ...` 나 `cd /workspace/ComfyUI && python main.py ...` 처럼 옛 경로로 ComfyUI 를
직접 띄우는 유저 부트스트랩이 real 에 있어서 이 파일을 둔다. 이미지의 기본 기동(post_start.sh)은 이 파일을
쓰지 않는다.

옛 이미지에서 /workspace/ComfyUI 가 앱 폴더였을 때와 같은 데이터 경로로 뜨게 하려고 다음을 한 뒤
/opt/ComfyUI/main.py 를 같은 프로세스에서 실행한다:
  - `--base-directory /workspace/ComfyUI` 를 붙인다 (인자에 이미 있으면 유저 값을 따른다)
  - `--database-url` 을 로컬 파일(/opt/ComfyUI/user/comfyui.db)로 붙인다 (인자에 있으면 유저 값). v0.37.0 은
    DB 를 유저 폴더에 두는데, --user-directory 를 NFS 로 주는 부트스트랩이면 sqlite 가 NFS 위에 생긴다.
    v0.31.0 까지는 앱 폴더 기준이라 로컬이었다 — 그 동작을 유지한다.
  - /workspace/ComfyUI/extra_model_paths.yaml 이 있으면 넘긴다 (옛 앱 폴더라 ComfyUI 가 자동으로 읽던 파일)
  - custom_nodes 폴더를 만든다 (없으면 ComfyUI 가 기동 중 os.listdir 에서 죽는다)
  - 작업 폴더를 /opt/ComfyUI 로 옮긴다 (post_start.sh 와 같은 조건으로 실행되게)

/workspace 나 /workspace/ComfyUI 에 볼륨을 붙이면 이 파일도 가려진다. 그 배치에서는 옛 이미지도
main.py 를 찾지 못했으므로 달라지는 것은 없다.
"""
import os
import runpy
import sys

APP_DIR = "/opt/ComfyUI"
DATA_DIR = "/workspace/ComfyUI"

user_args = sys.argv[1:]


def has_flag(name):
    return any(arg == name or arg.startswith(name + "=") for arg in user_args)


injected = []
if not has_flag("--base-directory"):
    injected += ["--base-directory", DATA_DIR]
if not has_flag("--database-url"):
    injected += ["--database-url", "sqlite:///" + os.path.join(APP_DIR, "user", "comfyui.db")]
data_paths_config = os.path.join(DATA_DIR, "extra_model_paths.yaml")
if os.path.isfile(data_paths_config):
    injected += ["--extra-model-paths-config", data_paths_config]

os.makedirs(os.path.join(DATA_DIR, "custom_nodes"), exist_ok=True)

main_py = os.path.join(APP_DIR, "main.py")
# ComfyUI-Manager 의 재시작은 sys.argv 로 자기 자신을 다시 exec 하므로, 여기서 바꾼 argv 가 그대로
# 이어진다 (재시작 뒤에도 같은 경로로 뜬다).
sys.argv = [main_py] + injected + user_args
# 스크립트 폴더(/workspace/ComfyUI) 대신 앱 폴더를 import 기준으로 한다.
sys.path[0] = APP_DIR
os.chdir(APP_DIR)
runpy.run_path(main_py, run_name="__main__")
