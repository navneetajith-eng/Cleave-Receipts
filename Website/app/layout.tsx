import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host") ?? "cleave-privacy-support.ryliemadisono.chatgpt.site";
  const protocol = requestHeaders.get("x-forwarded-proto") ?? (host.includes("localhost") ? "http" : "https");
  const metadataBase = new URL(`${protocol}://${host}`);
  const description = "Official privacy, security, and support information for the Cleave receipt splitting app.";

  return {
    metadataBase,
    title: "Cleave | Privacy & Support",
    description,
    icons: { icon: "/cleave-app-icon.png", shortcut: "/cleave-app-icon.png", apple: "/cleave-app-icon.png" },
    openGraph: {
      type: "website",
      title: "Cleave | Privacy & Support",
      description,
      images: [{ url: "/og.png", width: 1200, height: 630, alt: "Cleave Privacy & Support" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Cleave | Privacy & Support",
      description,
      images: ["/og.png"],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
