import { Button, PanelSection, TextField, ToggleField } from "@decky/ui";
import { useEffect, useState } from "react";
import { cecAction, setCecName, setCecToggle } from "../api";
import { ActionButton, EmptyState, StatusRow } from "../components/Common";
import type { TabProps } from "./shared";

export function CecTab({
  snapshot,
  busy,
  runMutation,
  compact = false,
}: TabProps & { compact?: boolean }) {
  const { cec } = snapshot;
  const controlsDisabled = busy || !snapshot.toolkit.cecAvailable;
  const [cecName, setName] = useState(cec.osdName ?? "");
  const [nameDirty, setNameDirty] = useState(false);
  const submittedName = cecName.trim();
  const nameBytes = new TextEncoder().encode(submittedName).length;
  const nameValid = nameBytes > 0 && nameBytes <= 14 &&
    !/["\\]/.test(submittedName) &&
    !Array.from(submittedName).some((character) => !character.trim() && character !== " ");
  const nameChanged = submittedName !== (cec.osdName ?? "");

  useEffect(() => {
    if (!nameDirty) setName(cec.osdName ?? "");
  }, [cec.osdName, nameDirty]);

  if (!cec.devicePresent) {
    return <EmptyState>Connect a CEC-tunneling DP-to-HDMI adapter to expose `/dev/cec0`.</EmptyState>;
  }

  const action = (name: string, label: string, confirmation?: string) =>
    runMutation(
      label,
      () => cecAction(name),
      confirmation
        ? { title: `${label}?`, description: confirmation }
        : undefined,
      {
        refresh: !["vol-up", "vol-down", "mute"].includes(name),
        successToast: false,
      },
    );

  const toggle = (key: string, enabled: boolean, label: string) =>
    runMutation(
      `${label} ${enabled ? "enabled" : "disabled"}`,
      () => setCecToggle(key, enabled),
      undefined,
      { successToast: false },
    );

  const saveName = () => {
    if (controlsDisabled || !nameValid || !nameChanged) return;
    setName(submittedName);
    setNameDirty(false);
    runMutation(
      `CEC name changed to ${submittedName}`,
      () => setCecName(submittedName),
    );
  };

  return (
    <>
      <PanelSection title={compact ? "CEC quick controls" : "CEC Status"}>
        <StatusRow
          label="Daemon"
          value={cec.service.active}
          good={cec.service.active === "active"}
        />
        {!compact && (
          <TextField
            label="CEC broadcast name"
            description={nameBytes > 14 ? `${nameBytes}/14 bytes` : "Shown in the TV's device list (14 bytes max)"}
            value={cecName}
            disabled={controlsDisabled || cec.osdName === null}
            onChange={(event) => {
              setName(event.target.value);
              setNameDirty(true);
            }}
            onKeyDown={(event) => {
              if (event.key === "Enter") saveName();
            }}
            inlineControls={
              <Button
                disabled={controlsDisabled || !nameValid || !nameChanged}
                onClick={saveName}
              >
                Save
              </Button>
            }
          />
        )}
        <StatusRow
          label="Active source"
          value={cec.active === null ? "Unknown" : cec.active ? "This console" : "Another source"}
          good={cec.active === true}
        />
        {!compact && (
          <StatusRow
            label="Poweroff integration"
            value={cec.poweroffIntegration ? "Installed" : "Pending"}
            good={cec.poweroffIntegration}
          />
        )}
      </PanelSection>

      <PanelSection title={compact ? "TV and Input" : "TV and Receiver"}>
        <ActionButton label="Wake TV and select input" disabled={controlsDisabled} onClick={() => action("tv-on", "TV on")} />
        <ActionButton
          label="TV standby"
          disabled={controlsDisabled}
          onClick={() => action("tv-off", "TV standby", "The television will enter standby immediately.")}
        />
        {!compact && (
          <ActionButton label="Receiver on" disabled={controlsDisabled} onClick={() => action("amp-on", "Receiver on")} />
        )}
        {!compact && (
          <ActionButton
            label="Receiver standby"
            disabled={controlsDisabled}
            onClick={() => action("amp-off", "Receiver standby", "The receiver will enter standby immediately.")}
          />
        )}
        <ActionButton label="Claim active source" disabled={controlsDisabled} onClick={() => action("switch", "Input selected")} />
        {!compact && (
          <ActionButton label="Release active source" disabled={controlsDisabled} onClick={() => action("release", "Input released")} />
        )}
      </PanelSection>

      <PanelSection title="Volume">
        <ActionButton label="Volume up" disabled={controlsDisabled} onClick={() => action("vol-up", "Volume raised")} />
        <ActionButton label="Volume down" disabled={controlsDisabled} onClick={() => action("vol-down", "Volume lowered")} />
        <ActionButton label="Mute" disabled={controlsDisabled} onClick={() => action("mute", "Mute toggled")} />
      </PanelSection>

      {!compact && <PanelSection title="Behavior">
        <ToggleField
          label="Wake TV on resume"
          checked={cec.wakeTv === true}
          disabled={controlsDisabled || cec.wakeTv === null}
          onChange={(enabled) => toggle("wake-tv", enabled, "TV resume wake")}
        />
        <ToggleField
          label="TV standby on suspend"
          checked={cec.suspendTv === true}
          disabled={controlsDisabled || cec.suspendTv === null}
          onChange={(enabled) => toggle("suspend-tv", enabled, "TV suspend standby")}
        />
        <ToggleField
          label="Suspend when TV turns off"
          checked={cec.allowStandby === true}
          disabled={controlsDisabled || cec.allowStandby === null}
          onChange={(enabled) => toggle("allow-standby", enabled, "TV standby follow")}
        />
        <ToggleField
          label="TV remote input"
          checked={cec.uinput === true}
          disabled={controlsDisabled || cec.uinput === null}
          onChange={(enabled) => toggle("uinput", enabled, "TV remote input")}
        />
      </PanelSection>}
    </>
  );
}
