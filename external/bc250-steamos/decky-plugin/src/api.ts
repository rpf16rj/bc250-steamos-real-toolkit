import { callable } from "@decky/api";
import type { Snapshot, TelemetrySample } from "./types";

export const getSnapshot = callable<[], Snapshot>("get_snapshot");
export const getTelemetry = callable<[], TelemetrySample>("get_telemetry");
export const setCuWgp = callable<
  [se: number, sh: number, wgp: number, enabled: boolean],
  void
>("set_cu_wgp");
export const setGpuFrequency = callable<
  [mode: string, minimum: number, maximum: number],
  void
>("set_gpu_frequency");
export const setLoadTarget = callable<[preset: string], void>(
  "set_load_target",
);
export const setCustomLoadTarget = callable<
  [minimum: number, maximum: number],
  void
>("set_custom_load_target");
export const setRamp = callable<[climbMs: number], void>("set_ramp");
export const cpuOcAction = callable<
  [action: string, frequency: number, voltage: number, temperature: number],
  void
>("cpu_oc_action");
export const cecAction = callable<[action: string], void>("cec_action");
export const setCecToggle = callable<
  [key: string, enabled: boolean],
  void
>("set_cec_toggle");
export const setCecName = callable<[name: string], void>("set_cec_name");
