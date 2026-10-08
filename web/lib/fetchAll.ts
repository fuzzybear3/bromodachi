import type { PostgrestError } from "@supabase/supabase-js";

// PostgREST answers at most 1000 rows per request (Supabase's default
// max-rows) and truncates without an error, so any table that grows is read
// in pages. Offset paging needs a total order: every caller's .order() chain
// ends on a unique column, or rows can repeat or vanish at page edges.
const PAGE = 1000;

type Page<T> = PromiseLike<{ data: T[] | null; error: PostgrestError | null }>;

/** Every row `query()` selects, PAGE at a time until a short page. `query`
 *  builds a fresh request per call because range() mutates the builder.
 *  Same { data, error } shape as a single request, so callers' error
 *  handling is unchanged. */
export async function fetchAll<T>(
  query: () => { range(from: number, to: number): Page<T> },
): Promise<{ data: T[] | null; error: PostgrestError | null }> {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await query().range(from, from + PAGE - 1);
    if (error) return { data: null, error };
    rows.push(...(data ?? []));
    if (!data || data.length < PAGE) return { data: rows, error: null };
  }
}
