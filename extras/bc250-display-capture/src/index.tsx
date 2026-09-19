import { callable, definePlugin, toaster } from "@decky/api";
import {
  ButtonItem,
  PanelSection,
  PanelSectionRow,
  staticClasses,
} from "@decky/ui";
import { useEffect, useState } from "react";

interface CaptureStatus {
  running: boolean;
  directory: string;
  archive: string;
}

const getStatus = callable<[], CaptureStatus>("get_status");
const startCapture = callable<[], CaptureStatus>("start_capture");
const stopCapture = callable<[], CaptureStatus>("stop_capture");

function shortPath(value: string): string {
  return value.replace(/^\/home\/[^/]+\//, "~/");
}

function CapturePanel() {
  const [status, setStatus] = useState<CaptureStatus>({
    running: false,
    directory: "",
    archive: "",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const refresh = async () => {
    try {
      setStatus(await getStatus());
      setError("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Unable to read capture status.");
    }
  };

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), 3000);
    return () => window.clearInterval(timer);
  }, []);

  const start = async () => {
    setBusy(true);
    try {
      const next = await startCapture();
      setStatus(next);
      toaster.toast({ title: "BC-250 Display Capture", body: "Collection started. It survives the KDE/Game Mode switch." });
      setError("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Unable to start collection.");
    } finally {
      setBusy(false);
    }
  };

  const stop = async () => {
    setBusy(true);
    try {
      const next = await stopCapture();
      setStatus(next);
      toaster.toast({ title: "BC-250 Display Capture", body: `Archive ready: ${shortPath(next.archive)}` });
      setError("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Unable to stop collection.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <PanelSection title="BC-250 Display Capture">
      <PanelSectionRow>
        <div style={{ fontSize: "13px", color: "#aeb3b8", lineHeight: 1.35 }}>
          Start before switching sessions. The collector keeps running while KDE closes and gamescope starts.
        </div>
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem disabled={busy || status.running} onClick={() => void start()}>
          {busy ? "Starting..." : "Start collection"}
        </ButtonItem>
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem disabled={busy || !status.running} onClick={() => void stop()}>
          {busy ? "Packaging..." : "Stop and package"}
        </ButtonItem>
      </PanelSectionRow>
      <PanelSectionRow>
        <div style={{ fontSize: "12px", color: status.running ? "#8fce00" : "#aeb3b8" }}>
          Status: {status.running ? "running" : "stopped"}
        </div>
      </PanelSectionRow>
      {status.directory && (
        <PanelSectionRow>
          <div style={{ fontSize: "11px", color: "#888", wordBreak: "break-all" }}>
            Folder: {shortPath(status.directory)}
          </div>
        </PanelSectionRow>
      )}
      {status.archive && !status.running && (
        <PanelSectionRow>
          <div style={{ fontSize: "11px", color: "#8fb8ff", wordBreak: "break-all" }}>
            Archive: {shortPath(status.archive)}
          </div>
        </PanelSectionRow>
      )}
      {error && (
        <PanelSectionRow>
          <div style={{ fontSize: "12px", color: "#ff8080", whiteSpace: "pre-wrap" }}>{error}</div>
        </PanelSectionRow>
      )}
    </PanelSection>
  );
}

export default definePlugin(() => ({
  name: "BC-250 Display Capture",
  titleView: <div className={staticClasses.Title}>BC-250 Display Capture</div>,
  content: <CapturePanel />,
}));
