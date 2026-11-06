#!/usr/bin/env python3
"""내장 Manager(comfyui_manager 4.x)의 config.ini 에 network_mode = personal_cloud 를 시드한다.

사용: seed_manager_config.py <ComfyUI 유저 폴더>
  - Dockerfile 이 /seed_manager_config.py 로 복사한다. post_start.sh 가 `$COMFYUI_DATA/user` 로, 옛 경로 shim
    (/workspace/ComfyUI/main.py)이 자기가 띄우는 ComfyUI 의 유저 폴더로 부른다. 둘 다 ComfyUI 를 띄우기 전이다 —
    Manager 는 이 파일을 기동할 때 한 번 읽는다(바꾸면 재시작해야 반영).
  - 쓰는 파일은 <유저 폴더>/__manager/config.ini 다. 4.3 context.py 가 folder_paths.get_system_user_directory("manager")
    를 쓰고, ComfyUI 는 `--user-directory` 가 있으면 그 폴더, 없으면 `--base-directory` 아래 user 를 유저 폴더로 쓴다.
    v3.42 레거시 Manager 도 같은 파일을 썼다.

왜: Pod 의 ComfyUI 는 `--listen`(0.0.0.0,::) 이라 Manager 가 비-loopback 으로 보고, 기본값 public 이면 nightly 설치·
Registry 에 없는(노드 DB 의 git) 노드 설치, update all, 스냅샷 복원을 막는다(4.3 은 stable CNR 설치만 허용).
personal_cloud 면 레거시 v3.42 때와 같은 수준으로 풀린다. 사유는 docker-bake.hcl 의 COMFYUI_MANAGER_VERSION 주석.

규칙:
  - 파일이 없거나 [default] 가 없으면 만든다. 넣는 키는 network_mode 와 use_uv·file_logging 셋이다. 4.3 read_config 는
    [default] 가 있으면 없는 키를 기본값으로 채워 읽지만, 불리언(get_bool)은 기본값 인자를 무시하고 False 로 읽는다.
    파일이 아예 없을 때의 기본값이 True 인 불리언이 그 둘이라(use_uv 는 uv 모듈이 있으면 True — comfyui_manager
    의존성이라 늘 있다), 빼면 파일이 없을 때와 달리 uv 대신 pip 을 쓰고 파일 로그를 끈다. 나머지 키는 없어도 기본값과
    같게 읽힌다. Manager 는 파일이 없을 때만 전체 기본값을 써 넣으므로(glob/manager_server.py) 시드한 파일에는 나머지
    키가 안 생긴다.
  - [default] 가 있으면 network_mode 만 본다. Manager 는 그 값을 소문자로 바꿔 읽고(read_config 의 .lower(), configparser
    가 앞뒤 공백을 뗀다) public·private·offline·personal_cloud 넷만 안다(common/enums.py NetworkMode). 남겨 두는 값은
    private·offline·personal_cloud(대소문자 무시) 셋뿐이다. 나머지 — public(v3·v4 기본값), 키 없음, 빈 값, 모르는 값 —
    는 personal_cloud 로 바꾼다. 빈 값·모르는 값도 Manager 는 personal_cloud 로 보지 않으므로 보안 검사에서는 public 과
    같다. public 을 일부러 고른 경우도 기본값과 구분할 수 없어 바뀐다. 다른 키는 그대로 둔다.
    private·offline 을 남기면 4.3 에서는 비-loopback 리스너라 public 과 같은 설치 제한을 받는다(security_utils 가
    personal_cloud 만 'middle+' 를 연다). v3.42 의 private·offline 은 보안 검사와 무관했으므로(network_mode 는 registry
    를 받는 방식 — 기다리지 않기·reload 생략·offline 캐시 — 에만 쓰였다), v3.42 때 이 값을 둔 볼륨은 그때 되던 nightly·
    노드 DB git 설치·Update All 이 막힌다. 유저가 고른 값이라 바꾸지 않는다 — 풀려면 personal_cloud 로 직접 바꾼다.
  - 다시 쓸 때는 같은 폴더의 임시 파일을 os.replace 로 바꾸고 기존 권한을 유지한다. INI 주석은 남지 않는다(Manager 의
    자기 저장도 같다). 못 읽는 파일은 그대로 두고 경고만 남긴다.
  - 무엇을 했는지 한 줄을 남긴다. 처리했으면(못 읽어 그대로 둔 경우 포함) 0, 쓰지 못했으면 1 로 끝난다. 부르는 쪽은
    실패해도 ComfyUI 를 그대로 띄운다.
"""
import configparser
import os
import sys
import tempfile

TARGET_MODE = "personal_cloud"
# Manager 4.3 NetworkMode 중 public 을 뺀 값 — 유저가 고른 것으로 보고 그대로 둔다.
KEPT_MODES = ("private", "offline", "personal_cloud")


def warn(message):
    print(f"**** WARN: {message} ****", file=sys.stderr)


def seed(user_dir):
    path = os.path.join(user_dir, "__manager", "config.ini")
    # strict=False 는 Manager 와 같다(중복 키는 마지막 값). interpolation=None 은 값의 % 를 해석하지 않고 그대로 다시
    # 쓰려는 것이다.
    config = configparser.ConfigParser(strict=False, interpolation=None)
    try:
        loaded = config.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError) as exc:
        reason = " ".join(str(exc).split())
        warn(f"ComfyUI-Manager config {path} could not be parsed ({reason}); left as is")
        return 0
    if not loaded and os.path.exists(path):
        warn(f"ComfyUI-Manager config {path} could not be read; left as is")
        return 0

    if not config.has_section("default"):
        config["default"] = {"network_mode": TARGET_MODE, "use_uv": "True", "file_logging": "True"}
        action = "created" if not loaded else f"added [default] (network_mode = {TARGET_MODE}) to"
    else:
        section = config["default"]
        old = section.get("network_mode")
        if old is not None and old.strip().lower() in KEPT_MODES:
            print(f"**** ComfyUI-Manager network_mode = {old.strip()} kept in {path} ****")
            return 0
        section["network_mode"] = TARGET_MODE
        was = "unset" if old is None else repr(old.strip())
        action = f"set network_mode = {TARGET_MODE} (was {was}) in"

    directory = os.path.dirname(path)
    tmp = None
    try:
        os.makedirs(directory, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".config-", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            config.write(f)
        if os.path.exists(path):
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
        os.replace(tmp, path)
    except OSError as exc:
        if tmp is not None:
            try:
                os.remove(tmp)
            except OSError:
                pass
        warn(f"ComfyUI-Manager config {path} could not be written ({exc})")
        return 1
    print(f"**** ComfyUI-Manager {action} {path} ****")
    return 0


def main(argv):
    if len(argv) != 1 or not argv[0]:
        warn("usage: seed_manager_config.py <ComfyUI user directory>")
        return 2
    return seed(argv[0])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
