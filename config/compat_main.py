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
  - `--enable-manager` 를 붙인다 (인자에 `--enable-manager` 나 `--enable-manager-legacy-ui` 가 있으면 그대로 둔다).
    옛 이미지의 Manager 는 custom node(레거시 ComfyUI-Manager)라 인자 없이도 떴지만, 지금은 ComfyUI 내장 Manager
    (pip 패키지 comfyui_manager)라 이 인자가 있어야 켜진다 — post_start.sh 와 같다. 이 인자로 뜨면 이름에
    'comfyui-manager' 가 든 custom node(유저가 직접 둔 레거시 사본 포함)는 로드되지 않는다.
  - custom_nodes 폴더를 만든다 (없으면 ComfyUI 가 기동 중 os.listdir 에서 죽는다)
  - 작업 폴더를 /opt/ComfyUI 로 옮긴다 (post_start.sh 와 같은 조건으로 실행되게)
  - 내장 Manager 의 config.ini 에 network_mode = personal_cloud 를 시드한다 — post_start.sh 와 같은
    /seed_manager_config.py 를, 이 실행에서 ComfyUI 가 쓸 유저 폴더(`--user-directory`, 없으면 `--base-directory`
    아래 user)로 부른다. 실패해도 ComfyUI 는 띄운다.

/workspace 나 /workspace/ComfyUI 에 볼륨을 붙이면 이 파일도 가려진다. 그 배치에서는 옛 이미지도
main.py 를 찾지 못했으므로 달라지는 것은 없다.
"""
import os
import runpy
import subprocess
import sys

APP_DIR = "/opt/ComfyUI"
DATA_DIR = "/workspace/ComfyUI"
SEED_MANAGER_CONFIG = "/seed_manager_config.py"

user_args = sys.argv[1:]


def has_flag(name):
    return any(arg == name or arg.startswith(name + "=") for arg in user_args)


def last_value(name):
    """argparse 처럼 마지막에 준 값을 돌려준다 (`name value` 와 `name=value` 둘 다). 없으면 None."""
    value = None
    for i, arg in enumerate(user_args):
        if arg == name:
            value = user_args[i + 1] if i + 1 < len(user_args) else None
        elif arg.startswith(name + "="):
            value = arg[len(name) + 1:]
    return value


def manager_user_dir():
    """ComfyUI 가 이 인자로 쓸 유저 폴더. 내장 Manager 는 그 아래 __manager/config.ini 를 읽는다.

    ComfyUI 는 둘 다 os.path.abspath 로 구하는데, 그때 작업 폴더는 아래 chdir 뒤의 APP_DIR 이다 — 그래서 chdir 뒤에 부른다.
    """
    user_dir = last_value("--user-directory")
    if user_dir is not None:
        # ComfyUI 는 없는 폴더면 인자 검사에서 멈춘다. 여기서 만들면 그 오류가 사라지므로 시드하지 않는다.
        return os.path.abspath(user_dir) if os.path.isdir(user_dir) else None
    base_dir = last_value("--base-directory")
    return os.path.join(os.path.abspath(DATA_DIR if base_dir is None else base_dir), "user")


def seed_manager_config():
    """/seed_manager_config.py 를 따로 띄운다. 무엇이 잘못돼도 경고만 남기고 ComfyUI 기동은 이어 간다."""
    user_dir = manager_user_dir()
    if user_dir is None:
        return
    try:
        result = subprocess.run([sys.executable, "-I", SEED_MANAGER_CONFIG, user_dir], timeout=60)
        failed = result.returncode != 0
    except (OSError, subprocess.SubprocessError):
        failed = True
    if failed:
        print("**** WARN: could not seed the ComfyUI-Manager config ****", file=sys.stderr, flush=True)


injected = []
if not has_flag("--base-directory"):
    injected += ["--base-directory", DATA_DIR]
if not has_flag("--database-url"):
    injected += ["--database-url", "sqlite:///" + os.path.join(APP_DIR, "user", "comfyui.db")]
data_paths_config = os.path.join(DATA_DIR, "extra_model_paths.yaml")
if os.path.isfile(data_paths_config):
    injected += ["--extra-model-paths-config", data_paths_config]
# 유저가 `--enable-manager` 나 `--enable-manager-legacy-ui`(ComfyUI 안에서 enable_manager 를 함께 켠다)를 직접 줬으면 그
# 조합을 그대로 둔다. 둘 다 없을 때만 post_start.sh 와 같은 `--enable-manager` 를 더한다. `--disable-manager-ui` 와는 배타
# 관계가 아니라 같이 있어도 된다.
if not has_flag("--enable-manager") and not has_flag("--enable-manager-legacy-ui"):
    injected += ["--enable-manager"]

os.makedirs(os.path.join(DATA_DIR, "custom_nodes"), exist_ok=True)

main_py = os.path.join(APP_DIR, "main.py")
# 내장 Manager(comfyui_manager 4.x)의 재시작(/v2/manager/reboot)은 os.execv(sys.executable, [sys.executable] + sys.argv)
# 로 자기 자신을 다시 exec 하므로(v3 레거시 Manager 도 같았다), 여기서 바꾼 argv 가 그대로 이어진다 — 재시작 뒤에도 같은
# 경로·같은 `--enable-manager` 로 뜬다. Manager 가 ComfyUI 위치를 구하는 sys.modules['__main__'].__file__ 은 아래
# runpy.run_path(run_name="__main__") 가 /opt/ComfyUI/main.py 로 둔다.
sys.argv = [main_py] + injected + user_args
# 스크립트 폴더(/workspace/ComfyUI) 대신 앱 폴더를 import 기준으로 한다.
sys.path[0] = APP_DIR
os.chdir(APP_DIR)
# Manager 재시작은 위 argv 로 /opt/ComfyUI/main.py 를 바로 exec 해 이 shim 을 다시 거치지 않는다 — 시드는 처음 기동 때
# 한 번이고, 그 파일이 남아 있으므로 충분하다.
seed_manager_config()
runpy.run_path(main_py, run_name="__main__")
