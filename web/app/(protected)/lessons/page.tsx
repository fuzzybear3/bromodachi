"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase/client";

// /lessons → the newest active lesson's review (the nav link target).
export default function LessonsIndex() {
  const router = useRouter();
  useEffect(() => {
    supabase.from("lessons").select("id, active").order("taught_on", { ascending: false })
      .then(({ data }) => {
        const pick = data?.find((l) => l.active) ?? data?.[0];
        if (pick) router.replace(`/lessons/${pick.id}`);
      });
  }, [router]);
  return null;
}
