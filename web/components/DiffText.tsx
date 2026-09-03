import { align } from "@/lib/diff";

/** The submitted text with its divergent runs highlighted. */
export function DiffText({ submitted, expected }: { submitted: string; expected: string }) {
  const { segs } = align(submitted, expected);
  return (
    <span lang="ja">
      {segs.map((s, i) => (s.changed ? <span key={i} className="hl">{s.text}</span> : <span key={i}>{s.text}</span>))}
    </span>
  );
}
