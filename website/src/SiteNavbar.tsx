import { AppleMark } from "./AppleMark";
import { BurritoMark } from "./BurritoMark";
import { GithubMark } from "./GithubMark";

export const repositoryUrl = "https://github.com/DeepanshuMishraa/burrito";
export const downloadUrl = `${repositoryUrl}/releases/latest`;

export function SiteNavbar() {
  return (
    <header className="relative z-30">
      <nav
        aria-label="Primary navigation"
        className="mx-auto grid h-[3.625rem] w-[min(calc(100%_-_1.5rem),72rem)] grid-cols-[1fr_auto_1fr] items-center sm:w-[min(calc(100%_-_3rem),72rem)]"
      >
        <a
          href="/"
          aria-label="Burrito home"
          className="brand-link col-start-1 flex items-center gap-2 text-[0.84rem] font-semibold tracking-[-0.025em]"
        >
          <BurritoMark className="brand-mark size-6" />
          <span>Burrito</span>
        </a>

        <div className="col-start-2 hidden items-center gap-7 text-[0.78rem] font-normal md:flex">
          <a
            href="/#features"
            className="nav-link text-ink/72"
          >
            Features
          </a>
          <a
            href="/#privacy"
            className="nav-link text-ink/72"
          >
            Privacy
          </a>
          <a
            href="/#faq"
            className="nav-link text-ink/72"
          >
            FAQ
          </a>
        </div>

        <div className="col-start-3 flex items-center justify-end gap-2 text-[0.78rem] font-medium">
          <a
            href={repositoryUrl}
            target="_blank"
            rel="noreferrer"
            data-cuelume-hover="whisper"
            data-cuelume-toggle="sparkle"
            className="nav-secondary hidden min-h-8 items-center rounded-lg border border-ink/12 bg-white/82 px-3 text-ink/65 sm:inline-flex"
          >
            <GithubMark className="mr-1.5 size-3.5" />
            GitHub
          </a>
          <a
            href={downloadUrl}
            data-cuelume-hover="whisper"
            data-cuelume-toggle="sparkle"
            className="nav-download inline-flex min-h-8 items-center gap-1.5 rounded-lg bg-action px-3 text-white"
          >
            <AppleMark className="h-3.5 w-3" />
            Download
          </a>
        </div>
      </nav>
    </header>
  );
}
