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
    title: "Blood Coven Treasury",
    description: "Private Blood Coven faction treasury with tax settlement, account balances, and persistent history.",
    robots: { index: false, follow: false, nocache: true },
    openGraph: {
      title: "Blood Coven Treasury",
      description: "Settle proceeds. Track the faction share.",
      type: "website",
      images: [{ url: image, width: 1200, height: 630, alt: "Blood Coven Treasury leadership ledger" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Blood Coven Treasury",
      description: "Settle proceeds. Track the faction share.",
      images: [image],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
