"use client";
// The Industry pieces every screen shares: the blueprint frame, the
// attempt strip, horizontal bars, segmented control, checkbox, stat pair.
// Plain CSS on plain elements — no charting library (deliberately).
import type { CSSProperties, ReactNode } from "react";
import type { TrendBar } from "@/lib/agg";

export function Corners() {
  return (
    <>
      <i className="corner tl" /><i className="corner tr" /><i className="corner bl" /><i className="corner br" />
    </>
  );
}

export function Blueprint({ className = "", style, children }: {
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
}) {
  return (
    <div className={`card blueprint ${className}`} style={style}>
      <Corners />
      {children}
    </div>
  );
}

/** Six bars, oldest left: correct = full accent, wrong = short neutral. */
export function AttemptStrip({ results }: { results: boolean[] }) {
  return (
    <span className="strip">
      {results.map((ok, i) => (
        <i key={i} className={ok ? "on" : ""} style={{ height: ok ? "100%" : "35%" }} />
      ))}
    </span>
  );
}

/** Height = the period's accuracy; accent where it beat the previous period. */
export function TrendStrip({ bars }: { bars: TrendBar[] }) {
  return (
    <span className="strip" title={bars.map((b) => (b.n ? `${b.h}% (${b.n})` : "—")).join(" · ")}>
      {bars.map((b, i) => (
        <i key={i} className={b.on ? "on" : ""} style={{ height: `${b.h}%` }} />
      ))}
    </span>
  );
}

export function Bar({ ratio, className = "" }: { ratio: number | null; className?: string }) {
  return (
    <span className={`bar ${className}`}>
      <span style={{ width: `${Math.round((ratio ?? 0) * 100)}%` }} />
    </span>
  );
}

export function Seg<T extends string>({ name, value, options, onChange }: {
  name: string;
  value: T;
  options: { value: T; label: ReactNode }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="seg">
      {options.map((o) => (
        <label className="seg-opt" key={o.value}>
          <input type="radio" name={name} checked={value === o.value} onChange={() => onChange(o.value)} />
          {o.label}
        </label>
      ))}
    </div>
  );
}

export function Check({ checked, onChange, children, disabled }: {
  checked: boolean;
  onChange: (v: boolean) => void;
  children?: ReactNode;
  disabled?: boolean;
}) {
  return (
    <label className="radio" style={disabled ? { opacity: 0.45, cursor: "not-allowed" } : undefined}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      <span className="dot" />
      {children}
    </label>
  );
}

export function StatPair({ value, unit, label, size = 32 }: {
  value: string;
  unit?: string;
  label: string;
  size?: number;
}) {
  return (
    <div>
      <div className="big" style={{ fontSize: size }}>
        {value}{unit && <span className="unit">{unit}</span>}
      </div>
      <div className="card-kicker">{label}</div>
    </div>
  );
}

/** A stat in a blueprint card (the 5-up row on question history). */
export function StatCard({ value, unit, label }: { value: string; unit?: string; label: string }) {
  return (
    <Blueprint className="pad-14">
      <div className="big" style={{ fontSize: 28 }}>
        {value}{unit && <span style={{ fontSize: 17 }}>{unit}</span>}
      </div>
      <div className="card-kicker">{label}</div>
    </Blueprint>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="muted prose-13" style={{ padding: "4px 0" }}>{children}</p>;
}
