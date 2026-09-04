import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "日本語トレーニング",
  description: "Japanese study buddy - progress and question management",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
