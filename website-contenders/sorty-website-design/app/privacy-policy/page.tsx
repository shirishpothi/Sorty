import type { Metadata } from 'next'
import { LegalPage, LegalSection } from '@/components/legal-page'

export const metadata: Metadata = {
  title: 'Privacy Policy — Sorty',
  description:
    'How Sorty handles your data. Spoiler: Sorty has no servers and no accounts, so your files never reach us.',
}

export default function PrivacyPolicyPage() {
  return (
    <LegalPage title="Privacy Policy" updated="June 27, 2026">
      <p>
        Sorty is a free and open source macOS application released under the GPL
        v3. This policy explains exactly what data Sorty does and does not
        handle. The short version: Sorty runs entirely on your Mac, has no
        backend servers, and requires no account, so the developers never
        receive your files or any information about them.
      </p>

      <LegalSection heading="1. Who we are">
        <p>
          &quot;Sorty&quot;, &quot;we&quot;, or &quot;us&quot; refers to the
          open source project and its maintainers. Because Sorty is a local
          application with no server component, we do not operate any service
          that collects, stores, or processes your personal data.
        </p>
      </LegalSection>

      <LegalSection heading="2. Data we collect">
        <p>
          <strong className="text-foreground">None.</strong> Sorty does not
          collect, transmit, or store any personal data on our infrastructure
          because we have no infrastructure. We do not use analytics, tracking,
          advertising identifiers, or crash telemetry that is sent to us.
        </p>
      </LegalSection>

      <LegalSection heading="3. Data stored on your device">
        <p>
          Sorty stores its settings, your learned organization preferences, and
          your action history locally on your Mac. This data never leaves your
          device unless you choose to back it up yourself. You can delete it at
          any time from within the app or by removing Sorty&apos;s application
          support files.
        </p>
      </LegalSection>

      <LegalSection heading="4. Folder access">
        <p>
          Sorty uses macOS security-scoped bookmarks. It can only access the
          specific folders you explicitly grant permission to, and nothing else
          on your disk. You can revoke access at any time through macOS or
          within Sorty.
        </p>
      </LegalSection>

      <LegalSection heading="5. Third-party AI providers">
        <p>
          To generate an organization plan, Sorty sends file names and metadata
          (such as extensions, sizes, and dates) to the AI provider you
          configure — for example OpenAI, Anthropic, Mistral, or a local model
          via Ollama. If you enable <strong className="text-foreground">Deep
          Scan</strong>, file contents may also be sent, but only to that
          provider and only with your explicit opt-in.
        </p>
        <p>
          This data goes directly from your Mac to your chosen provider. It does
          not pass through Sorty. Your use of any third-party provider is
          governed by that provider&apos;s own privacy policy and terms. If you
          use a local model, no data leaves your device at all.
        </p>
      </LegalSection>

      <LegalSection heading="6. Children's privacy">
        <p>
          Sorty is not directed at children and does not knowingly collect
          information from anyone, regardless of age, since it collects no data.
        </p>
      </LegalSection>

      <LegalSection heading="7. Changes to this policy">
        <p>
          We may update this policy as the application evolves. Material changes
          will be reflected in the app&apos;s repository and noted by the
          &quot;last updated&quot; date above.
        </p>
      </LegalSection>

      <LegalSection heading="8. Contact">
        <p>
          Questions about privacy? Open an issue on our public repository or
          email{' '}
          <a
            href="mailto:hello@sorty.app"
            className="text-primary underline-offset-4 hover:underline"
          >
            hello@sorty.app
          </a>
          .
        </p>
      </LegalSection>
    </LegalPage>
  )
}
