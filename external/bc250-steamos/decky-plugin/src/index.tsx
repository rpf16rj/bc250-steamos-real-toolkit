import {
  ButtonItem,
  ConfirmModal,
  Focusable,
  Navigation,
  PanelSection,
  PanelSectionRow,
  showModal,
  Spinner,
  staticClasses,
} from "@decky/ui";
import { definePlugin, routerHook, toaster } from "@decky/api";
import { useEffect, useRef, useState } from "react";
import {
  FaChartLine,
  FaCog,
  FaMemory,
  FaMicrochip,
  FaSyncAlt,
  FaTv,
} from "react-icons/fa";
import { getSnapshot, getTelemetry } from "./api";
import { EmptyState, StatusRow } from "./components/Common";
import { ScrollViewport } from "./components/ScrollViewport";
import { VerticalTabs, type VerticalTab } from "./components/VerticalTabs";
import { CecTab } from "./tabs/CecTab";
import { CpuTab } from "./tabs/CpuTab";
import { CuTab } from "./tabs/CuTab";
import { GpuTab } from "./tabs/GpuTab";
import {
  OverviewTab,
  OverviewSummary,
  type HistorySample,
} from "./tabs/OverviewTab";
import type {
  Confirmation,
  MutationOptions,
  MutationRunner,
} from "./tabs/shared";
import type { Snapshot } from "./types";

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  return "The backend action failed.";
}

const ROUTE_PATH = "/bc250-control";

function useTelemetryHistory(): HistorySample[] {
  const [history, setHistory] = useState<HistorySample[]>([]);
  const telemetryRunning = useRef(false);

  useEffect(() => {
    let active = true;
    const poll = async () => {
      if (telemetryRunning.current) return;
      telemetryRunning.current = true;
      try {
        const sample = await getTelemetry();
        if (active) setHistory((current) => [...current, sample].slice(-36));
      } catch {
        // Full status refreshes report backend errors; chart gaps stay quiet.
      } finally {
        telemetryRunning.current = false;
      }
    };
    void poll();
    const timer = window.setInterval(() => void poll(), 1_000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, []);

  return history;
}

function FullControl() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [activeTab, setActiveTab] = useState("overview");
  const history = useTelemetryHistory();
  const [loading, setLoading] = useState(true);
  const [busyLabel, setBusyLabel] = useState("");
  const [error, setError] = useState("");
  const requestVersion = useRef(0);
  const mutationRunning = useRef(false);
  const refreshRunning = useRef(false);

  const refresh = async (quiet = false) => {
    if (refreshRunning.current || (quiet && mutationRunning.current)) return;
    refreshRunning.current = true;
    const request = ++requestVersion.current;
    if (!quiet) setLoading(true);
    try {
      const next = await getSnapshot();
      if (request === requestVersion.current) {
        setSnapshot(next);
        setError("");
      }
    } catch (caught) {
      if (request === requestVersion.current) setError(errorMessage(caught));
    } finally {
      refreshRunning.current = false;
      if (!quiet) setLoading(false);
    }
  };

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(true), 10_000);
    return () => window.clearInterval(timer);
  }, []);

  const execute = async (
    label: string,
    operation: () => Promise<void>,
    options: MutationOptions = {},
  ) => {
    if (mutationRunning.current) return;
    mutationRunning.current = true;
    const request = ++requestVersion.current;
    setBusyLabel(label);
    try {
      await operation();
      if (options.refresh !== false) {
        try {
          const next = await getSnapshot();
          if (request === requestVersion.current) {
            setSnapshot(next);
            setError("");
          }
        } catch (caught) {
          if (request === requestVersion.current) {
            setError(`Action completed, but status refresh failed: ${errorMessage(caught)}`);
          }
        }
      }
      if (options.successToast !== false) {
        toaster.toast({ title: "BC-250 Control", body: label });
      }
    } catch (caught) {
      const message = errorMessage(caught);
      if (request === requestVersion.current) setError(message);
      toaster.toast({ title: "BC-250 action failed", body: message });
    } finally {
      mutationRunning.current = false;
      setBusyLabel("");
    }
  };

  const runMutation: MutationRunner = (
    label,
    operation,
    confirmation?: Confirmation,
    options?: MutationOptions,
  ) => {
    if (!confirmation) {
      void execute(label, operation, options);
      return;
    }
    showModal(
      <ConfirmModal
        strTitle={confirmation.title}
        strDescription={confirmation.description}
        strOKButtonText="Apply"
        strCancelButtonText="Cancel"
        bDestructiveWarning={confirmation.destructive}
        onOK={() => void execute(label, operation, options)}
      />,
    );
  };

  if (loading && !snapshot) {
    return (
      <div style={{ display: "flex", justifyContent: "center", padding: 28 }}>
        <Spinner />
      </div>
    );
  }

  if (!snapshot) {
    return (
      <PanelSection title="Backend unavailable">
        <EmptyState>{error || "Unable to load toolkit status."}</EmptyState>
        <PanelSectionRow>
          <ButtonItem layout="below" onClick={() => void refresh()}>
            Retry
          </ButtonItem>
        </PanelSectionRow>
      </PanelSection>
    );
  }

  const busy = Boolean(busyLabel);
  const tabProps = { snapshot, busy, runMutation };
  const serviceActive = (active: string) => active === "active";
  const tabs: VerticalTab[] = [
    {
      id: "overview",
      label: "Overview",
      icon: <FaChartLine />,
      healthy: [
        snapshot.cu.service,
        snapshot.power.governor,
        snapshot.power.acpiService,
        snapshot.power.cpufreqService,
        snapshot.power.frequencyRestore,
        snapshot.cpu.service,
      ].every((service) => serviceActive(service.active)) &&
        snapshot.toolkit.privileged &&
        snapshot.cu.available &&
        snapshot.gpu.dbusReady,
      content: <OverviewTab snapshot={snapshot} history={history} />,
    },
    {
      id: "cu",
      label: "CU",
      icon: <FaMicrochip />,
      healthy: snapshot.toolkit.privileged && snapshot.cu.controllable,
      content: <CuTab {...tabProps} />,
    },
    {
      id: "gpu",
      label: "GPU",
      icon: <FaMemory />,
      healthy: snapshot.toolkit.privileged && snapshot.gpu.controllable,
      content: <GpuTab {...tabProps} />,
    },
    {
      id: "cpu",
      label: "CPU OC",
      icon: <FaCog />,
      healthy:
        snapshot.toolkit.privileged &&
        snapshot.toolkit.cpuControlAvailable &&
        serviceActive(snapshot.cpu.service.active),
      content: <CpuTab {...tabProps} />,
    },
    {
      id: "cec",
      label: "CEC",
      icon: <FaTv />,
      healthy: serviceActive(snapshot.cec.service.active),
      content: <CecTab {...tabProps} />,
    },
  ];

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        minHeight: 0,
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
        background: "linear-gradient(135deg, #18222d 0%, #10161d 55%, #151b20 100%)",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 8,
          padding: "14px 22px",
          borderBottom: "1px solid rgba(255,255,255,.08)",
        }}
      >
        <div style={{ minWidth: 0 }}>
          <div style={{ color: "#fff", fontSize: 20, fontWeight: 700 }}>
            BC-250 Control
          </div>
          <div style={{ fontSize: 12, color: "#aeb3b8", marginTop: 2 }}>
            {busyLabel || `${snapshot.cu.available ? `${snapshot.cu.total}/${snapshot.cu.maximum} CU` : "CU unavailable"} · ${snapshot.gpu.activeMhz ?? "–"} MHz GPU`}
          </div>
          {!snapshot.toolkit.available && (
            <div
              style={{
                color: "#e6ad55",
                fontSize: 11,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              Toolkit incomplete: {snapshot.toolkit.path}
            </div>
          )}
          {!snapshot.toolkit.privileged && (
            <div style={{ color: "#e77878", fontSize: 11 }}>
              Backend is not running as root; reinstall the plugin.
            </div>
          )}
          {error && <div style={{ color: "#e77878", fontSize: 11 }}>{error}</div>}
        </div>
        <ButtonItem
          layout="below"
          disabled={Boolean(busyLabel)}
          onClick={() => void refresh()}
        >
          <FaSyncAlt />
        </ButtonItem>
      </div>
      <div style={{ flex: 1, minHeight: 0 }}>
        <VerticalTabs tabs={tabs} active={activeTab} onChange={setActiveTab} />
      </div>
    </div>
  );
}

function QuickPanel() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [activeTab, setActiveTab] = useState("summary");
  const history = useTelemetryHistory();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [busyLabel, setBusyLabel] = useState("");
  const requestVersion = useRef(0);
  const refreshRunning = useRef(false);
  const mutationRunning = useRef(false);

  const refresh = async (quiet = false) => {
    if (refreshRunning.current || (quiet && mutationRunning.current)) return;
    refreshRunning.current = true;
    const request = ++requestVersion.current;
    if (!quiet) setLoading(true);
    try {
      const next = await getSnapshot();
      if (request === requestVersion.current) {
        setSnapshot(next);
        setError("");
      }
    } catch (caught) {
      if (request === requestVersion.current) setError(errorMessage(caught));
    } finally {
      refreshRunning.current = false;
      if (!quiet) setLoading(false);
    }
  };

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(true), 10_000);
    return () => window.clearInterval(timer);
  }, []);

  const execute = async (
    label: string,
    operation: () => Promise<void>,
    options: MutationOptions = {},
  ) => {
    if (mutationRunning.current) return;
    mutationRunning.current = true;
    const request = ++requestVersion.current;
    setBusyLabel(label);
    try {
      await operation();
      if (options.refresh !== false) {
        try {
          const next = await getSnapshot();
          if (request === requestVersion.current) {
            setSnapshot(next);
            setError("");
          }
        } catch (caught) {
          if (request === requestVersion.current) {
            setError(`Action completed, but status refresh failed: ${errorMessage(caught)}`);
          }
        }
      }
      if (options.successToast !== false) {
        toaster.toast({ title: "BC-250 Control", body: label });
      }
    } catch (caught) {
      const message = errorMessage(caught);
      if (request === requestVersion.current) setError(message);
      toaster.toast({ title: "BC-250 action failed", body: message });
    } finally {
      mutationRunning.current = false;
      setBusyLabel("");
    }
  };

  const runMutation: MutationRunner = (
    label,
    operation,
    confirmation?: Confirmation,
    options?: MutationOptions,
  ) => {
    if (!confirmation) {
      void execute(label, operation, options);
      return;
    }
    showModal(
      <ConfirmModal
        strTitle={confirmation.title}
        strDescription={confirmation.description}
        strOKButtonText="Apply"
        strCancelButtonText="Cancel"
        bDestructiveWarning={confirmation.destructive}
        onOK={() => void execute(label, operation, options)}
      />,
    );
  };

  const openControls = () => {
    Navigation.Navigate(ROUTE_PATH);
    Navigation.CloseSideMenus();
  };

  if (loading && !snapshot) {
    return (
      <div style={{ display: "flex", justifyContent: "center", padding: 28 }}>
        <Spinner />
      </div>
    );
  }

  return (
    <div style={{ height: "100%", minHeight: 0, overflow: "hidden" }}>
      <ScrollViewport>
        <Focusable flow-children="down" style={{ paddingBottom: 64 }}>
          <Focusable
            flow-children="right"
            style={{ display: "flex", gap: 6, margin: "8px 8px 12px" }}
          >
            {[
              ["summary", "Summary"],
              ["cec", "CEC"],
            ].map(([id, label]) => (
              <Focusable
                key={id}
                tabIndex={0}
                role="button"
                aria-selected={activeTab === id}
                onFocus={() => setActiveTab(id)}
                onActivate={() => setActiveTab(id)}
                onClick={() => setActiveTab(id)}
                style={{
                  flex: 1,
                  padding: "9px 12px",
                  borderRadius: 6,
                  textAlign: "center",
                  color: activeTab === id ? "#fff" : "#aeb3b8",
                  background: activeTab === id
                    ? "rgba(64, 148, 255, 0.30)"
                    : "rgba(255,255,255,.05)",
                  fontSize: 13,
                  fontWeight: activeTab === id ? 700 : 500,
                }}
              >
                {label}
              </Focusable>
            ))}
          </Focusable>
          <PanelSection>
            <PanelSectionRow>
              <ButtonItem layout="below" onClick={openControls}>
                Open full controls
              </ButtonItem>
            </PanelSectionRow>
          </PanelSection>
          {snapshot ? (
            activeTab === "cec" ? (
              <CecTab
                snapshot={snapshot}
                busy={Boolean(busyLabel)}
                runMutation={runMutation}
                compact
              />
            ) : (
              <OverviewSummary snapshot={snapshot} history={history} compact />
            )
          ) : (
            <EmptyState>{error || "Unable to load toolkit status."}</EmptyState>
          )}
          {busyLabel && <StatusRow label="Working" value={busyLabel} />}
          {error && snapshot && <EmptyState>{error}</EmptyState>}
          <PanelSection>
            <PanelSectionRow>
              <ButtonItem
                layout="below"
                disabled={loading || Boolean(busyLabel)}
                onClick={() => void refresh()}
              >
                <FaSyncAlt /> Refresh status
              </ButtonItem>
            </PanelSectionRow>
          </PanelSection>
        </Focusable>
      </ScrollViewport>
    </div>
  );
}

export default definePlugin(() => {
  routerHook.addRoute(ROUTE_PATH, FullControl);

  return {
    name: "BC-250 Control",
    titleView: <div className={staticClasses.Title}>BC-250 Control</div>,
    content: <QuickPanel />,
    icon: <FaMicrochip />,
    onDismount() {
      routerHook.removeRoute(ROUTE_PATH);
    },
  };
});
