import { downloadURL, repoURL } from "@/lib/site";

/**
 * heyclicky spells its name out of Finder folders. DaemonFlow spells it out
 * of the capsule bars from its icon and pill: each glyph is a small bitmap,
 * and every straight run of lit cells, down or across, becomes one rounded
 * bar. Overlapping bars join into strokes.
 */
const glyphs: Record<string, string[]> = {
  d: ["....#", "....#", "#####", "#...#", "#...#", "#...#", "#####"],
  a: [".....", ".....", "####.", "....#", "#####", "#...#", "#####"],
  e: [".....", ".....", "#####", "#...#", "#####", "#....", "#####"],
  m: [".....", ".....", "#####", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
  o: [".....", ".....", "#####", "#...#", "#...#", "#...#", "#####"],
  n: [".....", ".....", "#####", "#...#", "#...#", "#...#", "#...#"],
  f: ["..##", ".#..", "####", ".#..", ".#..", ".#..", ".#.."],
  l: ["#", "#", "#", "#", "#", "#", "#"],
  w: [".....", ".....", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#####"],
};

const cell = 10;
const stroke = 7;

type Bar = { x: number; y: number; width: number; height: number };

function barsFor(word: string): { bars: Bar[]; width: number } {
  const bars: Bar[] = [];
  let column = 0;

  for (const letter of word) {
    const rows = glyphs[letter];
    const glyphWidth = rows[0].length;
    const lit = (x: number, y: number) => rows[y]?.[x] === "#";
    const covered = new Set<string>();

    // Down strokes.
    for (let x = 0; x < glyphWidth; x++) {
      for (let y = 0; y < 7; ) {
        let end = y;
        while (lit(x, end)) end++;
        if (end - y >= 2) {
          bars.push({ x: (column + x) * cell, y: y * cell, width: stroke, height: (end - y) * cell - (cell - stroke) });
          for (let k = y; k < end; k++) covered.add(`${x},${k}`);
        }
        y = Math.max(end, y + 1);
      }
    }

    // Across strokes, then any cell neither pass reached as a dot.
    for (let y = 0; y < 7; y++) {
      for (let x = 0; x < glyphWidth; ) {
        let end = x;
        while (lit(end, y)) end++;
        const length = end - x;
        if (length >= 2) {
          bars.push({ x: (column + x) * cell, y: y * cell, width: length * cell - (cell - stroke), height: stroke });
        } else if (length === 1 && !covered.has(`${x},${y}`)) {
          bars.push({ x: (column + x) * cell, y: y * cell, width: stroke, height: stroke });
        }
        x = Math.max(end, x + 1);
      }
    }

    column += glyphWidth + 1;
  }

  return { bars, width: (column - 1) * cell - (cell - stroke) };
}

const { bars, width } = barsFor("daemonflow");

export function Footer() {
  return (
    <footer className="footer">
      <div className="footer-cols">
        <nav aria-label="Product">
          <h3>product</h3>
          <a href="#features">features</a>
          <a href={downloadURL}>download</a>
          <a href={`${repoURL}/releases`}>release notes</a>
        </nav>
        <nav aria-label="Source">
          <h3>source</h3>
          <a href={repoURL}>github</a>
          <a href={`${repoURL}#building-from-source`}>build from source</a>
          <a href={`${repoURL}/issues`}>report a bug</a>
        </nav>
        <div className="footer-disclaimer">
          <h3>privacy</h3>
          <p>*daemonflow only reads your screen while you hold fn, and never reads password fields*</p>
        </div>
      </div>

      <svg className="bars-wordmark" viewBox={`0 0 ${width} ${7 * cell}`} role="img" aria-label="daemonflow">
        {bars.map((bar) => (
          <rect key={`${bar.x}-${bar.y}-${bar.width}`} x={bar.x} y={bar.y} width={bar.width} height={bar.height} rx={stroke / 2} />
        ))}
      </svg>

      <p className="copyright">© 2026 kaihere14</p>
    </footer>
  );
}
