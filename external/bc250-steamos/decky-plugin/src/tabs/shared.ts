import type { Snapshot } from "../types";

export interface Confirmation {
  title: string;
  description: string;
  destructive?: boolean;
}

export interface MutationOptions {
  refresh?: boolean;
  successToast?: boolean;
}

export type MutationRunner = (
  label: string,
  operation: () => Promise<void>,
  confirmation?: Confirmation,
  options?: MutationOptions,
) => void;

export interface TabProps {
  snapshot: Snapshot;
  busy: boolean;
  runMutation: MutationRunner;
}
