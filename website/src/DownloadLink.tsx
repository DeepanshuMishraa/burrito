import {
  useEffect,
  useId,
  useRef,
  useState,
  type ComponentPropsWithoutRef,
  type MouseEvent,
} from "react";
import { AppleMark } from "./AppleMark";

const quarantineCommand =
  'sudo xattr -rd com.apple.quarantine "/Applications/Burrito.app"';

type CopyState = "idle" | "copied" | "failed";

type DownloadLinkProps = Omit<ComponentPropsWithoutRef<"a">, "href">;

export function DownloadLink({
  children,
  onClick,
  ...props
}: DownloadLinkProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const descriptionId = useId();
  const [isOpen, setIsOpen] = useState(false);
  const [copyState, setCopyState] = useState<CopyState>("idle");

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) {
      return;
    }

    if (isOpen && !dialog.open) {
      dialog.showModal();
    } else if (!isOpen && dialog.open) {
      dialog.close();
    }
  }, [isOpen]);

  function openDialog(event: MouseEvent<HTMLAnchorElement>) {
    onClick?.(event);
    if (event.defaultPrevented) {
      return;
    }

    event.preventDefault();
    setCopyState("idle");
    setIsOpen(true);
  }

  async function copyCommand() {
    try {
      await navigator.clipboard.writeText(quarantineCommand);
      setCopyState("copied");
    } catch {
      setCopyState("failed");
    }
  }

  return (
    <>
      <a {...props} href={downloadUrl} onClick={openDialog}>
        {children}
      </a>

      <dialog
        ref={dialogRef}
        className="download-dialog"
        aria-labelledby={titleId}
        aria-describedby={descriptionId}
        onCancel={() => setIsOpen(false)}
        onClose={() => setIsOpen(false)}
        onClick={(event) => {
          if (event.target === event.currentTarget) {
            setIsOpen(false);
          }
        }}
      >
        <div className="download-dialog-content">
          <button
            type="button"
            className="download-dialog-close"
            aria-label="Close download instructions"
            onClick={() => setIsOpen(false)}
          >
            ×
          </button>

          <p className="download-dialog-kicker">Before you open Burrito</p>
          <h2 id={titleId}>One macOS step, for now.</h2>
          <p id={descriptionId}>
            Burrito is not notarized yet, so macOS may block the first launch. Move
            Burrito to Applications, then run this command in Terminal.
          </p>

          <div className="download-command">
            <code>{quarantineCommand}</code>
            <button type="button" onClick={copyCommand}>
              {copyState === "copied"
                ? "Copied"
                : copyState === "failed"
                  ? "Select command"
                  : "Copy"}
            </button>
          </div>

          <div className="download-dialog-actions">
            <button type="button" onClick={() => setIsOpen(false)}>
              Cancel
            </button>
            <a href={downloadUrl} download onClick={() => setIsOpen(false)}>
              <AppleMark className="h-4 w-3.5" />
              Download Burrito
            </a>
          </div>
        </div>
      </dialog>
    </>
  );
}

export const downloadUrl =
  "https://github.com/DeepanshuMishraa/burrito/releases/latest/download/Burrito.dmg";
