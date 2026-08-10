import { useEffect, type ReactNode } from "react";
import { repositoryUrl, SiteNavbar } from "./SiteNavbar";

const siteUrl = "https://burrito.dipxsy.app";
const maintainerEmail = "dipxsy@duck.com";

type LegalPageProps = {
  title: string;
  description: string;
  path: string;
  summary: string;
  effectiveDate?: string;
  children: ReactNode;
};

function usePageMetadata(title: string, description: string, path: string) {
  useEffect(() => {
    document.title = `${title} | Burrito`;

    const descriptionElement = document.querySelector<HTMLMetaElement>(
      'meta[name="description"]',
    );
    descriptionElement?.setAttribute("content", description);

    const canonicalElement =
      document.querySelector<HTMLLinkElement>('link[rel="canonical"]');
    canonicalElement?.setAttribute("href", `${siteUrl}${path}`);

    const openGraphTitle = document.querySelector<HTMLMetaElement>(
      'meta[property="og:title"]',
    );
    openGraphTitle?.setAttribute("content", `${title} | Burrito`);

    const openGraphDescription = document.querySelector<HTMLMetaElement>(
      'meta[property="og:description"]',
    );
    openGraphDescription?.setAttribute("content", description);

    const openGraphUrl = document.querySelector<HTMLMetaElement>(
      'meta[property="og:url"]',
    );
    openGraphUrl?.setAttribute("content", `${siteUrl}${path}`);
  }, [description, path, title]);
}

function LegalPage({
  title,
  description,
  path,
  summary,
  effectiveDate = "July 29, 2026",
  children,
}: LegalPageProps) {
  usePageMetadata(title, description, path);

  return (
    <div className="min-h-screen bg-canvas text-ink">
      <a
        href="#policy"
        className="fixed top-3 left-3 z-50 -translate-y-[150%] bg-ink px-4 py-3 text-canvas transition-transform duration-200 ease-out-expo focus:translate-y-0"
      >
        Skip to document
      </a>

      <SiteNavbar />

      <main id="policy" className="legal-page pb-24">
        <header className="legal-hero">
          <div className="legal-shell">
            <p className="mb-5 text-[0.68rem] font-semibold tracking-[0.14em] text-ink/45 uppercase">
              Burrito · Legal
            </p>
            <h1 className="max-w-[11ch] font-display text-[clamp(4rem,8vw,7rem)] leading-[0.94] font-normal tracking-[-0.04em]">
              {title}
            </h1>
            <div className="legal-hero-summary">
              <p>{summary}</p>
              <span>Effective {effectiveDate}</span>
            </div>
          </div>
        </header>

        <div className="legal-shell legal-layout">
          <aside className="h-fit text-sm leading-6 text-ink/45 lg:sticky lg:top-8">
            <p className="mb-4 text-[0.67rem] font-semibold tracking-[0.12em] text-ink/35 uppercase">
              About this document
            </p>
            <p>
              Burrito is an open-source, local-first macOS application maintained
              through its public GitHub repository.
            </p>
            <a
              href={`mailto:${maintainerEmail}`}
              className="mt-4 inline-block border-b border-ink/30 pb-0.5 font-medium text-ink"
            >
              Contact the maintainer
            </a>
          </aside>

          <article className="legal-copy max-w-[46rem]">{children}</article>
        </div>

        <div className="legal-shell">
          <aside className="mt-16 border-t border-ink/15 pt-7 text-sm leading-6 text-ink/45">
            This document is provided for transparency and should be reviewed by
            qualified counsel before a public release. Jurisdiction-specific clauses,
            liability limits, and regulatory obligations require legal review.
          </aside>

          <footer className="mt-16 flex flex-wrap gap-6 border-t border-ink/15 pt-7 text-sm">
            <a href="/">Home</a>
            <a href="/privacy/">Privacy</a>
            <a href="/terms/">Terms</a>
            <a href={repositoryUrl}>GitHub</a>
          </footer>
        </div>
      </main>
    </div>
  );
}

export function PrivacyPolicy() {
  return (
    <LegalPage
      title="Privacy Policy"
      path="/privacy/"
      description="Learn how Burrito keeps meeting data local by default and how optional Supermemory cloud search processes app data."
      summary="Burrito keeps meeting data on your Mac by default. Connecting a Supermemory API key validates the account; meeting titles and transcripts are sent only after you separately choose Index meetings."
      effectiveDate="August 10, 2026"
    >
      <section>
        <h2>1. The short version</h2>
        <p>
          Burrito processes meeting audio and creates notes locally on your Mac. The
          app does not require an account and does not upload your recordings,
          transcripts, generated notes, templates, or folders to a Burrito-operated
          server by default. Burrito does not sell personal information. The optional
          Supermemory Cloud Search feature sends meeting titles and transcripts to
          Supermemory only after you connect your own API key and separately choose
          Index meetings in Settings.
        </p>
      </section>

      <section>
        <h2>2. Information handled by the app</h2>
        <p>
          Depending on the features you use, Burrito may handle system audio,
          microphone audio, speech transcripts, generated notes, custom templates,
          folder names, Calendar event details, and app preferences. This information
          is stored and processed on your Mac by default. When Supermemory Cloud Search
          is connected and you choose Index meetings, non-deleted meeting titles and
          transcripts are also stored and processed by Supermemory under its own terms
          and privacy policy.
        </p>
        <p>
          Burrito uses macOS permissions for screen and system-audio capture,
          microphone access in Meeting mode, speech recognition, Calendar access, and
          notifications. You control these permissions in System Settings.
        </p>
      </section>

      <section>
        <h2>3. Local transcription and note generation</h2>
        <p>
          Transcription uses Apple Speech or an optional locally installed Parakeet
          model. Note generation uses Apple Intelligence through Apple’s on-device
          Foundation Models framework. Burrito never sends source audio to
          Supermemory. Transcript uploads occur only when you explicitly click Index
          meetings after connecting Supermemory Cloud Search.
        </p>
        <p>
          If you install a Parakeet model, the model files are downloaded from their
          published model source and then used locally. Download providers may receive
          standard network information such as your IP address under their own
          privacy policies; your recordings and notes are not included in that
          request.
        </p>
      </section>

      <section>
        <h2>4. Optional Supermemory Cloud Search</h2>
        <p>
          You may connect a Supermemory API key to improve meeting retrieval beyond
          Burrito’s local keyword search. Connecting validates and stores the key but
          does not upload meeting content. When you separately click Index meetings,
          Burrito uploads every existing non-deleted meeting title and transcript to
          your Supermemory account and automatically keeps future changes indexed.
          Burrito stores the API key in macOS Keychain and uses it only to validate,
          index, search, update, and delete Burrito meeting documents.
        </p>
        <p>
          Supermemory receives and processes uploaded content, account information,
          network metadata, and API usage under its own privacy policy. Usage is billed
          by Supermemory to your account. Disconnecting removes the API key from this
          Mac but does not itself delete previously uploaded data. The app provides a
          separate action to request deletion of Burrito’s uploaded documents before
          disconnecting. If Supermemory is unavailable or disconnected, Burrito falls
          back to local keyword search.
        </p>
      </section>

      <section>
        <h2>5. Storage and retention</h2>
        <p>
          Notes, transcripts, settings, and retained recordings live in Burrito’s
          local Application Support data. Audio is removed after successful
          transcription by default. If you enable Keep Audio, or if a recording is
          interrupted or fails, audio may remain locally so you can recover it.
        </p>
        <p>
          You can edit or delete notes in the app, empty Trash, remove retained audio,
          uninstall downloaded models, or remove Burrito’s local application data
          through macOS. Deleting a local meeting causes Burrito to request deletion
          of its indexed Supermemory document while the integration remains connected.
        </p>
      </section>

      <section>
        <h2>6. Website data</h2>
        <p>
          The Burrito website does not intentionally set cookies, run analytics,
          display advertising, fingerprint visitors, or include marketing trackers.
          It does not contain account, payment, newsletter, or contact forms.
        </p>
        <p>
          The website’s hosting provider may process ordinary web-server information,
          such as IP address, browser type, requested URL, and request time, to deliver
          and secure the site. The provider’s own privacy terms govern that processing.
        </p>
        <p>
          The website loads the Inter typeface from Google Fonts. When your browser
          requests the font files, Google may receive standard network information,
          including your IP address and browser details, under Google’s own privacy
          terms.
        </p>
      </section>

      <section>
        <h2>7. Sharing and disclosure</h2>
        <p>
          Burrito does not sell, rent, or trade personal information. Because app data
          is not collected by a Burrito server, there is ordinarily no app content for
          the project maintainers to disclose. If you enable Supermemory Cloud Search,
          meeting titles and transcripts are disclosed to Supermemory at your direction.
          Information may also be accessible to anyone who can access your Mac, your
          backups, your Supermemory account, or files you choose to export and share.
        </p>
      </section>

      <section>
        <h2>8. Security</h2>
        <p>
          Burrito relies on macOS application storage, permission controls, and your
          device security. Keep macOS updated, use a strong login password, and protect
          your backups. No software or storage method can guarantee absolute security.
        </p>
      </section>

      <section>
        <h2>9. Your choices and rights</h2>
        <p>
          Because Burrito does not maintain user accounts or a remote database, you
          directly control most relevant data on your Mac. Depending on where you live,
          privacy law may also provide rights of access, correction, deletion,
          restriction, portability, objection, or complaint to a regulator. The exact
          application of these rights requires jurisdiction-specific legal review.
        </p>
      </section>

      <section>
        <h2>10. Children</h2>
        <p>
          Burrito is a general-purpose productivity tool and is not directed to
          children under 13. The project does not knowingly collect children’s
          personal information through an account or online service.
        </p>
      </section>

      <section>
        <h2>11. Changes and contact</h2>
        <p>
          Material changes will be reflected by updating this page and its effective
          date. For privacy questions, email{" "}
          <a href={`mailto:${maintainerEmail}`}>{maintainerEmail}</a>. Do not send
          private recordings, transcripts, credentials, or other sensitive
          information unless it is necessary to resolve your request.
        </p>
      </section>
    </LegalPage>
  );
}

export function TermsOfService() {
  return (
    <LegalPage
      title="Terms of Service"
      path="/terms/"
      description="Read the terms governing use of Burrito, an open-source local meeting transcription and note-taking application for macOS."
      summary="These terms explain the conditions for using Burrito, including recording consent, AI-generated output, open-source licensing, and warranty limitations."
    >
      <section>
        <h2>1. Agreement</h2>
        <p>
          By downloading, installing, or using Burrito, you agree to these terms. If
          you do not agree, do not use the software. These terms apply to the Burrito
          application and project website; third-party software and services have
          their own terms.
        </p>
      </section>

      <section>
        <h2>2. Open-source license</h2>
        <p>
          Burrito’s source code is provided under the MIT License. The MIT License
          governs your rights to use, copy, modify, merge, publish, distribute,
          sublicense, or sell copies of the software. These terms do not restrict
          rights granted by that license.
        </p>
      </section>

      <section>
        <h2>3. Requirements and permissions</h2>
        <p>
          Burrito requires a compatible Apple-silicon Mac, supported macOS version,
          and relevant system features. Some functions require screen and audio
          capture, microphone, speech recognition, Calendar, or notification
          permissions. You can revoke permissions in System Settings, but related
          features may stop working.
        </p>
      </section>

      <section>
        <h2>4. Your responsibility when recording</h2>
        <p>
          Recording laws differ by location and context. You are responsible for
          obtaining every consent and authorization required before recording,
          transcribing, storing, or sharing a conversation. Do not use Burrito to
          intercept communications unlawfully or violate another person’s privacy,
          confidentiality, intellectual-property, employment, or contractual rights.
        </p>
      </section>

      <section>
        <h2>5. Generated content</h2>
        <p>
          Transcriptions and AI-generated notes may be incomplete, inaccurate, or
          misleading. Review important names, dates, decisions, quotations, and action
          items against the original source before relying on them. Burrito is not a
          substitute for professional legal, medical, financial, safety, or compliance
          advice.
        </p>
      </section>

      <section>
        <h2>6. Your content</h2>
        <p>
          You retain responsibility for recordings, transcripts, notes, templates,
          and files you create or import. Burrito’s maintainers do not claim ownership
          of that content. You are responsible for securing your Mac, backups, and
          exported files and for deciding how long to keep them.
        </p>
      </section>

      <section>
        <h2>7. Third-party components</h2>
        <p>
          Burrito may use open-source libraries, Apple frameworks, and optional model
          files supplied by third parties. Their licenses and terms continue to apply.
          External websites linked from the project are controlled by their respective
          operators.
        </p>
      </section>

      <section>
        <h2>8. Availability and changes</h2>
        <p>
          The project may change, suspend, or discontinue features at any time. There
          is no promise that Burrito will remain compatible with every macOS release,
          model, language, device, or third-party component.
        </p>
      </section>

      <section>
        <h2>9. Disclaimer of warranties</h2>
        <p>
          To the fullest extent permitted by law, Burrito is provided “as is” and
          “as available,” without warranties of any kind, express or implied. This
          includes implied warranties of merchantability, fitness for a particular
          purpose, title, non-infringement, accuracy, and uninterrupted operation.
          Consumer-law limitations and jurisdiction-specific wording require legal
          review.
        </p>
      </section>

      <section>
        <h2>10. Limitation of liability</h2>
        <p>
          To the fullest extent permitted by law, the project maintainers and
          contributors will not be liable for indirect, incidental, special,
          consequential, exemplary, or punitive damages, or for lost data, recordings,
          profits, business, or opportunities arising from use of Burrito. The scope
          and enforceability of this limitation require jurisdiction-specific legal
          review.
        </p>
      </section>

      <section>
        <h2>11. Ending use</h2>
        <p>
          You may stop using Burrito at any time by uninstalling it and removing local
          data and downloaded models. Provisions that logically continue after use
          ends—including license, warranty, and liability provisions—survive.
        </p>
      </section>

      <section>
        <h2>12. Governing law and disputes</h2>
        <p>
          No governing jurisdiction or dispute forum is stated in this draft. Those
          clauses should be completed by qualified counsel based on the project
          maintainer’s legal location and intended distribution.
        </p>
      </section>

      <section>
        <h2>13. Changes and contact</h2>
        <p>
          Changes will be posted on this page with an updated effective date.
          Questions may be emailed to{" "}
          <a href={`mailto:${maintainerEmail}`}>{maintainerEmail}</a>. Do not send
          confidential or sensitive information unless it is necessary to resolve
          your request.
        </p>
      </section>
    </LegalPage>
  );
}
