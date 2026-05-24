import { app } from "../../scripts/app.js";

// Loads the bundled Flux 2 Dev (fp8) workflow once per browser, only if the
// user hasn't already loaded a non-trivial graph. ComfyUI's own per-tab
// persistence takes over on subsequent visits, so user edits aren't clobbered.
const FLAG = "flux.autoloaded.v2";
const WORKFLOW_URL = new URL("./flux2_dev_fp8.json", import.meta.url);

app.registerExtension({
    name: "flux.autoload",
    async setup() {
        if (localStorage.getItem(FLAG)) return;

        // Give ComfyUI a tick to finish any restore-from-storage step first.
        await new Promise((r) => setTimeout(r, 150));

        const nodeCount = app.graph?.nodes?.length ?? 0;
        if (nodeCount > 1) {
            // User already has a real workflow open — don't trample it.
            localStorage.setItem(FLAG, "1");
            return;
        }

        try {
            const res = await fetch(WORKFLOW_URL);
            if (!res.ok) {
                console.warn("[flux] workflow fetch failed:", res.status);
                return;
            }
            const data = await res.json();
            await app.loadGraphData(data);
            localStorage.setItem(FLAG, "1");
            console.log("[flux] auto-loaded Flux 2 Dev (fp8) workflow");
        } catch (e) {
            console.warn("[flux] auto-load error:", e);
        }
    },
});
