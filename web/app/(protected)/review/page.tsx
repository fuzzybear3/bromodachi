"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase/client";

// /review → the newest active lesson's review sheet.
export default function ReviewIndex() {
  const router = useRouter();
  useEffect(() => {
    supabase.from("lessons").select("id, active").order("taught_on", { ascending: false })
      .then(({ data }) => {
        const pick = data?.find((l) => l.active) ?? data?.[0];
        if (pick) router.replace(`/lessons/${pick.id}/review`);
      });
  }, [router]);
  return null;
}
