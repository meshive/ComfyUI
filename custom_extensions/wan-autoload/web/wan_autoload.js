import { app } from "../../scripts/app.js";

// Loads the bundled Wan 2.2 14B I2V workflow once per browser, only if the user
// hasn't already loaded a non-trivial graph. ComfyUI's own per-tab persistence
// takes over on subsequent visits, so user edits aren't clobbered.
const FLAG = "wan.autoloaded.v1";
const WORKFLOW_URL = new URL("./wan_2_2_14B_i2v.json", import.meta.url);

app.registerExtension({
    name: "wan.autoload",
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
                console.warn("[wan] workflow fetch failed:", res.status);
                return;
            }
            const data = await res.json();
            await app.loadGraphData(data);
            localStorage.setItem(FLAG, "1");
            console.log("[wan] auto-loaded Wan 2.2 I2V workflow");
        } catch (e) {
            console.warn("[wan] auto-load error:", e);
        }
    },
});
