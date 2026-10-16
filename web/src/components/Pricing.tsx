import { downloadURL } from "@/lib/site";
import { Window } from "./Window";

const included = [
  "Unlimited dictation",
  "Every transcription and cleanup model",
  "Screen awareness and ⌥1 refine",
  "Works offline once models are downloaded",
];

/** heyclicky's sky-backed pricing, on DaemonFlow's violet canvas. One plan. */
export function Pricing() {
  return (
    <section className="pricing" id="download" aria-labelledby="pricing-title">
      <h2 id="pricing-title">daemonflow, for free</h2>
      <p className="pricing-sub">no account, no subscription, no word limit.</p>

      <div className="pricing-grid">
        <Window title="DaemonFlow" className="price-win">
          <div className="price-body">
            <p className="price-amount">$0</p>
            <p className="price-note">forever, on your own Mac</p>
            <a className="btn btn-primary" href={downloadURL}>
              download for mac
            </a>
            <ul>
              {included.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </div>
        </Window>

        <Window title="zsh" variant="terminal" className="term-win">
          <div className="term-body">
            <p className="term-title">
              &lt; build it yourself &gt;<span className="caret" aria-hidden="true" />
            </p>
            <pre>
              <code>
                {[
                  "git clone --recurse-submodules \\\n    https://github.com/kaihere14/DaemonFlow.git",
                  "cd DaemonFlow",
                  "./scripts/build-whisper.sh",
                  "./scripts/build-and-install.sh",
                ].map((line) => (
                  <span key={line} className="term-line">
                    <span className="term-prompt">$</span> {line}
                  </span>
                ))}
              </code>
            </pre>
            <p className="term-note">needs Xcode with the macOS 27 SDK and cmake.</p>
          </div>
        </Window>
      </div>

      <p className="pricing-foot">The app isn&apos;t notarized yet: open it the first time with right-click, then Open.</p>
    </section>
  );
}
