import { Focusable } from "@decky/ui";
import type { ReactNode } from "react";
import { ScrollViewport } from "./ScrollViewport";

export interface VerticalTab {
  id: string;
  label: string;
  icon: ReactNode;
  healthy: boolean;
  content: ReactNode;
}

export function VerticalTabs({
  tabs,
  active,
  onChange,
}: {
  tabs: VerticalTab[];
  active: string;
  onChange: (id: string) => void;
}) {
  const selected = tabs.find((tab) => tab.id === active) ?? tabs[0];

  return (
    <Focusable
      flow-children="right"
      style={{ display: "flex", alignItems: "stretch", height: "100%", minHeight: 0 }}
    >
      <Focusable
        flow-children="down"
        style={{
          width: 132,
          flex: "0 0 132px",
          padding: "14px 8px",
          borderRight: "1px solid rgba(255,255,255,0.10)",
          background: "rgba(0,0,0,0.12)",
        }}
      >
        {tabs.map((tab) => {
          const isActive = tab.id === selected.id;
          return (
            <Focusable
              key={tab.id}
              tabIndex={0}
              role="button"
              aria-selected={isActive}
              onFocus={() => onChange(tab.id)}
              onActivate={() => onChange(tab.id)}
              onClick={() => onChange(tab.id)}
              style={{
                position: "relative",
                display: "flex",
                minHeight: 50,
                marginBottom: 6,
                padding: "8px 12px",
                alignItems: "center",
                gap: 10,
                borderRadius: 6,
                color: isActive ? "#fff" : "#aeb3b8",
                background: isActive ? "rgba(64, 148, 255, 0.30)" : "transparent",
                fontSize: 13,
                fontWeight: isActive ? 700 : 500,
                textAlign: "center",
              }}
            >
              <span style={{ fontSize: 17, lineHeight: 1 }}>{tab.icon}</span>
              <span>{tab.label}</span>
              <span
                style={{
                  position: "absolute",
                  right: 5,
                  top: 5,
                  width: 6,
                  height: 6,
                  borderRadius: "50%",
                  background: tab.healthy ? "#59d185" : "#e6ad55",
                }}
              />
            </Focusable>
          );
        })}
      </Focusable>
      <div
        style={{
          minWidth: 0,
          minHeight: 0,
          height: "100%",
          flex: 1,
          overflow: "hidden",
        }}
      >
        <ScrollViewport>
          <Focusable
            key={selected.id}
            flow-children="down"
            style={{
              boxSizing: "border-box",
              width: "100%",
              padding: "14px 24px 96px",
            }}
          >
            {selected.content}
          </Focusable>
        </ScrollViewport>
      </div>
    </Focusable>
  );
}
