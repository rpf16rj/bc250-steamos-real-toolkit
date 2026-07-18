import { PanelSection } from "@decky/ui";
import { StatusRow } from "../components/Common";
import type { Snapshot } from "../types";

export function PowerTab({ snapshot }: { snapshot: Snapshot }) {
  const { power } = snapshot;
  const governorEnabled = power.governor.enabled === "enabled";

  return (
    <>
      <PanelSection title="Power Health">
        <StatusRow
          label="ACPI C/P-states"
          value={power.acpiActive ? "Active" : "Reboot or setup needed"}
          good={power.acpiActive}
        />
        <StatusRow
          label="CPU governor"
          value={power.cpuGovernor || "Unavailable"}
          good={power.cpuGovernor === "schedutil"}
        />
        <StatusRow
          label="CPU clock"
          value={power.cpuCurrentMhz ? `${power.cpuCurrentMhz} MHz` : "Unavailable"}
        />
        <StatusRow label="Idle states" value={`${power.cStates} states`} good={power.cStates >= 3} />
        <StatusRow
          label="GPU governor"
          value={
            snapshot.gpu.dbusReady
              ? "Active · D-Bus ready"
              : power.governor.active === "active"
                ? "Active · D-Bus unavailable"
                : power.governor.active
          }
          good={snapshot.gpu.dbusReady}
        />
      </PanelSection>

      <PanelSection title="Boot Behavior">
        <StatusRow
          label="Adaptive GPU governor"
          value={governorEnabled ? "Enabled" : "Disabled"}
          good={governorEnabled}
        />
        <StatusRow
          label="Frequency replay"
          value={power.frequencyRestore.enabled}
          good={power.frequencyRestore.enabled === "enabled"}
        />
      </PanelSection>
    </>
  );
}
