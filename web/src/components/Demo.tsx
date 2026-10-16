"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Window } from "./Window";
import { Waveform } from "./Pill";

/**
 * The hero's stand-in for a video: hold the key and the pill streams a
 * messy sentence the way the real HUD's live preview does; let go and the
 * cleaned version types into the window. Scripted, but every pair is
 * behaviour the app really has (filler removal, self-corrections, spoken
 * lists, screen-aware spelling).
 */
const phrases = [
  {
    raw: "um so i think we should uh move the launch to thursday no wait friday because the the build isn't signed yet",
    clean: "I think we should move the launch to Friday, because the build isn't signed yet.",
  },
  {
    raw: "okay so for the grocery list first tomato second potato third onion",
    clean: "Grocery list:\n1. Tomato\n2. Potato\n3. Onion",
  },
  {
    raw: "can you push the super base migration then redeploy on for sell",
    clean: "Can you push the Supabase migration, then redeploy on Vercel?",
  },
] as const;

type PillState = "idle" | "recording" | "processing" | "done";

/** Matches the app: anything shorter is treated as an accidental tap. */
const minimumHoldMs = 400;
const wordIntervalMs = 170;
const processingMs = 650;
const typeIntervalMs = 16;
const liveCharacterLimit = 34;
const barCount = 14;

function liveTail(words: string[]): string {
  const text = words.join(" ");
  if (text.length <= liveCharacterLimit) return text;
  const tail = text.slice(-liveCharacterLimit);
  const space = tail.indexOf(" ");
  return "…" + (space >= 0 ? tail.slice(space + 1) : tail);
}

export function Demo() {
  const [pill, setPill] = useState<PillState>("idle");
  const [live, setLive] = useState("");
  const [levels, setLevels] = useState<number[]>(() => Array(barCount).fill(0));
  const [output, setOutput] = useState("");
  const [hint, setHint] = useState("Hold the key (or Space) and let go to see what gets pasted.");

  const phraseIndex = useRef(0);
  const pressedAt = useRef<number | null>(null);
  const timers = useRef<number[]>([]);
  const reduceMotion = useRef(false);

  useEffect(() => {
    reduceMotion.current = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const pending = timers.current;
    return () => pending.forEach((id) => window.clearInterval(id));
  }, []);

  const clearTimers = () => {
    timers.current.forEach((id) => window.clearInterval(id));
    timers.current = [];
  };

  const start = useCallback(() => {
    if (pressedAt.current !== null) return;
    clearTimers();
    pressedAt.current = performance.now();
    setPill("recording");
    setLive("");

    const words = phrases[phraseIndex.current].raw.split(" ");
    let heard = 0;
    timers.current.push(
      window.setInterval(() => {
        if (heard < words.length) {
          heard += 1;
          setLive(liveTail(words.slice(0, heard)));
        }
      }, wordIntervalMs),
    );
    timers.current.push(
      window.setInterval(() => {
        setLevels((previous) =>
          reduceMotion.current
            ? previous.map((_, index) => 0.35 + 0.3 * Math.sin(index))
            : [...previous.slice(1), 0.15 + Math.random() * 0.85],
        );
      }, 60),
    );
  }, []);

  const stop = useCallback(() => {
    if (pressedAt.current === null) return;
    const heldFor = performance.now() - pressedAt.current;
    pressedAt.current = null;
    clearTimers();
    setLevels(Array(barCount).fill(0));

    if (heldFor < minimumHoldMs) {
      setPill("idle");
      setHint("Too short to count as speech. Hold it while you talk.");
      return;
    }

    const { clean } = phrases[phraseIndex.current];
    phraseIndex.current = (phraseIndex.current + 1) % phrases.length;
    setPill("processing");
    setHint("Hold it again for another example.");

    const finish = window.setTimeout(() => {
      setPill("done");
      setOutput("");
      if (reduceMotion.current) {
        setOutput(clean);
      } else {
        let typed = 0;
        const typer = window.setInterval(() => {
          typed += 2;
          setOutput(clean.slice(0, typed));
          if (typed >= clean.length) window.clearInterval(typer);
        }, typeIntervalMs);
        timers.current.push(typer);
      }
      const rest = window.setTimeout(() => setPill((state) => (state === "done" ? "idle" : state)), 2000);
      timers.current.push(rest);
    }, processingMs);
    timers.current.push(finish);
  }, []);

  return (
    <figure className="demo">
      <Window title="Untitled" className="demo-win">
        <div className="demo-doc">
          <p className="demo-output" aria-live="polite">
            {output ? output : <span className="demo-placeholder">Your words land here.</span>}
            <span className="caret" aria-hidden="true" />
          </p>
        </div>
        <div className="demo-dock">
          <div className="pill pill-live" data-state={pill} aria-hidden="true">
            {pill === "recording" && (
              <>
                <Waveform levels={levels} />
                {live && <span className="pill-text">{live}</span>}
              </>
            )}
            {pill === "processing" && <span className="pill-spin" />}
            {pill === "done" && <span className="pill-done">✓ Done</span>}
          </div>
        </div>
      </Window>
      <figcaption className="demo-hint">
        <button
          type="button"
          className="key key-hold"
          data-pressed={pill === "recording"}
          aria-describedby="demo-hint-text"
          onPointerDown={(event) => {
            event.currentTarget.setPointerCapture(event.pointerId);
            start();
          }}
          onPointerUp={stop}
          onPointerCancel={stop}
          onKeyDown={(event) => {
            if ((event.key === " " || event.key === "Enter") && !event.repeat) {
              event.preventDefault();
              start();
            }
          }}
          onKeyUp={(event) => {
            if (event.key === " " || event.key === "Enter") stop();
          }}
          onBlur={stop}
          onContextMenu={(event) => event.preventDefault()}
        >
          fn
        </button>
        <span id="demo-hint-text">{hint}</span>
      </figcaption>
    </figure>
  );
}
