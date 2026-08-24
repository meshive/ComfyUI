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
//
// ── v2: "브라우저당 1회" 에서 "slug 단위 기억" 으로 (2026-08-24) ────────────────
// v1 의 1회성 불리언 플래그는 asset set 을 **교체한** Pod 에서 사고를 만든다: ComfyUI 는
// 미저장 캔버스를 origin 별 localStorage draft(`Comfy.Workflow.Draft.v2:*`)로 복원하는데,
// Pod 의 대시보드 origin 은 노드 이동·컨테이너 재생성에도 그대로라 **옛 세트의 그래프가
// 어느 새 노드에서든 계속 되살아난다**. v1 은 이미 소진된 플래그라 양보만 했고, 유저는
// "missing model" 다이얼로그와 함께 옛 workflow 에 갇혔다 (2026-08-24 pod-cs1i 실사고 —
// SDXL→Z-Image 교체 후 노드까지 바뀌었는데 SDXL 그래프가 복원됨).
//
// v2 계약:
//   · 마지막으로 고려한 slug 를 기억한다 (`meshive.autoload.v2` = {"slug": ...}).
//   · 캔버스가 비어 있으면 → 현행 세트의 workflow 를 자동 로드 (v1 과 동일한 배려).
//   · 캔버스에 뭔가 있고 기억한 slug == 현행 slug → 손대지 않는다 (draft 가 주인).
//   · 캔버스에 뭔가 있고 slug 가 **다르면** → 덮지 않는다. 대신 비파괴 배너로 제안한다
//     ([Open] = 새 workflow 로드, [Keep] = 현행 캔버스 유지). 어느 쪽이든 기억을 갱신해
//     같은 질문을 반복하지 않는다. 유저 작업을 코드가 판별할 수 없으므로(복원된 옛 시드와
//     진짜 작업물을 그래프만 보고 구분 불가) 자동 교체는 하지 않는다.
//   · v1 플래그만 있고 v2 기억이 없는 기존 브라우저는 "미확인" 으로 본다 → 캔버스가 차
//     있으면 배너가 한 번 뜬다 (같은 세트여도 — Keep 한 번이면 끝). 이 한 번이 바로
//     위 사고의 유저를 구출하는 경로다.
//
// 프리셋 이미지에서도 이 확장은 안전하다: 프리셋 템플릿은 `config` semantic path 를
// 선언하지 않아 workflow-seed init 자체가 붙지 않는다 → `bundled-*` 마커만 존재 →
// 아래 필터가 전부 걸러 내고 no-op 으로 끝난다.
//
// 유지되는 계약:
//   · **마커는 있는데 파일이 없으면 열지 않는다** — 유저가 지운 것이므로 존중한다
//     (마커의 의미는 "이 slug 는 이 볼륨에서 이미 고려됐다" 이지 "파일이 있다" 가 아니다)
const LEGACY_FLAG = "meshive.autoload.v1";
const STATE_KEY = "meshive.autoload.v2";
const SEEDED_DIR = "workflows/.meshive/seeded";
const WORKFLOWS_DIR = "workflows";
const RESTORE_GRACE_MS = 150;
const BANNER_ID = "meshive-autoload-banner";

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

function readState() {
    try {
        const raw = localStorage.getItem(STATE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch {
        return null;
    }
}

function remember(slug) {
    localStorage.setItem(STATE_KEY, JSON.stringify({ slug }));
    // v1 도 세워 둔다 — 구 이미지로 롤백해도 그 코드가 다시 자동 로드로 덮지 않게.
    localStorage.setItem(LEGACY_FLAG, "1");
}

function showBanner(filename, onOpen) {
    if (document.getElementById(BANNER_ID)) return;
    const bar = document.createElement("div");
    bar.id = BANNER_ID;
    bar.style.cssText = [
        "position:fixed", "top:12px", "left:50%", "transform:translateX(-50%)",
        "z-index:10000", "display:flex", "align-items:center", "gap:12px",
        "padding:10px 16px", "border-radius:8px", "font-size:13px",
        "font-family:sans-serif", "color:#fff", "background:#1e293b",
        "border:1px solid #475569", "box-shadow:0 4px 16px rgba(0,0,0,.45)",
        "max-width:calc(100vw - 48px)",
    ].join(";");
    const label = document.createElement("span");
    const stem = filename.replace(/\.json$/, "");
    label.textContent =
        `Your asset set changed — starter workflow "${stem}" is ready.`;
    const openBtn = document.createElement("button");
    openBtn.textContent = "Open";
    openBtn.style.cssText =
        "padding:4px 14px;border-radius:6px;border:0;cursor:pointer;" +
        "background:#38bdf8;color:#0b1220;font-weight:600";
    const keepBtn = document.createElement("button");
    keepBtn.textContent = "Keep current";
    keepBtn.style.cssText =
        "padding:4px 12px;border-radius:6px;cursor:pointer;background:none;" +
        "border:1px solid #64748b;color:#cbd5e1";
    openBtn.onclick = async () => { bar.remove(); await onOpen(); };
    keepBtn.onclick = () => bar.remove();
    bar.append(label, openBtn, keepBtn);
    document.body.appendChild(bar);
}

app.registerExtension({
    name: "meshive.autoload",
    async setup() {
        // ComfyUI 의 복원(localStorage 의 이전 workflow)이 먼저 끝나게 둔다.
        await new Promise((r) => setTimeout(r, RESTORE_GRACE_MS));

        try {
            const markers = await listSeedMarkers();
            const slug = markers.find((n) => !n.startsWith("bundled-"));
            if (!slug) {
                // asset set 없이 띄운 base pod — 정상 경로다. 기억을 세우지 않아
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
                // 유저가 지운 경우가 대부분이다 (위 '삭제 존중' 참조). 기억은 갱신해
                // 지운 세트에 대해 배너로 되묻지 않는다.
                console.info("[meshive] seeded workflow is gone, not restoring:",
                             filename);
                remember(slug);
                return;
            }

            const empty = (app.graph?.nodes?.length ?? 0) <= 1;
            if (empty) {
                await app.loadGraphData(data);
                remember(slug);
                console.log("[meshive] auto-loaded seeded workflow:", filename);
                return;
            }

            const prev = readState();
            if (prev?.slug === slug) return;  // 같은 세트 — draft 가 주인이다.

            showBanner(filename, async () => {
                await app.loadGraphData(data);
                console.log("[meshive] opened seeded workflow via banner:",
                            filename);
            });
            // 응답과 무관하게 기억한다 — Keep(또는 무시 후 이탈)이 "다시 묻지 마" 다.
            // 배너가 떠 있는 동안 유저가 사이드바에서 직접 열어도 결과는 같다.
            remember(slug);
            console.log("[meshive] asset set changed, offering workflow:",
                        filename);
        } catch (e) {
            // 자동 로드는 편의 기능이다 — 어떤 실패도 대시보드를 막지 않는다.
            console.warn("[meshive] auto-load error:", e);
        }
    },
});
