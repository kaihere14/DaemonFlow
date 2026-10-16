import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  // Absolute URLs for the Open Graph image need a base; set
  // NEXT_PUBLIC_SITE_URL to the real domain when deploying.
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
  title: "DaemonFlow: voice to text that stays on your Mac",
  description:
    "Hold Fn, talk, let go. DaemonFlow transcribes and cleans up your voice on your Mac, then pastes it wherever you're typing. Free, no account.",
  openGraph: {
    title: "DaemonFlow",
    description: "Talk normally. It types what you meant. Free, private voice dictation for macOS.",
  },
  twitter: { card: "summary_large_image" },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
