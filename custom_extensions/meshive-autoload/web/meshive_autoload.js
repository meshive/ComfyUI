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
//   · **"열려 있던 작업이 있는가" 는 캔버스가 아니라 localStorage draft 로 판정한다.**
//     ComfyUI 의 draft 복원(`Comfy.Workflow.Draft.v2:*`)은 setup 보다 늦게 끝날 수 있어
//     캔버스를 보면 레이스다 — 복원 전의 빈 캔버스를 "새 브라우저"로 오판해 자동 로드가
//     유저 draft 를 밀어낸다 (dev E2E 에서 실측: 150ms 그레이스로는 복원이 안 끝났다).
//     draft 키 존재는 동기적으로 읽히므로 타이밍이 없다.
//   · draft 가 없으면(진짜 새 브라우저) → 현행 세트의 workflow 를 자동 로드.
//   · draft 가 있고 기억한 slug == 현행 slug → 손대지 않는다 (draft 가 주인).
//   · draft 가 있고 slug 가 **다르면**(v2 미기록 포함) → **복원이 자리잡길 기다린 뒤**
//     새 workflow 를 자동으로 전면에 연다. 순서가 안전장치다: 복원이 끝난 다음의
//     `loadGraphData` 는 **새 탭을 추가**할 뿐 기존 draft 를 건드리지 않는다 (복원 전에
//     부르면 draft 저장기가 활성 워크플로를 같은 draft 슬롯에 덮어써 유저 작업이 사라진다
//     — 위 레이스 실측과 동일 기전). 옛 draft 는 탭 스트립에 그대로 남아 한 클릭 거리다.
//     slug 를 기억하므로 전환은 세트 교체당 **한 번** — 이후 리로드는 유저의 탭 선택이
//     주인이다. (배너로 물어보는 안도 검토했으나, 복원 완료 후의 load 는 비파괴임이
//     보장되므로 물을 이유가 없다 — 2026-08-24 유저 결정.)
//   · v1 플래그만 있고 v2 기억이 없는 기존 브라우저도 같은 경로다 — 옛 세트 draft 에
//     갇힌 사고 브라우저가 다음 방문에서 자동 구출된다. 같은 세트를 계속 쓰던
//     브라우저는 한 번 시드 탭이 전면에 오는 비용을 치른다 (작업 draft 는 탭에 보존).
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
// draft 복원 완료 대기의 상한 — 복원은 보통 1초 안에 끝난다. 상한에 걸리는 경우는
// draft 키는 있는데 복원이 실패한 형태(깨진 인덱스 등)뿐이고, 그때 캔버스는 비어
// 있으므로 시드를 열어도 잃을 것이 없다.
const RESTORE_SETTLE_TIMEOUT_MS = 5000;
const RESTORE_SETTLE_POLL_MS = 100;

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

function hasOpenDrafts() {
    // ComfyUI 가 복원할 미저장 작업이 이 origin 에 있는가 — **동기 판정** (복원 완료를
    // 기다리는 타이밍 게임 금지, 위 v2 계약 참조). 신/구 프론트엔드 키 모두 커버한다.
    for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.startsWith("Comfy.Workflow.Draft.v2:")) return true;
    }
    return !!localStorage.getItem("workflow");  // 구 프론트엔드의 미저장 캔버스 키
}

function remember(slug) {
    localStorage.setItem(STATE_KEY, JSON.stringify({ slug }));
    // v1 도 세워 둔다 — 구 이미지로 롤백해도 그 코드가 다시 자동 로드로 덮지 않게.
    localStorage.setItem(LEGACY_FLAG, "1");
}

async function waitForRestoreToSettle() {
    // draft 가 있음을 안 뒤에만 부른다 — "캔버스에 뭔가 나타날 때까지"가 곧
    // "복원이 자리잡았다"다. 상한 초과는 복원 실패(빈 캔버스)이므로 그대로 진행한다.
    const deadline = performance.now() + RESTORE_SETTLE_TIMEOUT_MS;
    while (performance.now() < deadline) {
        if ((app.graph?.nodes?.length ?? 0) > 0) return true;
        await new Promise((r) => setTimeout(r, RESTORE_SETTLE_POLL_MS));
    }
    return false;
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

            if (!hasOpenDrafts()) {
                // 복원할 draft 가 없는 진짜 새 브라우저 — 바로 열어 준다.
                await app.loadGraphData(data);
                remember(slug);
                console.log("[meshive] auto-loaded seeded workflow:", filename);
                return;
            }

            const prev = readState();
            if (prev?.slug === slug) return;  // 같은 세트 — draft 가 주인이다.

            // 세트가 바뀌었다(또는 v2 미기록) — 복원이 자리잡은 **뒤에**, **새 임시
            // 워크플로 탭을 만들어** 그 안에 연다. 두 단계가 모두 보존의 조건이다:
            //   · 복원 전에 load 하면 draft 저장기가 활성 워크플로를 기존 draft 슬롯에
            //     덮어써 유저 작업이 사라진다 (dev E2E 실측 — nodes>0 직후의 load 도
            //     탭 등록 전이라 같은 슬롯을 덮었다).
            //   · createNewTemporary 없이 load 해도 같은 이유로 활성 탭이 제물이 된다.
            // 순서를 지키면 기존 draft 는 탭 스트립에 그대로 남는다 (E2E: drafts 1→2,
            // 옛 내용 보존 실측). 기억을 먼저 갱신해 load 도중 리로드돼도 반복하지 않는다.
            remember(slug);
            await waitForRestoreToSettle();
            try {
                await app.extensionManager?.workflow?.createNewTemporary?.();
            } catch (e) {
                // 구 프론트엔드(스토어 API 부재) — 활성 탭에 그대로 연다. draft 가
                // 없던 시절의 동작과 같아 순 회귀는 아니다.
                console.warn("[meshive] createNewTemporary unavailable:", e);
            }
            await app.loadGraphData(data);
            console.log("[meshive] asset set changed, opened seeded workflow:",
                        filename);
        } catch (e) {
            // 자동 로드는 편의 기능이다 — 어떤 실패도 대시보드를 막지 않는다.
            console.warn("[meshive] auto-load error:", e);
        }
    },
});
