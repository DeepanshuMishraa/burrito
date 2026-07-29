import { BurritoMark } from "./BurritoMark";

export const repositoryUrl = "https://github.com/DeepanshuMishraa/burrito";
export const downloadUrl = `${repositoryUrl}/releases/latest`;

export function SiteNavbar() {
  return (
    <header>
      <nav
        aria-label="Primary navigation"
        className="mx-auto flex h-20 w-[min(calc(100%_-_1.5rem),82rem)] items-center justify-between sm:h-24 sm:w-[min(calc(100%_-_3rem),82rem)]"
      >
        <a
          href="/"
          aria-label="Burrito home"
          className="flex items-center gap-2.5 text-[1.05rem] font-semibold tracking-[-0.035em]"
        >
          <BurritoMark className="size-8" />
          <span>Burrito</span>
        </a>

        <div className="flex items-center gap-5 text-sm font-medium sm:gap-8">
          <a
            href="/privacy/"
            className="hidden text-ink/50 transition-colors duration-150 hover:text-ink md:block"
          >
            Privacy
          </a>
          <a
            href="/terms/"
            className="hidden text-ink/50 transition-colors duration-150 hover:text-ink md:block"
          >
            Terms
          </a>
          <a
            href={repositoryUrl}
            target="_blank"
            rel="noreferrer"
            className="hidden text-ink/50 transition-colors duration-150 hover:text-ink sm:block"
          >
            GitHub
          </a>
          <a
            href={downloadUrl}
            className="border-b border-ink pb-0.5 transition-opacity duration-150 hover:opacity-55"
          >
            Download
          </a>
        </div>
      </nav>
    </header>
  );
}
