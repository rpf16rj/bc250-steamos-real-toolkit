import { Focusable, PanelSection, ToggleField } from "@decky/ui";
import { useState } from "react";
import { setCuWgp } from "../api";
import { EmptyState, StatusRow } from "../components/Common";
import type { CuRow } from "../types";
import type { TabProps } from "./shared";

function savedRows(masks: number[], liveRows: CuRow[]): CuRow[] {
  return masks.slice(0, 4).map((value, index) => {
    const mask = value & 0x1f;
    const factory = liveRows.find(
      (row) => row.se === Math.floor(index / 2) && row.sh === index % 2,
    );
    return {
      se: Math.floor(index / 2),
      sh: index % 2,
      spi: mask,
      cc: null,
      wgps: Array.from({ length: 5 }, (_, wgp) => Boolean(mask & (1 << wgp))),
      cus: mask.toString(2).replace(/0/g, "").length * 2,
      factoryCuMask: factory?.factoryCuMask ?? null,
      factoryWgps: factory?.factoryWgps ?? Array(5).fill(false),
    };
  });
}

function CuGrid({
  rows,
  editable,
  busy,
  onToggle,
}: {
  rows: CuRow[];
  editable: boolean;
  busy: boolean;
  onToggle: (row: CuRow, wgp: number, enabled: boolean) => void;
}) {
  return (
    <div style={{ padding: "4px 12px 10px" }}>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "68px repeat(5, minmax(54px, 1fr)) 42px",
          gap: 5,
          marginBottom: 6,
          color: "#87919a",
          fontSize: 10,
          textAlign: "center",
        }}
      >
        <span />
        {Array.from({ length: 5 }, (_, wgp) => (
          <span key={wgp}>CU{wgp * 2}-{wgp * 2 + 1}</span>
        ))}
        <span>Total</span>
      </div>
      {rows.map((row) => (
        <div
          key={`${row.se}-${row.sh}`}
          style={{
            display: "grid",
            gridTemplateColumns: "68px repeat(5, minmax(54px, 1fr)) 42px",
            gap: 5,
            alignItems: "center",
            marginBottom: 6,
            fontSize: 11,
          }}
        >
          <span style={{ color: "#aeb3b8" }}>SE{row.se}.SH{row.sh}</span>
          {row.wgps.map((enabled, wgp) => {
            const factory = row.factoryWgps[wgp] === true;
            const style = {
              minHeight: 30,
              boxSizing: "border-box" as const,
              padding: "7px 2px",
              border: editable && !factory
                ? "1px solid rgba(255,255,255,.14)"
                : factory
                  ? "1px solid rgba(96,165,250,.42)"
                  : "1px solid transparent",
              borderRadius: 5,
              textAlign: "center" as const,
              background: factory
                ? enabled
                  ? "rgba(64,148,255,.30)"
                  : "rgba(230,173,85,.22)"
                : enabled
                  ? "rgba(89,209,133,.28)"
                  : "rgba(255,255,255,.06)",
              color: factory
                ? enabled ? "#91c5ff" : "#e6c48f"
                : enabled ? "#82e8a7" : "#777f86",
              fontWeight: 700,
            };
            const label = factory ? enabled ? "OEM" : "OEM!" : enabled ? "ON" : "OFF";
            return editable && !factory ? (
              <Focusable
                key={wgp}
                role="button"
                tabIndex={0}
                aria-label={`SE${row.se} SH${row.sh} CU${wgp * 2}-${wgp * 2 + 1} ${label}`}
                onActivate={() => onToggle(row, wgp, !enabled)}
                onClick={() => onToggle(row, wgp, !enabled)}
                style={{ ...style, opacity: busy ? 0.55 : 1 }}
              >
                {label}
              </Focusable>
            ) : <span key={wgp} style={style}>{label}</span>;
          })}
          <span style={{ textAlign: "right", color: "#f2f2f2" }}>{row.cus}/10</span>
        </div>
      ))}
      <div
        style={{
          display: "flex",
          gap: 14,
          padding: "2px 68px 0",
          color: "#87919a",
          fontSize: 10,
        }}
      >
        <span style={{ color: "#91c5ff" }}>OEM factory, locked</span>
        <span style={{ color: "#82e8a7" }}>Unlocked and routed</span>
      </div>
    </div>
  );
}

export function CuTab({ snapshot, busy, runMutation }: TabProps) {
  const { cu } = snapshot;
  const bootEnabled = cu.service.enabled === "enabled";
  const [advanced, setAdvanced] = useState(false);
  const hasSavedTable = cu.savedMasks.length === 4;
  const rows = cu.available
    ? cu.rows
    : hasSavedTable ? savedRows(cu.savedMasks, cu.rows) : [];

  const toggleWgp = (row: CuRow, wgp: number, enabled: boolean) => {
    if (busy || !cu.controllable) return;
    const pair = `CU${wgp * 2}-${wgp * 2 + 1}`;
    runMutation(
      `${enabled ? "Enabled" : "Disabled"} SE${row.se}.SH${row.sh} ${pair}`,
      () => setCuWgp(row.se, row.sh, wgp, enabled),
      {
        title: `${enabled ? "Enable" : "Disable"} ${pair}?`,
        description: "This writes live GPU routing registers. Factory-disabled WGPs may be defective and can cause corruption, a GPU hang, or a forced reboot. Save your work and monitor temperatures before continuing.",
        destructive: true,
      },
    );
  };

  return (
    <>
      <PanelSection title="Compute Units">
        <StatusRow
          label="Live routing"
          value={cu.available ? `${cu.total}/${cu.maximum} CU` : "Unavailable"}
          good={cu.available}
        />
        <StatusRow
          label="Boot replay"
          value={bootEnabled ? "Enabled" : "Disabled"}
          good={bootEnabled}
        />
        <StatusRow
          label="Factory lock"
          value={cu.factoryMapAvailable ? `${cu.factoryTotal}/40 CU locked` : "Map unavailable"}
          good={cu.factoryMapAvailable}
        />
        <StatusRow
          label="Update protection"
          value={cu.protected ? "Protected" : "Pending"}
          good={cu.protected}
        />
      </PanelSection>

      {rows.length === 4 ? (
        <PanelSection title={cu.available ? "Active CU Routing" : "Saved CU Routing"}>
          <CuGrid
            rows={rows}
            editable={advanced && cu.controllable}
            busy={busy}
            onToggle={toggleWgp}
          />
          {!cu.available && (
            <EmptyState>
              Live registers are unavailable. This colored grid shows the saved boot table instead.
            </EmptyState>
          )}
        </PanelSection>
      ) : (
        <EmptyState>{cu.liveReason || "Live CU routing is unavailable."}</EmptyState>
      )}

      <PanelSection title="Advanced">
        <ToggleField
          label="Enable live WGP editing"
          description="Each switch controls one two-CU WGP pair and writes the routing registers immediately."
          checked={advanced && cu.controllable}
          disabled={busy || !cu.controllable}
          onChange={setAdvanced}
        />
        {!cu.controllable && (
          <EmptyState>
            Live editing requires readable GPU registers, the verified factory 24-CU map, and a root-owned CU manager installation.
          </EmptyState>
        )}
        <EmptyState>
          Warning: factory-disabled WGPs may have failed validation. Test changes for correctness and stability before saving them for boot.
        </EmptyState>
      </PanelSection>

      <PanelSection title="Boot Behavior">
        <StatusRow
          label="Saved table"
          value={hasSavedTable ? "Available" : "Unavailable"}
          good={hasSavedTable}
        />
        <EmptyState>
          Save live routing and change boot replay from the toolkit CLI, where the full harvest-map checks are available.
        </EmptyState>
      </PanelSection>
    </>
  );
}
