import Image from "next/image";
import { downloadURL, repoURL, requirements } from "@/lib/site";
import { Demo } from "./Demo";

/**
 * heyclicky scatters desktop clutter around its wordmark; here the clutter
 * is what DaemonFlow throws away (struck-through filler words) plus the
 * keys you press to use it.
 */
const floaters = [
  { kind: "key", text: "fn", x: "9%", y: "17%", r: "-8deg" },
  { kind: "key", text: "⌥", x: "87%", y: "31%", r: "10deg" },
  { kind: "word", text: "um", x: "17%", y: "40%", r: "-4deg" },
  { kind: "word", text: "uh", x: "76%", y: "46%", r: "5deg" },
  { kind: "word", text: "like", x: "26%", y: "8%", r: "3deg" },
  { kind: "word", text: "you know", x: "66%", y: "14%", r: "-6deg" },
  { kind: "word", text: "no wait", x: "5%", y: "54%", r: "6deg" },
] as const;

export function Hero() {
  return (
    <header className="hero">
      <div className="floaters" aria-hidden="true">
        {floaters.map((item) =>
          item.kind === "key" ? (
            <span key={item.text} className="floater key" style={{ left: item.x, top: item.y, rotate: item.r }}>
              {item.text}
            </span>
          ) : (
            <s key={item.text} className="floater filler" style={{ left: item.x, top: item.y, rotate: item.r }}>
              {item.text}
            </s>
          ),
        )}
        <Image className="floater app-icon" src="/app-icon.png" alt="" width={72} height={72} style={{ left: "79%", top: "6%", rotate: "8deg" }} />
      </div>

      <h1 className="wordmark">daemonflow</h1>
      <p className="tagline">voice to text that never leaves your mac</p>
      <div className="ctas">
        <a className="btn btn-primary" href={downloadURL}>
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M8 1.5v8.2m0 0L4.8 6.5M8 9.7l3.2-3.2M2.5 11.5v1.2c0 .7.6 1.3 1.3 1.3h8.4c.7 0 1.3-.6 1.3-1.3v-1.2" />
          </svg>
          download for mac
        </a>
        <a className="btn" href={repoURL}>
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M8 .2a8 8 0 0 0-2.5 15.6c.4 0 .5-.2.5-.4v-1.5c-2.2.5-2.7-1-2.7-1-.4-.9-.9-1.2-.9-1.2-.7-.5.1-.5.1-.5.8.1 1.2.8 1.2.8.7 1.3 1.9.9 2.3.7.1-.5.3-.9.5-1.1-1.8-.2-3.6-.9-3.6-4 0-.9.3-1.6.8-2.1-.1-.2-.4-1 .1-2.1 0 0 .7-.2 2.2.8a7.6 7.6 0 0 1 4 0c1.5-1 2.2-.8 2.2-.8.4 1.1.2 1.9.1 2.1.5.6.8 1.3.8 2.1 0 3.1-1.9 3.8-3.6 4 .3.3.6.8.6 1.5v2.2c0 .2.1.5.6.4A8 8 0 0 0 8 .2Z" />
          </svg>
          view the source
        </a>
      </div>
      <p className="fineprint">100% free, no account. {requirements}.</p>

      <Demo />
    </header>
  );
}
