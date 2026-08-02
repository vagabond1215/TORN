import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host") ?? "localhost:3000";
  const protocol = requestHeaders.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  const origin = `${protocol}://${host}`;
  const image = new URL("/og.png", origin).toString();

  return {
    metadataBase: new URL(origin),
    title: "Faction Ledger — Torn City Budget Tracker",
    description: "Distribute faction proceeds, manage earmarked accounts, and keep a clean audit trail.",
    openGraph: {
      title: "Faction Ledger",
      description: "Put every dollar to work.",
      type: "website",
      images: [{ url: image, width: 1200, height: 630, alt: "Faction Ledger allocation dashboard" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Faction Ledger",
      description: "Put every dollar to work.",
      images: [image],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
