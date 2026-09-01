import type { WeekRow } from "@/lib/stats";
import { fmtDur } from "@/lib/format";

export function WeeklyTable({ rows }: { rows: WeekRow[] }) {
  return (
    <div className="panel">
      <h2>Week by week</h2>
      {rows.length === 0 ? (
        <p className="muted">No attempts yet.</p>
      ) : (
        <table>
          <thead>
            <tr><th>week of</th><th>answers</th><th>accuracy</th><th>study time</th>
                <th>words touched</th><th>new words</th><th>hint %</th></tr>
          </thead>
          <tbody>
            {rows.map((w) => (
              <tr key={w.weekStart}>
                <td>{w.weekStart}</td>
                <td>{w.answers}</td>
                <td>{Math.round((w.correct / w.answers) * 100)}%</td>
                <td>{fmtDur(w.activeMs)}</td>
                <td>{w.distinct}</td>
                <td>{w.newSeen}</td>
                <td className="muted">{Math.round((w.hintUsed / w.answers) * 100)}%</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
