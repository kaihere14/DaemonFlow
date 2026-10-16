import Image from "next/image";
import { Window } from "./Window";

/** heyclicky's founder note, in the same Notes window. */
export function Note() {
  return (
    <section className="note" aria-labelledby="note-title">
      <h2 id="note-title" className="section-title">
        why i built it
      </h2>
      <Window title="Notes" variant="notes" className="note-win">
        <div className="note-body">
          <p>I used Wispr Flow. It&apos;s good, but my voice went to someone else&apos;s server, and the free tier ran out fast.</p>
          <p>
            So I built my own. Whisper or Parakeet hears you, a small model on your Mac cleans it up, and{" "}
            <mark>nothing ever leaves the machine</mark>.
          </p>
          <p>I&apos;ve dictated everything with it for the last couple of months, and I haven&apos;t missed the old one.</p>
          <p>
            It&apos;s free. Try it and tell me what breaks.
            <span className="caret" aria-hidden="true" />
          </p>
          <div className="note-sign">
            <Image src="/app-icon.png" alt="" width={40} height={40} />
            <div>
              <strong>kaihere14</strong>
              <span>built DaemonFlow</span>
            </div>
          </div>
        </div>
      </Window>
    </section>
  );
}
