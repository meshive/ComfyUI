import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

// 대시보드를 열자마자 **선택한 asset set 의 스타터 workflow** 를 띄운다.
//
// 왜 필요한가: quick deploy(프리셋 이미지)는 `{preset}-autoload` 가 구워져 있어 바로
// 떴지만, base 이미지는 어떤 asset set 이 붙을지 빌드 시점에 알 수 없어 그게 없었다.
// 유저는 workflow 브라우저를 열고 직접 클릭해야 했다.
//
// 어디서 "무엇을 열지" 를 알아내나 — **새 계약을 만들지 않았다.** 이미 있는 시드 마커를
// 읽는다 (`.meshive/seeded/<slug>` = `{"filename": ..., "sha256": ...}`). 그 디렉토리에는
// 두 종류가 섞여 있고 접두사로 구분된다:
//   · `bundled-*`  → **이미지 동봉 예제** (pre_start.sh 가 놓는다). 이건 열지 않는다 —
//                    base 이미지에는 그 예제가 요구하는 모델이 없어서 열어 봐야 빨간 노드다
//                    (Dockerfile 의 "base/slim images don't auto-load a workflow whose
//                    models they don't have" 와 같은 판단).
//   · 그 외        → **플랫폼 시드** (K8sCS workflow-seed init, slug = 번들 slug).
//                    asset set 을 붙였을 때만 생긴다. 이게 우리가 열 대상이다.
// 접두사 이름 공간은 ComfyUI 이미지가 시드 마커를 쓰기 시작할 때(2026-08-05) 의도적으로
// 갈라 둔 것이라, 여기서 새로 도입하는 규약이 아니다.
//
// 프리셋 이미지에서도 이 확장은 안전하다: 프리셋 템플릿은 `config` semantic path 를
// 선언하지 않아(lora/output 2개뿐) workflow-seed init 자체가 붙지 않는다 →
// `bundled-*` 마커만 존재 → 아래 필터가 전부 걸러 내고 no-op 으로 끝난다. 즉 프리셋의
// 기존 `{preset}-autoload` 와 **동시에 그래프를 건드리는 경합이 생기지 않는다.**
//
// 유저 작업 보존 계약 (기존 `{preset}-autoload` 에서 그대로 가져왔다):
//   · 브라우저당 1회만 — 이후에는 ComfyUI 자신의 탭 복원이 주인이다
//   · 이미 의미 있는 그래프가 열려 있으면 손대지 않는다
//   · **마커는 있는데 파일이 없으면 열지 않는다** — 유저가 지운 것이므로 존중한다
//     (마커의 의미는 "이 slug 는 이 볼륨에서 이미 고려됐다" 이지 "파일이 있다" 가 아니다)
const FLAG = "meshive.autoload.v1";
const SEEDED_DIR = "workflows/.meshive/seeded";
const WORKFLOWS_DIR = "workflows";
const RESTORE_GRACE_MS = 150;

async function listSeedMarkers() {
    const res = await api.fetchApi(
        `/userdata?dir=${encodeURIComponent(SEEDED_DIR)}`);
    if (!res.ok) return [];
    const names = await res.json();
    return Array.isArray(names) ? names : [];
}

async function readJson(path) {
    const res = await api.getUserData(path);
    if (!res.ok) return null;
    return await res.json();
}

app.registerExtension({
    name: "meshive.autoload",
    async setup() {
        if (localStorage.getItem(FLAG)) return;

        // ComfyUI 의 복원(localStorage 의 이전 workflow)이 먼저 끝나게 둔다.
        await new Promise((r) => setTimeout(r, RESTORE_GRACE_MS));

        if ((app.graph?.nodes?.length ?? 0) > 1) {
            // 유저가 이미 뭔가 열어 뒀다 — 덮지 않는다.
            localStorage.setItem(FLAG, "1");
            return;
        }

        try {
            const markers = await listSeedMarkers();
            const slug = markers.find((n) => !n.startsWith("bundled-"));
            if (!slug) {
                // asset set 없이 띄운 base pod — 정상 경로다. 플래그를 세우지 않아
                // 다음 로드에서 다시 확인한다 (요청 1건, 무해).
                return;
            }

            const marker = await readJson(`${SEEDED_DIR}/${slug}`);
            const filename = marker?.filename;
            if (!filename) {
                console.warn("[meshive] seed marker has no filename:", slug);
                return;
            }

            const data = await readJson(`${WORKFLOWS_DIR}/${filename}`);
            if (!data) {
                // 유저가 지운 경우가 대부분이다 (위 '삭제 존중' 참조).
                console.info("[meshive] seeded workflow is gone, not restoring:",
                             filename);
                localStorage.setItem(FLAG, "1");
                return;
            }

            await app.loadGraphData(data);
            localStorage.setItem(FLAG, "1");
            console.log("[meshive] auto-loaded seeded workflow:", filename);
        } catch (e) {
            // 자동 로드는 편의 기능이다 — 어떤 실패도 대시보드를 막지 않는다.
            console.warn("[meshive] auto-load error:", e);
        }
    },
});
