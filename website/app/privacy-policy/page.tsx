import type { Metadata } from 'next'
import { LegalPage, LegalSection } from '@/components/legal-page'
import { PageStructuredData } from '@/components/page-structured-data'
import { sitePath } from '@/lib/site-paths'
import { OG_IMAGE_PATH, SITE_URL } from '@/lib/site-metadata'

export const metadata: Metadata = {
  title: 'Privacy Policy',
  description:
    'How Sorty handles your data. Sorty has no servers and no accounts, so your files never reach us. File contents only leave your Mac when you explicitly enable Deep Scan.',
  alternates: { canonical: '/privacy-policy' },
  openGraph: {
    title: 'Privacy Policy — Sorty',
    description:
      'Sorty has no servers and no accounts, so your files never reach us. File contents only leave your Mac when you explicitly enable Deep Scan.',
    url: `${SITE_URL}/privacy-policy`,
    type: 'article',
    images: [
      {
        url: OG_IMAGE_PATH,
        width: 1102,
        height: 754,
        alt: 'Sorty app interface.',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Privacy Policy — Sorty',
    description:
      'Sorty has no servers and no accounts, so your files never reach us. File contents only leave your Mac when you explicitly enable Deep Scan.',
    images: [OG_IMAGE_PATH],
  },
}

const TOC = [
  { id: 'overview', label: 'Overview' },
  { id: 'data-we-collect', label: 'Data We Collect' },
  { id: 'ai-providers', label: 'AI Providers & Your Files' },
  { id: 'local-storage', label: 'Local Storage & Encryption' },
  { id: 'network', label: 'Network & Update Checks' },
  { id: 'sandboxing', label: 'Sandboxing & Permissions' },
  { id: 'third-party', label: 'Third-Party Services' },
  { id: 'children', label: "Children's Privacy" },
  { id: 'your-rights', label: 'Your Rights & Controls' },
  { id: 'changes', label: 'Changes to This Policy' },
  { id: 'contact', label: 'Contact' },
]

export default function PrivacyPolicyPage() {
  return (
    <LegalPage
      title="Privacy Policy"
      updated="June 2026"
      toc={TOC}
      summary={
        <>
          Sorty does not collect telemetry, analytics, or personal data. Your
          files stay on your Mac. When you use a cloud AI provider, only file
          names and metadata are sent for analysis — never file contents unless
          you explicitly enable Deep Scan. Your Learnings profile is encrypted
          with AES-256 and protected by Touch ID or Face ID.
        </>
      }
    >
      <PageStructuredData
        name="Sorty Privacy Policy"
        description="How Sorty handles files, metadata, AI providers, and local storage."
        path="/privacy-policy"
        dateModified="2026-06-01"
        breadcrumbs={[{ name: 'Sorty', path: '/' }, { name: 'Privacy Policy', path: '/privacy-policy' }]}
      />
      <LegalSection id="overview" heading="1. Overview">
        <p>
          Sorty (&quot;the App&quot;) is a native macOS application published by
          the Sorty open-source project and licensed under the{' '}
          <a
            href="https://www.gnu.org/licenses/gpl-3.0.en.html"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            GNU General Public License v3.0
          </a>
          . This Privacy Policy explains how the App handles information when
          you use it.
        </p>
        <p>
          Sorty is built privacy-first. The App runs entirely on your device,
          within the macOS App Sandbox, and is designed so that the smallest
          amount of information necessary leaves your computer — and only when
          you choose a cloud-based AI provider. We do not operate any servers
          that process your files or personal data.
        </p>
      </LegalSection>

      <LegalSection id="data-we-collect" heading="2. Data We Collect">
        <p>
          We do not collect, transmit, or store any telemetry, usage analytics,
          crash reports, or personal data. There is no Sorty account, and we
          have no database of user information.
        </p>
        <p>The following is handled locally on your device only:</p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            <strong className="text-foreground">Organization History</strong> —
            records of operations (file paths and metadata), stored locally and
            not encrypted.
          </li>
          <li>
            <strong className="text-foreground">Settings &amp; preferences</strong>{' '}
            — stored in standard macOS UserDefaults.
          </li>
          <li>
            <strong className="text-foreground">Watched Folders</strong> —
            stored as macOS security-scoped bookmarks so access persists across
            restarts.
          </li>
          <li>
            Exclusion rules, personas, and naming presets you create.
          </li>
        </ul>
      </LegalSection>

      <LegalSection id="ai-providers" heading="3. AI Providers & Your Files">
        <p>
          Sorty is provider-agnostic. You choose which AI provider (if any)
          analyzes your files, and you can switch or disable providers at any
          time in Settings → AI Provider.
        </p>
        <h3 className="pt-1 text-base font-medium text-foreground">
          What is sent to cloud providers
        </h3>
        <p>
          When using a cloud-based provider (for example OpenAI, Anthropic,
          Google Gemini, Groq, OpenRouter, or GitHub Copilot):
        </p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            File names and metadata are sent for analysis so the model can
            suggest a folder structure.
          </li>
          <li>
            File contents are <strong className="text-foreground">NOT</strong>{' '}
            uploaded unless you explicitly enable Deep Scan. Deep Scan uploads
            small content excerpts and should only be enabled for files you are
            comfortable analyzing remotely.
          </li>
          <li>All traffic occurs over HTTPS with TLS 1.2+.</li>
          <li>
            API keys are stored in the macOS Keychain, never logged, and never
            transmitted outside your chosen provider&apos;s endpoints.
          </li>
        </ul>
        <p>
          For maximum privacy, use a fully on-device provider.{' '}
          <a
            href="https://ollama.com"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            Ollama
          </a>{' '}
          processes everything on your machine, and{' '}
          <a
            href="https://developer.apple.com/apple-intelligence/"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            Apple Foundation Models
          </a>{' '}
          run on-device via Apple Intelligence (requires macOS 15+). With these
          options, no file information leaves your Mac.
        </p>
        <p>
          When you use a third-party AI provider, that provider&apos;s own
          privacy policy and terms apply to the data you send. We encourage you
          to review the policies of your chosen provider, for example{' '}
          <a
            href="https://openai.com/policies/privacy-policy"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            OpenAI
          </a>{' '}
          and{' '}
          <a
            href="https://www.anthropic.com/legal/privacy"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            Anthropic
          </a>
          .
        </p>
      </LegalSection>

      <LegalSection id="local-storage" heading="4. Local Storage & Encryption">
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            The Learnings Profile — the data Sorty uses to adapt to your style —
            is stored with{' '}
            <strong className="text-foreground">AES-256 encryption</strong> and
            protected by Touch ID or Face ID.
          </li>
          <li>API keys are stored in the macOS Keychain.</li>
          <li>
            Privacy Mode (enabled by default) blurs sensitive handles until you
            hover and hides API keys behind a manual reveal toggle — useful for
            screensharing or streaming.
          </li>
          <li>
            Privacy Path Masking redacts usernames from file paths shown in the
            UI and logs.
          </li>
        </ul>
      </LegalSection>

      <LegalSection id="network" heading="5. Network & Update Checks">
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            The App checks for updates by fetching version data from the GitHub
            Releases API over HTTPS. Update checks run on app launch (at most
            once per 24 hours) or manually via the menu.
          </li>
          <li>
            No telemetry or analytics are included in these or any other
            requests.
          </li>
          <li>
            You can disable automatic update checks in Settings → Updates →
            Manual only.
          </li>
        </ul>
      </LegalSection>

      <LegalSection id="sandboxing" heading="6. Sandboxing & Permissions">
        <p>
          Sorty runs within the macOS App Sandbox with the following
          entitlements:
        </p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            User-selected file access (read/write) for folders you explicitly
            grant.
          </li>
          <li>Network access for AI provider APIs and update checks.</li>
          <li>No system-level access outside the sandbox.</li>
        </ul>
        <p>
          You grant folder access through macOS security-scoped bookmarks. You
          can revoke access at any time by removing a folder from the Watched
          list or in macOS System Settings.
        </p>
      </LegalSection>

      <LegalSection id="third-party" heading="7. Third-Party Services">
        <p>
          Sorty integrates with the following third-party components and
          services, each governed by their own policies:
        </p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            <a
              href="https://sparkle-project.org"
              target="_blank"
              rel="noreferrer"
              className="text-primary underline-offset-4 hover:underline"
            >
              <strong>Sparkle Framework</strong>
            </a>{' '}
            — handles secure in-app updates.
          </li>
          <li>
            <strong className="text-foreground">AI providers</strong> — each has
            its own security and privacy policy (see above).
          </li>
          <li>
            <a
              href="https://github.com/sorty-organizer/Sorty/releases"
              target="_blank"
              rel="noreferrer"
              className="text-primary underline-offset-4 hover:underline"
            >
              <strong>GitHub</strong>
            </a>{' '}
            — hosts releases and the update feed.
          </li>
        </ul>
        <p>
          Releases are not code-signed with an Apple Developer certificate. You
          may verify integrity by{' '}
          <a
            href="https://github.com/sorty-organizer/Sorty"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            building from source
          </a>{' '}
          or checking release notes. See{' '}
          <a
            href="https://github.com/sorty-organizer/Sorty/blob/main/SECURITY.md"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            SECURITY.md
          </a>{' '}
          for full details.
        </p>
      </LegalSection>

      <LegalSection id="children" heading="8. Children's Privacy">
        <p>
          Sorty is a general-purpose developer and productivity tool and is not
          directed at children under 16. We do not knowingly collect personal
          data from anyone. The App collects no personal data regardless of age.
        </p>
      </LegalSection>

      <LegalSection id="your-rights" heading="9. Your Rights & Controls">
        <p>
          Because Sorty stores everything locally and collects nothing, you are
          always in control:
        </p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li>
            <strong className="text-foreground">Delete your data</strong> — use
            Settings → Troubleshooting → Delete All Data to wipe usage history,
            watched folders, and local caches.
          </li>
          <li>
            <strong className="text-foreground">Reset everything</strong> —
            &quot;Reset All Settings&quot; returns you to the onboarding
            experience.
          </li>
          <li>
            <strong className="text-foreground">Use on-device AI</strong> —
            choose Ollama or Apple Foundation Models to keep processing on your
            Mac.
          </li>
          <li>
            <strong className="text-foreground">Disable Deep Scan</strong> —
            keep file contents from ever leaving your device.
          </li>
          <li>
            <strong className="text-foreground">Disable update checks</strong> —
            minimize network exposure.
          </li>
        </ul>
      </LegalSection>

      <LegalSection id="changes" heading="10. Changes to This Policy">
        <p>
          We may update this Privacy Policy as Sorty evolves. Material changes
          will be reflected in the Changelog and via in-app notifications. The
          &quot;Last updated&quot; date above indicates when this policy was last
          revised.
        </p>
      </LegalSection>

      <LegalSection id="contact" heading="11. Contact">
        <p>
          For privacy or security questions, please use{' '}
          <a
            href="https://github.com/sorty-organizer/Sorty/security/advisories/new"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            GitHub&apos;s private vulnerability reporting
          </a>{' '}
          or open a{' '}
          <a
            href="https://github.com/sorty-organizer/Sorty/discussions"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            GitHub Discussion
          </a>{' '}
          for general questions. For security reports specifically, see{' '}
          <a
            href="https://github.com/sorty-organizer/Sorty/blob/main/SECURITY.md"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            SECURITY.md
          </a>
          .
        </p>
        <p className="pt-2 text-xs text-muted-foreground/80">
          © 2026 Sorty. Released under the GPL-3.0 license.{' '}
          <a href={sitePath('/')} className="underline-offset-4 hover:underline">
            Home
          </a>{' '}
          ·{' '}
          <a href={sitePath('/terms')} className="underline-offset-4 hover:underline">
            Terms
          </a>{' '}
          ·{' '}
          <a
            href="https://github.com/sorty-organizer/Sorty/releases"
            target="_blank"
            rel="noreferrer"
            className="underline-offset-4 hover:underline"
          >
            Changelog
          </a>
        </p>
      </LegalSection>
    </LegalPage>
  )
}
