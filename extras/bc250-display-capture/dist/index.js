const manifest = { name: "BC-250 Display Capture" };
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) throw new Error("Decky loader API was not initialized.");
let api;
try { api = internalAPIConnection.connect(API_VERSION, manifest.name); }
catch (_) { api = internalAPIConnection.connect(1, manifest.name); }
const callable = api.callable;
const toaster = api.toaster;
const definePlugin = (fn) => (...args) => fn(...args);
const h = SP_REACT.createElement;
const getStatus = callable("get_status");
const startCapture = callable("start_capture");
const stopCapture = callable("stop_capture");

function shortPath(value) {
    return String(value || "").replace(/^\/home\/[^/]+\//, "~/");
}
function errorText(error) {
    return error instanceof Error ? error.message : String(error);
}
function CapturePanel() {
    const [status, setStatus] = SP_REACT.useState({ running: false, directory: "", archive: "" });
    const [busy, setBusy] = SP_REACT.useState(false);
    const [error, setError] = SP_REACT.useState("");
    const refresh = async () => {
        try { setStatus(await getStatus()); setError(""); }
        catch (error) { setError(errorText(error)); }
    };
    SP_REACT.useEffect(() => {
        void refresh();
        const timer = window.setInterval(() => void refresh(), 3000);
        return () => window.clearInterval(timer);
    }, []);
    const start = async () => {
        setBusy(true);
        try {
            const next = await startCapture();
            setStatus(next);
            setError("");
            toaster.toast({ title: manifest.name, body: "Collection started and will survive the session switch." });
        } catch (error) { setError(errorText(error)); }
        finally { setBusy(false); }
    };
    const stop = async () => {
        setBusy(true);
        try {
            const next = await stopCapture();
            setStatus(next);
            setError("");
            toaster.toast({ title: manifest.name, body: `Archive ready: ${shortPath(next.archive)}` });
        } catch (error) { setError(errorText(error)); }
        finally { setBusy(false); }
    };
    const row = (children) => h(DFL.PanelSectionRow, null, children);
    return h(DFL.PanelSection, { title: "BC-250 Display Capture" },
        row(h("div", { style: { fontSize: "13px", color: "#aeb3b8", lineHeight: 1.35 } }, "Start before switching sessions. The system collector remains active while KDE closes and gamescope starts.")),
        row(h(DFL.ButtonItem, { disabled: busy || status.running, onClick: () => void start() }, busy ? "Starting..." : "Start collection")),
        row(h(DFL.ButtonItem, { disabled: busy || !status.running, onClick: () => void stop() }, busy ? "Packaging..." : "Stop and package")),
        row(h("div", { style: { fontSize: "12px", color: status.running ? "#8fce00" : "#aeb3b8" } }, `Status: ${status.running ? "running" : "stopped"}`)),
        status.directory && row(h("div", { style: { fontSize: "11px", color: "#888", wordBreak: "break-all" } }, `Folder: ${shortPath(status.directory)}`)),
        status.archive && !status.running && row(h("div", { style: { fontSize: "11px", color: "#8fb8ff", wordBreak: "break-all" } }, `Archive: ${shortPath(status.archive)}`)),
        error && row(h("div", { style: { fontSize: "12px", color: "#ff8080", whiteSpace: "pre-wrap" } }, error))
    );
}

var index = definePlugin(() => ({
    name: manifest.name,
    titleView: h("div", { className: DFL.staticClasses.Title }, manifest.name),
    content: h(CapturePanel, {}),
    icon: h("span", null, "D"),
    onDismount() {},
}));
index;
