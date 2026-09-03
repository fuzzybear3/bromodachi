// Read-time divergence between what was typed and what was expected. The
// design stores raw strings only; the diff is never persisted.
//
// Character-level LCS over code points (so a kanji or a small っ is one
// unit). Output is the submitted string cut into runs, each flagged as
// shared-with-expected or divergent.

export interface Seg {
  text: string;
  changed: boolean;
}

export interface Hunk {
  /** run of expected characters that the typed text lacks */
  del: string;
  /** run of typed characters that the expected text lacks */
  ins: string;
}

interface Alignment {
  segs: Seg[];
  hunks: Hunk[];
}

export function normalize(s: string): string {
  return s.replace(/[\s　]+/g, "").toLowerCase();
}

export function align(submitted: string, expected: string): Alignment {
  const a = Array.from(normalize(submitted));
  const b = Array.from(normalize(expected));
  const n = a.length, m = b.length;
  // dp[i][j] = LCS length of a[i..] and b[j..]
  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--)
    for (let j = m - 1; j >= 0; j--)
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);

  const segs: Seg[] = [];
  const hunks: Hunk[] = [];
  let i = 0, j = 0;
  let ins = "", del = "";
  const flush = () => {
    if (ins || del) hunks.push({ del, ins });
    ins = ""; del = "";
  };
  const push = (text: string, changed: boolean) => {
    const last = segs[segs.length - 1];
    if (last && last.changed === changed) last.text += text;
    else segs.push({ text, changed });
  };
  while (i < n || j < m) {
    if (i < n && j < m && a[i] === b[j]) {
      flush();
      push(a[i], false);
      i++; j++;
    } else if (j < m && (i >= n || dp[i][j + 1] >= dp[i + 1][j])) {
      del += b[j]; j++;
    } else {
      ins += a[i]; push(a[i], true); i++;
    }
  }
  flush();
  return { segs, hunks };
}

/** The single divergence, when there is exactly one; null otherwise. */
export function soleHunk(submitted: string, expected: string): Hunk | null {
  const { hunks } = align(submitted, expected);
  return hunks.length === 1 ? hunks[0] : null;
}
