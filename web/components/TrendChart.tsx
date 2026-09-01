import type { DayPoint } from "@/lib/stats";

// Daily accuracy for the last 30 days: one polyline, no chart library.
// Days without attempts are gaps. <title> gives native hover per point.
export function TrendChart({ points }: { points: DayPoint[] }) {
  const W = 300, H = 80, PAD = 4;
  const step = (W - 2 * PAD) / Math.max(points.length - 1, 1);
  const active = points
    .map((p, i) => ({ ...p, i }))
    .filter((p) => p.total > 0);
  const xy = (p: { i: number; correct: number; total: number }) =>
    `${PAD + p.i * step},${H - PAD - (p.correct / p.total) * (H - 2 * PAD)}`;
  return (
    <div className="panel trend">
      <h2>Accuracy - last 30 days</h2>
      {active.length === 0 ? (
        <p className="muted">No attempts yet.</p>
      ) : (
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
          <line x1={PAD} y1={PAD} x2={W - PAD} y2={PAD} stroke="#8888aa33" />
          <line x1={PAD} y1={H - PAD} x2={W - PAD} y2={H - PAD} stroke="#8888aa33" />
          <polyline
            points={active.map(xy).join(" ")}
            fill="none" stroke="#f0c419" strokeWidth="2"
          />
          {active.map((p) => (
            <circle key={p.day} cx={xy(p).split(",")[0]} cy={xy(p).split(",")[1]} r="2.5" fill="#f0c419">
              <title>{`${p.day}: ${p.correct}/${p.total}`}</title>
            </circle>
          ))}
        </svg>
      )}
    </div>
  );
}
