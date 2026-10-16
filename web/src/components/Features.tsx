import Image from "next/image";
import type { ReactNode } from "react";
import { StaticPill } from "./Pill";
import { Window } from "./Window";

type Feature = {
  image: string;
  alt: string;
  pill: "recording" | "refining" | "done" | "processing";
  title: string;
  body: ReactNode;
};

const features: Feature[] = [
  {
    image: "how-it-works.jpg",
    alt: "Three steps: hold Fn and talk while the pill shows a live preview, let go while it transcribes, and the text is pasted.",
    pill: "recording",
    title: "hold fn, talk, let go",
    body: "A pill above the Dock shows what it's hearing while you talk. Let go and Whisper or Parakeet transcribes it, a small model on your Mac cleans it up, and the text is pasted into the app you were typing in.",
  },
  {
    image: "screen-awareness.jpg",
    alt: "Supabase and Vercel are picked up from the screen, so 'push the super base migration then redeploy on for sell' becomes 'Push the Supabase migration, then redeploy on Vercel.'",
    pill: "processing",
    title: "your screen is the context",
    body: "Names and jargon in the window you're working in become spelling hints. With Supabase on screen, you get Supabase, not \"super base\". Password fields are never read, and you can turn it off.",
  },
  {
    image: "refine.jpg",
    alt: "Selected text is rewritten in place after holding Option-1 and saying 'make it more formal'.",
    pill: "refining",
    title: "fix any text with ⌥1",
    body: (
      <>
        Select text in any app and tap <kbd>⌥1</kbd> to clean it up in place. Hold <kbd>⌥1</kbd> and say how you want it changed, like
        &ldquo;make it more formal&rdquo;.
      </>
    ),
  },
  {
    image: "models.jpg",
    alt: "The Models page: Parakeet TDT 0.6B for transcription and Llama 3.2 3B for cleanup, both in use.",
    pill: "done",
    title: "every word stays on your mac",
    body: "Speech and cleanup models run on your Mac. Download them once and it works offline, with no account and nothing sent anywhere.",
  },
];

export function Features() {
  return (
    <section className="features" id="features" aria-label="Features">
      {features.map((feature, index) => (
        <article key={feature.image} className={`row ${index % 2 ? "row-flip" : ""}`}>
          <figure className="shot">
            <Window title={feature.image}>
              <Image src={`/${feature.image}`} alt={feature.alt} width={1600} height={900} sizes="(max-width: 860px) 100vw, 640px" />
            </Window>
          </figure>
          <div className="row-copy">
            <StaticPill state={feature.pill} />
            <h2>{feature.title}</h2>
            <p>{feature.body}</p>
          </div>
        </article>
      ))}
    </section>
  );
}
