import type { ReactNode } from "react";

type Props = {
  title?: string;
  /** Tints the title bar: "notes" is Notes' yellow, "terminal" is dark. */
  variant?: "default" | "notes" | "terminal";
  className?: string;
  children: ReactNode;
};

/** A macOS window frame: traffic lights, centred title, content below. */
export function Window({ title = "", variant = "default", className = "", children }: Props) {
  return (
    <div className={`win win-${variant} ${className}`}>
      <div className="win-bar">
        <span className="win-lights" aria-hidden="true">
          <i />
          <i />
          <i />
        </span>
        <span className="win-title">{title}</span>
      </div>
      {children}
    </div>
  );
}
