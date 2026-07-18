import { ButtonItem, PanelSectionRow } from "@decky/ui";
import type { ReactNode } from "react";

export function StatusRow({
  label,
  value,
  good,
}: {
  label: string;
  value: ReactNode;
  good?: boolean;
}) {
  return (
    <PanelSectionRow>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 12,
          width: "100%",
          minHeight: 28,
        }}
      >
        <span style={{ color: "#b8bcbf", fontSize: 13 }}>{label}</span>
        <span
          style={{
            color: good === undefined ? "#f2f2f2" : good ? "#59d185" : "#e6ad55",
            fontSize: 13,
            fontWeight: 600,
            textAlign: "right",
          }}
        >
          {value}
        </span>
      </div>
    </PanelSectionRow>
  );
}

export function ActionButton({
  label,
  description,
  disabled,
  onClick,
}: {
  label: string;
  description?: string;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <PanelSectionRow>
      <ButtonItem
        layout="below"
        description={description}
        disabled={disabled}
        onClick={onClick}
      >
        {label}
      </ButtonItem>
    </PanelSectionRow>
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return (
    <div
      style={{
        margin: "12px 8px",
        padding: 12,
        borderRadius: 6,
        background: "rgba(230, 173, 85, 0.12)",
        color: "#e6c48f",
        fontSize: 13,
        lineHeight: 1.4,
      }}
    >
      {children}
    </div>
  );
}
