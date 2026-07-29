import { useState, type CSSProperties } from "react";
import { PrivacyPolicy, TermsOfService } from "./LegalPages";
import { downloadUrl, repositoryUrl, SiteNavbar } from "./SiteNavbar";

type RevealStyle = CSSProperties & { "--delay": string; };

function reveal(delay: string): RevealStyle {
  return { "--delay": delay };
}

function AppComparison() {
  const [position, setPosition] = useState(50);
  const [isDragging, setIsDragging] = useState(false);
  const movementClass = isDragging
    ? "duration-75 ease-linear"
    : "duration-200 ease-out-expo";

  return (
    <figure
      className="reveal mx-auto mt-11 w-[min(calc(100%_-_1rem),88rem)] sm:mt-14 sm:w-[min(calc(100%_-_2rem),88rem)]"
      style={reveal("260ms")}
    >
      <div className="comparison-frame relative isolate overflow-hidden">
        <img
          src="/burrito-light.webp"
          srcSet="/burrito-light-1132.webp 1132w, /burrito-light.webp 2264w"
          sizes="(max-width: 1150px) calc(100vw - 16px), 1408px"
          width="2264"
          height="1568"
          alt="Burrito in light mode"
          fetchPriority="high"
          decoding="async"
          className="block w-full select-none"
          draggable={false}
        />

        <div
          aria-hidden="true"
          className={`pointer-events-none absolute inset-0 overflow-hidden transition-[clip-path] ${movementClass}`}
          style={{ clipPath: `inset(0 ${100 - position}% 0 0)` }}
        >
          <img
            src="/burrito-dark.webp"
            srcSet="/burrito-dark-1132.webp 1132w, /burrito-dark.webp 2264w"
            sizes="(max-width: 1150px) calc(100vw - 16px), 1408px"
            width="2264"
            height="1568"
            alt=""
            decoding="async"
            className="block h-full w-full max-w-none select-none object-cover"
            draggable={false}
          />
        </div>

        <div
          aria-hidden="true"
          className={`pointer-events-none absolute inset-y-[4%] z-10 w-px bg-white/75 shadow-[0_0_0_1px_rgb(0_0_0/0.12)] transition-[left] ${movementClass}`}
          style={{ left: `${position}%` }}
        >
          <span className="absolute top-1/2 left-1/2 flex h-9 w-6 -translate-1/2 items-center justify-center rounded-full border border-black/12 bg-white/92 backdrop-blur-sm">
            <i className="h-3 w-px bg-black/25" />
            <i className="ml-1 h-3 w-px bg-black/25" />
          </span>
        </div>

        <input
          type="range"
          min="3"
          max="97"
          value={position}
          onChange={(event) => setPosition(Number(event.target.value))}
          onPointerDown={() => setIsDragging(true)}
          onPointerUp={() => setIsDragging(false)}
          onPointerCancel={() => setIsDragging(false)}
          onBlur={() => setIsDragging(false)}
          aria-label="Compare Burrito dark and light appearance"
          aria-valuetext={`${position}% dark appearance, ${100 - position}% light appearance`}
          className="comparison-range absolute inset-y-0 left-[3%] z-20 m-0 h-full w-[94%] cursor-ew-resize appearance-none bg-transparent opacity-0"
        />
      </div>
      <figcaption className="sr-only">
        Drag the divider to compare Burrito in dark and light appearances.
      </figcaption>
    </figure>
  );
}

function App() {
  const path = window.location.pathname.replace(/\/+$/, "") || "/";

  if (path === "/privacy") {
    return <PrivacyPolicy />;
  }

  if (path === "/terms") {
    return <TermsOfService />;
  }

  return (
    <div className="min-h-screen overflow-hidden bg-canvas text-ink">
      <a
        href="#main"
        className="fixed top-3 left-3 z-50 -translate-y-[150%] bg-ink px-4 py-3 text-canvas transition-transform duration-200 ease-out-expo focus:translate-y-0"
      >
        Skip to content
      </a>

      <SiteNavbar />

      <main id="main">
        <section
          aria-labelledby="hero-title"
          className="pt-[clamp(2.5rem,5vh,4.25rem)] text-center"
        >
          <div className="mx-auto w-[min(calc(100%_-_2rem),78rem)]">
            <h1
              id="hero-title"
              className="reveal mx-auto text-[clamp(3.2rem,6vw,5.9rem)] leading-[0.98] font-semibold tracking-[-0.038em]"
              style={reveal("60ms")}
            >
              <span className="block">The open-source</span>
              <span className="mt-[0.04em] inline-flex max-w-full flex-wrap items-baseline justify-center gap-[0.12em] sm:flex-nowrap sm:whitespace-nowrap">
                <img
                  src="/granola-mark.png"
                  width="240"
                  height="240"
                  alt=""
                  aria-hidden="true"
                  className="relative top-[0.07em] size-[0.72em] rounded-[0.16em]"
                />
                alternative.
              </span>
            </h1>

            <p
              className="reveal mx-auto mt-6 max-w-[44rem] text-[clamp(1rem,1.3vw,1.16rem)] leading-[1.6] text-ink/52 text-balance"
              style={reveal("120ms")}
            >
              Record meetings, transcribe them locally, and turn every conversation
              into useful notes without anything leaving your Mac.
            </p>

            <div
              className="reveal mt-7 flex flex-col items-center justify-center gap-5 sm:flex-row"
              style={reveal("180ms")}
            >
              <a
                href={downloadUrl}
                className="inline-flex min-h-12 w-full items-center justify-center rounded-lg bg-ink px-7 text-sm font-semibold text-canvas transition-opacity duration-150 hover:opacity-75 sm:w-auto"
              >
                Download for macOS
              </a>
              <a
                href={repositoryUrl}
                target="_blank"
                rel="noreferrer"
                className="border-b border-ink/35 pb-1 text-sm font-semibold transition-opacity duration-150 hover:opacity-55"
              >
                Read the source
              </a>
            </div>

            <p
              className="reveal mt-4 text-xs text-ink/35"
              style={reveal("220ms")}
            >
              Free · Apple silicon · macOS 26
            </p>
          </div>

          <AppComparison />
        </section>
      </main>
    </div>
  );
}

export default App;
