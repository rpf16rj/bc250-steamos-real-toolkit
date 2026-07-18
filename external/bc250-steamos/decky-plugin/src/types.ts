export interface ServiceState {
  enabled: string;
  active: string;
}

export interface CuRow {
  se: number;
  sh: number;
  spi: number | null;
  cc: number | null;
  wgps: boolean[];
  cus: number;
  factoryCuMask: number | null;
  factoryWgps: boolean[];
}

export interface CuStatus {
  available: boolean;
  controllable: boolean;
  liveReason: string | null;
  total: number;
  maximum: number;
  rows: CuRow[];
  savedMasks: number[];
  factoryMapAvailable: boolean;
  factoryTotal: number | null;
  service: ServiceState;
  protected: boolean;
}

export interface Temperature {
  device: string;
  label: string;
  celsius: number;
}

export interface TelemetrySample {
  cpuClock: number | null;
  gpuClock: number | null;
  cpuTemp: number | null;
  gpuTemp: number | null;
}

export interface PowerStatus {
  acpiActive: boolean;
  cStates: number;
  cpuGovernor: string;
  cpuCurrentMhz: number | null;
  governor: ServiceState;
  acpiService: ServiceState;
  cpufreqService: ServiceState;
  frequencyRestore: ServiceState;
  temperatures: Temperature[];
  protected: boolean;
}

export interface SafePoint {
  frequency: number | null;
  voltage: number | null;
}

export type GpuMode = "adaptive" | "max" | "pin" | "range";

export interface GpuStatus {
  available: boolean;
  controllable: boolean;
  dbusReady: boolean;
  mode: GpuMode;
  requestedMode: GpuMode;
  requestedMinimum: number;
  requestedMaximum: number;
  minimum: number;
  maximum: number;
  liveMinimum: number | null;
  liveMaximum: number | null;
  activeMhz: number | null;
  levels: string[];
  allowedMinimum: number | null;
  allowedMaximum: number | null;
  climbMs: number | null;
  frequencyRestore: ServiceState;
  persistent: boolean;
  replayApplied: boolean;
  safePoints: SafePoint[];
  configuredMax: number | null;
  loadUpper: number | null;
  loadLower: number | null;
  adjustMicros: number | null;
  rampNormal: number | null;
  downEvents: number | null;
}

export interface CpuConfig {
  values: Record<string, string>;
  detected: string;
}

export interface CpuStatus {
  service: ServiceState;
  installed: CpuConfig | null;
  staged: CpuConfig | null;
  toolAvailable: boolean;
}

export interface CecStatus {
  devicePresent: boolean;
  service: ServiceState;
  osdName: string | null;
  wakeTv: boolean | null;
  suspendTv: boolean | null;
  allowStandby: boolean | null;
  uinput: boolean | null;
  active: boolean | null;
  physicalAddress: number | null;
  audioLogicalAddress: number | null;
  poweroffIntegration: boolean;
  sleepIntegration: boolean;
  protected: boolean;
}

export interface Snapshot {
  toolkit: {
    available: boolean;
    privileged: boolean;
    powerAvailable: boolean;
    cpuControlAvailable: boolean;
    cecAvailable: boolean;
    path: string;
  };
  cu: CuStatus;
  power: PowerStatus;
  gpu: GpuStatus;
  cpu: CpuStatus;
  cec: CecStatus;
}
