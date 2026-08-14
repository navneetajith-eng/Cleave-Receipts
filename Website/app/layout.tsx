import type { Metadata } from "next";
import "./globals.css";

export async function generateMetadata(): Promise<Metadata> {
  const metadataBase = new URL("https://navneetajith-eng.github.io");
  const description = "Official privacy, security, and support information for the Cleave receipt splitting app.";

  return {
    metadataBase,
    alternates: { canonical: "/cleave/" },
    title: "Cleave | Privacy & Support",
    description,
    icons: { icon: "/cleave/cleave-app-icon.png", shortcut: "/cleave/cleave-app-icon.png", apple: "/cleave/cleave-app-icon.png" },
    openGraph: {
      type: "website",
      title: "Cleave | Privacy & Support",
      description,
      images: [{ url: "/cleave/og.png", width: 1200, height: 630, alt: "Cleave Privacy & Support" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Cleave | Privacy & Support",
      description,
      images: ["/cleave/og.png"],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
