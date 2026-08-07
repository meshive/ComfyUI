"""Frontend-only extension that opens the attached asset set's seeded workflow.

프리셋 전용 `{preset}-autoload` 와 달리 **모든 변형에 설치된다** — 열 대상을 빌드 시점이
아니라 런타임 시드 마커(`.meshive/seeded/`)에서 찾기 때문이다. 열 게 없으면 조용히
no-op 이라 프리셋 이미지에서도 안전하다 (사유는 web/meshive_autoload.js 상단 주석).
"""

WEB_DIRECTORY = "./web"
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
