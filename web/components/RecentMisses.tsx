import Link from "next/link";
import type { Attempt, Question } from "@/lib/types";

export function RecentMisses({ misses, questions }: {
  misses: Attempt[];
  questions: Map<string, Question>;
}) {
  return (
    <div className="panel">
      <h2>Recent misses</h2>
      {misses.length === 0 ? (
        <p className="muted">Nothing missed lately. すごい！</p>
      ) : (
        <table>
          <thead>
            <tr><th>Question</th><th>You typed</th><th>Hint</th><th>When</th></tr>
          </thead>
          <tbody>
            {misses.map((a) => {
              const q = questions.get(a.question_id);
              return (
                <tr key={a.id}>
                  <td lang="ja"><Link href={`/questions/${a.question_id}`}>{q?.prompt ?? "?"}</Link></td>
                  <td lang="ja" className="miss">{a.typed || "—"}</td>
                  <td className="muted">{a.hint_used ? "used" : ""}</td>
                  <td className="muted">{new Date(a.answered_at).toLocaleString()}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}
