import type { LessonMastery } from "@/lib/stats";

export function MasteryBars({ rows }: { rows: LessonMastery[] }) {
  return (
    <div className="panel">
      <h2>Lesson mastery</h2>
      {rows.map(({ lesson, mastered, total }) => (
        <div className="mastery-row" key={lesson.id}>
          <span>
            {lesson.taught_on}
            {lesson.title ? <span className="muted"> · {lesson.title}</span> : null}
          </span>
          <div className="bar">
            <div style={{ width: total ? `${(mastered / total) * 100}%` : 0 }} />
          </div>
          <span className="frac">{mastered}/{total}</span>
        </div>
      ))}
    </div>
  );
}
