import { ScrollPanel } from "@decky/ui";
import type { ComponentType, CSSProperties, ReactNode } from "react";

// Decky's runtime component accepts style, but the published type only lists children.
const RuntimeScrollPanel = ScrollPanel as ComponentType<{
  children?: ReactNode;
  style?: CSSProperties;
}>;

export function ScrollViewport({ children }: { children: ReactNode }) {
  return (
    <RuntimeScrollPanel style={{ width: "100%", height: "100%", minHeight: 0 }}>
      {children}
    </RuntimeScrollPanel>
  );
}
