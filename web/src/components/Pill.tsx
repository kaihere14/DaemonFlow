/**
 * The app's floating HUD pill, drawn with its real defaults: #15181D fill,
 * #242832 hairline, #7C5CFF waveform. Static versions sit beside each
 * feature the way heyclicky's speech bubble does; the live one is in Demo.
 */

/** Fixed bar levels so the static pills look mid-sentence, not random. */
export const restingLevels = [0.2, 0.42, 0.7, 0.95, 0.6, 0.85, 0.5, 0.3, 0.75, 0.55, 0.35, 0.65, 0.4, 0.22];

export function Waveform({ levels }: { levels: readonly number[] }) {
  return (
    <span className="pill-wave">
      {levels.map((level, index) => (
        <i key={index} style={{ height: `${18 + level * 82}%` }} />
      ))}
    </span>
  );
}

type StaticPillProps = { state: "recording" | "refining" | "done" | "processing" };

export function StaticPill({ state }: StaticPillProps) {
  return (
    <span className="pill" data-state={state} aria-hidden="true">
      {state === "recording" && <Waveform levels={restingLevels} />}
      {state === "processing" && <span className="pill-spin" />}
      {state === "refining" && <span className="pill-shimmer">Refining</span>}
      {state === "done" && <span className="pill-done">✓ Done</span>}
    </span>
  );
}
