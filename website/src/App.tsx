import { useState, type CSSProperties } from "react";
import {
  FolderSecurityIcon,
  Mic02Icon,
  SourceCodeIcon,
  UserBlock02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { AppleMark } from "./AppleMark";
import { GithubMark } from "./GithubMark";
import { PrivacyPolicy, TermsOfService } from "./LegalPages";
import { downloadUrl, repositoryUrl, SiteNavbar } from "./SiteNavbar";

type RevealStyle = CSSProperties & { "--delay": string; };

function reveal(delay: string): RevealStyle {
  return { "--delay": delay };
}

function AppPreview() {
  return (
    <figure
      className="reveal comparison-shell mx-auto mt-[clamp(2.25rem,5vh,3.75rem)] w-[min(calc(100%_-_1rem),82rem)] sm:w-[min(calc(100%_-_2rem),82rem)]"
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
      </div>
      <figcaption className="sr-only">
        Burrito’s note library in its light appearance.
      </figcaption>
    </figure>
  );
}

const faqs = [
  {
    question: "Does Burrito upload my recordings?",
    answer:
      "No. Burrito is designed to keep recordings, transcripts, and generated notes on your Mac. It does not require a Burrito account or a Burrito-operated cloud service.",
  },
  {
    question: "Which transcription model does Burrito use?",
    answer:
      "Burrito uses a locally installed Parakeet model when one is available and falls back to Apple's on-device transcription frameworks.",
  },
  {
    question: "Can I change how my notes are generated?",
    answer:
      "Yes. Templates are fully editable. You can inspect their prompts, change them, or create a new template for your own workflow.",
  },
  {
    question: "What does Burrito cost?",
    answer:
      "Burrito is free and open source under the MIT license. You can download the app or inspect the complete source on GitHub.",
  },
] as const;

type FaqItemProps = {
  answer: string;
  id: string;
  question: string;
};

function FaqItem({ answer, id, question }: FaqItemProps) {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className={`faq-item${isOpen ? " is-open" : ""}`}>
      <button
        type="button"
        aria-expanded={isOpen}
        aria-controls={id}
        onClick={() => setIsOpen((current) => !current)}
      >
        <span>{question}</span>
        <i aria-hidden="true">+</i>
      </button>
      <div id={id} className="faq-answer">
        <div>
          <p>{answer}</p>
        </div>
      </div>
    </div>
  );
}

function CloudBackdrop({ priority = false }: { priority?: boolean }) {
  return (
    <>
      <picture className="pointer-events-none absolute inset-0 -z-20" aria-hidden="true">
        <source
          srcSet="/cloud-hero-960.webp 960w, /cloud-hero.webp 1920w"
          sizes="100vw"
          type="image/webp"
        />
        <img
          src="/cloud-hero.webp"
          width="1920"
          height="972"
          alt=""
          fetchPriority={priority ? "high" : "auto"}
          decoding="async"
          className="hero-cloud-image h-full w-full object-cover object-top"
        />
      </picture>
      <div className="hero-cloud-wash pointer-events-none absolute inset-0 -z-10" />
    </>
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
          className="hero-section relative isolate overflow-hidden text-center"
        >
          <CloudBackdrop priority />

          <div className="relative z-10 mx-auto w-[min(calc(100%_-_2rem),62rem)]">
            <h1
              id="hero-title"
              className="reveal mx-auto font-display text-[clamp(4rem,7vw,6.5rem)] leading-[1.04] font-normal tracking-[-0.035em]"
              style={reveal("60ms")}
            >
              <span className="block">The open-source</span>
              <span className="mt-[0.12em] inline-flex max-w-full flex-wrap items-baseline justify-center gap-[0.14em] sm:flex-nowrap sm:whitespace-nowrap">
                <img
                  src="/granola-mark.png"
                  width="240"
                  height="240"
                  alt=""
                  aria-hidden="true"
                  className="relative top-[0.06em] size-[0.62em] rounded-[0.16em]"
                />
                <span className="sr-only">Granola</span>
                alternative.
              </span>
            </h1>

            <p
              className="reveal mx-auto mt-7 max-w-[42rem] text-base leading-6 font-normal text-ink/52 text-balance"
              style={reveal("120ms")}
            >
              Record meetings, transcribe them locally, and turn every conversation
              into useful notes without anything leaving your Mac.
            </p>

            <div
              className="reveal mt-7 flex flex-col items-center justify-center gap-3 sm:flex-row"
              style={reveal("180ms")}
            >
              <a
                href={downloadUrl}
                className="primary-action inline-flex min-h-9 w-full items-center justify-center gap-2 rounded-lg bg-action px-4 text-sm font-medium text-white sm:w-auto"
              >
                <AppleMark className="h-4 w-3.5" />
                Download for macOS
              </a>
              <a
                href={repositoryUrl}
                target="_blank"
                rel="noreferrer"
                className="secondary-button inline-flex min-h-9 w-full items-center justify-center rounded-lg border border-ink/12 bg-white/88 px-4 text-sm font-medium text-ink/68 sm:w-auto"
              >
                <GithubMark className="mr-2 size-4" />
                Read the source
              </a>
            </div>

          </div>

          <AppPreview />
        </section>

        <section className="landing-section">
          <div className="statement-copy">
            <h2>
              Most meeting tools treat your conversations as data to upload, process,
              and retain.
            </h2>
            <p>
              Burrito is different. Audio stays on your Mac. Local transcription turns
              it into a searchable record, and on-device intelligence shapes that
              record into notes you can actually use.
            </p>
          </div>
        </section>

        <section id="features" className="landing-section scroll-mt-8">
          <div className="section-heading">
            <p>Features</p>
            <h2>Built to remember the meeting, not collect it.</h2>
            <span>
              One calm workspace for recording, transcription, templates, and useful
              notes.
            </span>
          </div>

          <div className="feature-grid">
            <article className="feature-card feature-card-wide">
              <div className="feature-copy">
                <p className="feature-number">01</p>
                <h3>Record without breaking focus</h3>
                <p>
                  Capture a meeting or a personal note, then let Burrito handle the
                  transcript and structure when you stop.
                </p>
              </div>
              <div className="product-crop" aria-hidden="true">
                <img
                  src="/burrito-light-1132.webp"
                  width="1132"
                  height="784"
                  alt=""
                  loading="lazy"
                  decoding="async"
                />
              </div>
            </article>

            <article className="feature-card">
              <div className="feature-copy">
                <p className="feature-number">02</p>
                <h3>Notes shaped your way</h3>
                <p>
                  Use a focused summary, detailed notes, study notes, or a template you
                  wrote yourself.
                </p>
              </div>
              <div className="template-stack" aria-hidden="true">
                <span>Summary</span>
                <span>Detailed</span>
                <span>Study notes</span>
                <span>Your template</span>
              </div>
            </article>

            <article className="feature-card">
              <div className="feature-copy">
                <p className="feature-number">03</p>
                <h3>Every note keeps its context</h3>
                <p>
                  Revisit the transcript, continue recording, organize with folders,
                  and find anything with Command K.
                </p>
              </div>
              <div className="context-list" aria-hidden="true">
                <span><i />Transcript retained</span>
                <span><i />Recording ready</span>
                <span><i />Template applied</span>
              </div>
            </article>
          </div>
        </section>

        <section className="workflow-section relative isolate overflow-hidden">
          <CloudBackdrop />
          <div className="landing-section relative z-10">
            <div className="section-heading section-heading-left">
              <p>How it works</p>
              <h2>Speak naturally. Burrito does the clerical work.</h2>
              <span>
                From live audio to an organized note without sending the conversation
                through someone else’s server.
              </span>
            </div>

            <div className="workflow-grid">
              <article className="workflow-panel">
                <p className="panel-label">What you do</p>
                <div className="record-orb" aria-hidden="true">
                  <span />
                  <span />
                  <span />
                  <span />
                  <span />
                </div>
                <h3>Press record. Stay in the conversation.</h3>
                <p>Meeting mode captures the room. Note mode captures your thoughts.</p>
              </article>

              <article className="workflow-panel">
                <p className="panel-label">What Burrito does</p>
                <ol className="process-list">
                  <li><span>1</span><div><strong>Transcribes locally</strong><small>Parakeet or Apple transcription</small></div></li>
                  <li><span>2</span><div><strong>Understands the structure</strong><small>Your selected note template</small></div></li>
                  <li><span>3</span><div><strong>Delivers the note</strong><small>Ready inside your library</small></div></li>
                </ol>
              </article>
            </div>

            <div className="capability-row">
              <article><p>Local transcription</p><span>Audio processing happens on your Mac.</span></article>
              <article><p>Editable prompts</p><span>See and change exactly how notes are shaped.</span></article>
              <article><p>Continuous context</p><span>Record more without rebuilding the note from scratch.</span></article>
            </div>
          </div>
        </section>

        <section className="landing-section">
          <div className="section-heading section-heading-left">
            <p>Fits your Mac</p>
            <h2>Native where it matters. Flexible where you want it.</h2>
          </div>

          <div className="system-grid">
            <article>
              <span>01</span>
              <h3>Parakeet ready</h3>
              <p>Use a compatible local Parakeet model when it is installed.</p>
            </article>
            <article>
              <span>02</span>
              <h3>Apple fallback</h3>
              <p>Continue with Apple’s on-device transcription when needed.</p>
            </article>
            <article>
              <span>03</span>
              <h3>System aware</h3>
              <p>Native notifications tell you when recording starts, ends, and notes are ready.</p>
            </article>
            <article>
              <span>04</span>
              <h3>Open source</h3>
              <p>Inspect the code, understand the behavior, and make Burrito yours.</p>
            </article>
          </div>
        </section>

        <section id="privacy" className="privacy-section scroll-mt-8">
          <div className="landing-section">
            <div className="privacy-intro">
              <h2>Privacy that comes from architecture, not promises.</h2>
              <p>
                Burrito is designed around local files, local models, and native Mac
                frameworks. There is no Burrito account and no recording cloud.
              </p>
            </div>

            <div className="privacy-grid">
              <article>
                <HugeiconsIcon
                  icon={Mic02Icon}
                  size={28}
                  strokeWidth={1.35}
                  className="privacy-glyph"
                />
                <h3>On-device transcription</h3>
                <p>Your meeting audio is processed where it was recorded.</p>
              </article>
              <article>
                <HugeiconsIcon
                  icon={FolderSecurityIcon}
                  size={28}
                  strokeWidth={1.35}
                  className="privacy-glyph"
                />
                <h3>Local note library</h3>
                <p>Recordings, transcripts, notes, folders, and templates stay on your Mac.</p>
              </article>
              <article>
                <HugeiconsIcon
                  icon={UserBlock02Icon}
                  size={28}
                  strokeWidth={1.35}
                  className="privacy-glyph"
                />
                <h3>No account required</h3>
                <p>Download the app and use it without creating another identity.</p>
              </article>
              <article>
                <HugeiconsIcon
                  icon={SourceCodeIcon}
                  size={28}
                  strokeWidth={1.35}
                  className="privacy-glyph"
                />
                <h3>Source available</h3>
                <p>Privacy claims are easier to trust when the implementation is public.</p>
              </article>
            </div>

            <div className="privacy-links">
              <a href="/privacy/">Read the privacy policy</a>
              <a href={repositoryUrl} target="_blank" rel="noreferrer">
                <GithubMark className="size-3.5" />
                Inspect the source
              </a>
            </div>
          </div>
        </section>

        <section id="faq" className="landing-section scroll-mt-8">
          <div className="faq-layout">
            <div className="section-heading section-heading-left">
              <p>FAQ</p>
              <h2>Questions, answered plainly.</h2>
            </div>
            <div className="faq-list">
              {faqs.map((faq, index) => (
                <FaqItem
                  key={faq.question}
                  id={`faq-answer-${index + 1}`}
                  question={faq.question}
                  answer={faq.answer}
                />
              ))}
            </div>
          </div>
        </section>

        <section className="closing-section relative isolate overflow-hidden text-center">
          <CloudBackdrop />
          <div className="relative z-10 mx-auto max-w-[42rem] px-4 py-[clamp(6rem,14vw,10rem)]">
            <p className="mb-4 text-[0.68rem] font-semibold tracking-[0.14em] text-ink/50 uppercase">
              Your next meeting can stay yours
            </p>
            <h2 className="font-display text-[clamp(3.3rem,6vw,5.5rem)] leading-[0.92] tracking-[-0.04em]">
              Useful notes, without the recording cloud.
            </h2>
            <a
              href={downloadUrl}
              className="primary-action mt-8 inline-flex min-h-9 items-center justify-center gap-2 rounded-lg bg-action px-4 text-sm font-medium text-white"
            >
              <AppleMark className="h-4 w-3.5" />
              Download for macOS
            </a>
          </div>
          <footer className="relative z-10 mx-auto flex w-[min(calc(100%_-_2rem),82rem)] flex-wrap items-center justify-between gap-4 border-t border-ink/12 py-6 text-xs text-ink/48">
            <span>© 2026 Burrito. Open source under MIT.</span>
            <nav aria-label="Footer navigation" className="flex gap-5">
              <a href="/privacy/">Privacy</a>
              <a href="/terms/">Terms</a>
              <a href={repositoryUrl}>GitHub</a>
            </nav>
          </footer>
        </section>
      </main>
    </div>
  );
}

export default App;
