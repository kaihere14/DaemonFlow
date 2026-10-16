import Image from "next/image";
import { requirements } from "@/lib/site";
import { Window } from "./Window";

/**
 * Where heyclicky shows testimonials. DaemonFlow has none yet and won't
 * invent any, so this slot holds the facts instead, as an About window.
 */
const specs = [
  ["Transcription", "Whisper (Tiny to Large v3 Turbo) with Metal, or Parakeet TDT 0.6B on the Neural Engine"],
  ["Cleanup", "Llama 3.2, Qwen 2.5, Phi 3.5 or Llama 3.1 8B, running locally on MLX"],
  ["Shortcuts", "Hold Fn to dictate, double-tap Fn for hands-free, ⌥1 to refine"],
  ["Extras", "Custom vocabulary, editable prompts, your own pill size and colours"],
  ["Network", "Only to download models from Hugging Face, when you pick one"],
  ["Requires", requirements],
] as const;

export function About() {
  return (
    <section className="about" aria-labelledby="about-title">
      <Window className="about-win">
        <div className="about-body">
          <Image src="/app-icon.png" alt="" width={128} height={128} />
          <div>
            <h2 id="about-title">DaemonFlow</h2>
            <p className="about-version">Version 1.1.0</p>
            <dl>
              {specs.map(([term, detail]) => (
                <div key={term}>
                  <dt>{term}</dt>
                  <dd>{detail}</dd>
                </div>
              ))}
            </dl>
          </div>
        </div>
      </Window>
    </section>
  );
}
