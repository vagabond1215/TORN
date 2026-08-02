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
    title: "Blood Coven Treasury — Leadership Ledger",
    description: "Private Blood Coven treasury allocations, spending, transfers, and persistent leadership history.",
    robots: { index: false, follow: false, nocache: true },
    openGraph: {
      title: "Blood Coven Treasury",
      description: "Guard the reserve. Fund the war.",
      type: "website",
      images: [{ url: image, width: 1200, height: 630, alt: "Blood Coven Treasury leadership ledger" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Blood Coven Treasury",
      description: "Guard the reserve. Fund the war.",
      images: [image],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
