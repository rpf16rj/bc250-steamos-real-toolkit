import { DropdownItem, PanelSection, SliderField } from "@decky/ui";
import { useEffect, useState } from "react";
import {
  setCustomLoadTarget,
  setGpuFrequency,
  setLoadTarget,
  setRamp,
} from "../api";
import { ActionButton, EmptyState, StatusRow } from "../components/Common";
import type { GpuMode } from "../types";
import type { TabProps } from "./shared";

const modeOptions = [
  { data: "adaptive", label: "Adaptive" },
  { data: "range", label: "Custom range / overclock" },
  { data: "pin", label: "Pinned frequency" },
  { data: "max", label: "Maximum curve point" },
];

export function GpuTab({ snapshot, busy, runMutation }: TabProps) {
  const { gpu } = snapshot;
  const initialMax = gpu.maximum || gpu.configuredMax || 1500;
  const [mode, setMode] = useState<GpuMode>(gpu.mode);
  const [minimum, setMinimum] = useState(gpu.minimum || 0);
  const [maximum, setMaximum] = useState(initialMax);
  const [rampMs, setRampMs] = useState(gpu.climbMs || 500);
  const [loadMinimum, setLoadMinimum] = useState(
    Math.round((gpu.loadLower ?? 0.65) * 100),
  );
  const [loadMaximum, setLoadMaximum] = useState(
    Math.round((gpu.loadUpper ?? 0.80) * 100),
  );
  const frequencyDisabled = busy || !gpu.controllable;
  const frequencyMaximum = Math.min(gpu.allowedMaximum || 2150, 2150);
  const frequencyMinimum = Math.max(gpu.allowedMinimum || 100, 100);

  useEffect(() => {
    setMode(gpu.mode);
    setMinimum(gpu.minimum || 0);
    setMaximum(gpu.maximum || gpu.configuredMax || 1500);
    setRampMs(gpu.climbMs || 500);
    setLoadMinimum(Math.round((gpu.loadLower ?? 0.65) * 100));
    setLoadMaximum(Math.round((gpu.loadUpper ?? 0.80) * 100));
  }, [
    gpu.mode,
    gpu.minimum,
    gpu.maximum,
    gpu.configuredMax,
    gpu.climbMs,
    gpu.loadLower,
    gpu.loadUpper,
  ]);

  if (!gpu.available) {
    return <EmptyState>Install the GPU governor through `bc250-power.sh governor`.</EmptyState>;
  }

  const applyFrequency = () =>
    runMutation(
      "GPU frequency updated",
      () => setGpuFrequency(mode, minimum, maximum),
      mode === "pin" || mode === "max"
        ? {
            title: "Apply sustained GPU clocks?",
            description: "Pinned or maximum clocks increase heat and power. Thermal throttling remains active.",
          }
        : undefined,
    );

  return (
    <>
      <PanelSection title="Live GPU">
        <StatusRow
          label="Active clock"
          value={gpu.activeMhz ? `${gpu.activeMhz} MHz` : "Unavailable"}
        />
        <StatusRow label="Live mode" value={gpu.mode} good={gpu.dbusReady} />
        <StatusRow
          label="Saved replay"
          value={
            gpu.requestedMode === "range"
              ? `${gpu.requestedMinimum}-${gpu.requestedMaximum} MHz`
              : gpu.requestedMode === "pin"
                ? `${gpu.requestedMaximum} MHz pinned`
                : gpu.requestedMode
          }
        />
        <StatusRow
          label="Live range"
          value={
            gpu.liveMinimum !== null && gpu.liveMaximum !== null
              ? `${gpu.liveMinimum}-${gpu.liveMaximum} MHz`
              : "D-Bus unavailable"
          }
          good={gpu.dbusReady}
        />
        <StatusRow
          label="Boot replay"
          value={
            !gpu.persistent
              ? "Pending setup"
              : gpu.replayApplied
                ? "Applied"
                : "Enabled, not live"
          }
          good={gpu.persistent && gpu.replayApplied}
        />
        <StatusRow
          label="Adaptive ceiling"
          value={gpu.configuredMax ? `${gpu.configuredMax} MHz` : "Curve maximum"}
        />
      </PanelSection>

      <PanelSection title="Frequency">
        <DropdownItem
          label="Mode"
          rgOptions={modeOptions}
          selectedOption={mode}
          disabled={frequencyDisabled}
          onChange={(option) => setMode(option.data as GpuMode)}
        />
        {(mode === "adaptive" || mode === "range") && (
          <SliderField
            label="Minimum clock"
            value={minimum}
            min={0}
            max={frequencyMaximum}
            step={50}
            valueSuffix=" MHz"
            editableValue
            disabled={frequencyDisabled}
            onChange={(value) => {
              setMinimum(value);
              setMode("range");
            }}
          />
        )}
        {mode !== "max" && (
          <SliderField
            label={mode === "pin" ? "Pinned clock" : "Maximum clock"}
            value={maximum}
            min={frequencyMinimum}
            max={frequencyMaximum}
            step={50}
            valueSuffix=" MHz"
            editableValue
            disabled={frequencyDisabled}
            onChange={(value) => {
              setMaximum(value);
              if (mode === "adaptive") setMode("range");
            }}
          />
        )}
        {!gpu.controllable && (
          <EmptyState>
            {!snapshot.toolkit.privileged
              ? "GPU controls require the Decky backend to run as root."
              : "Start the GPU governor before changing live frequency mode."}
          </EmptyState>
        )}
        <ActionButton
          label="Apply frequency mode"
          disabled={frequencyDisabled}
          onClick={applyFrequency}
        />
      </PanelSection>

      <PanelSection title="Load Response">
        <StatusRow
          label="Current target"
          value={
            gpu.loadUpper !== null && gpu.loadLower !== null
              ? `${Math.round(gpu.loadUpper * 100)} / ${Math.round(gpu.loadLower * 100)}%`
              : "Unavailable"
          }
        />
        <ActionButton
          label="Eager preset"
          description="40/10%; ramps aggressively for light or frame-capped games."
          disabled={busy || !gpu.controllable}
          onClick={() =>
            runMutation("Eager load target applied", () => setLoadTarget("eager"))
          }
        />
        <ActionButton
          label="Balanced preset"
          description="80/65%; restores the toolkit defaults."
          disabled={busy || !gpu.controllable}
          onClick={() =>
            runMutation("Balanced load target applied", () => setLoadTarget("reset"))
          }
        />
        <SliderField
          label="Minimum load"
          description="Clock down when GPU load falls below this threshold."
          value={loadMinimum}
          min={1}
          max={99}
          step={1}
          valueSuffix="%"
          editableValue
          disabled={busy || !gpu.controllable}
          onChange={setLoadMinimum}
        />
        <SliderField
          label="Maximum load"
          description="Clock up when GPU load rises above this threshold."
          value={loadMaximum}
          min={1}
          max={99}
          step={1}
          valueSuffix="%"
          editableValue
          disabled={busy || !gpu.controllable}
          onChange={setLoadMaximum}
        />
        {loadMinimum >= loadMaximum && (
          <EmptyState>Minimum load must be lower than maximum load.</EmptyState>
        )}
        <ActionButton
          label="Apply custom load target"
          disabled={
            busy || !gpu.controllable || loadMinimum >= loadMaximum
          }
          onClick={() =>
            runMutation(
              "Custom load target applied",
              () => setCustomLoadTarget(loadMinimum, loadMaximum),
            )
          }
        />
      </PanelSection>

      <PanelSection title="Ramp">
        <SliderField
          label="Idle-to-max climb"
          value={rampMs}
          min={200}
          max={5000}
          step={100}
          valueSuffix=" ms"
          editableValue
          disabled={busy || !gpu.controllable}
          onChange={setRampMs}
        />
        <ActionButton
          label="Apply ramp time"
          disabled={busy}
          onClick={() =>
            runMutation("GPU ramp updated", () => setRamp(rampMs))
          }
        />
      </PanelSection>

      {gpu.safePoints.length > 0 && (
        <PanelSection title="Voltage Curve">
          {gpu.safePoints.map((point, index) => (
            <StatusRow
              key={`${point.frequency}-${index}`}
              label={point.frequency ? `${point.frequency} MHz` : `Point ${index + 1}`}
              value={point.voltage ? `${point.voltage} mV` : "Unavailable"}
            />
          ))}
        </PanelSection>
      )}
    </>
  );
}
