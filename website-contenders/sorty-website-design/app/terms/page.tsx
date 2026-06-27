import type { Metadata } from 'next'
import { LegalPage, LegalSection } from '@/components/legal-page'

export const metadata: Metadata = {
  title: 'Terms of Use — Sorty',
  description:
    'The terms that govern your use of Sorty, the free and open source GPL v3 Mac app for organizing folders.',
}

export default function TermsPage() {
  return (
    <LegalPage title="Terms of Use" updated="June 27, 2026">
      <p>
        These terms govern your use of Sorty, a free and open source macOS
        application. By downloading, installing, or using Sorty, you agree to
        these terms. Sorty is provided under the GNU General Public License
        version 3 (GPL v3), and that license governs your rights to use, study,
        modify, and redistribute the software.
      </p>

      <LegalSection heading="1. License">
        <p>
          Sorty is licensed under the{' '}
          <a
            href="https://www.gnu.org/licenses/gpl-3.0.en.html"
            target="_blank"
            rel="noreferrer"
            className="text-primary underline-offset-4 hover:underline"
          >
            GPL v3
          </a>
          . You are free to run the program for any purpose, study how it works,
          modify it, and distribute copies of the original or your modified
          versions, provided you comply with the terms of the GPL v3. The full
          license text ships with the source code.
        </p>
      </LegalSection>

      <LegalSection heading="2. No warranty">
        <p>
          Sorty is provided &quot;as is&quot;, without warranty of any kind,
          express or implied, including but not limited to the warranties of
          merchantability, fitness for a particular purpose, and
          non-infringement. You use Sorty at your own risk.
        </p>
      </LegalSection>

      <LegalSection heading="3. Your responsibility for files">
        <p>
          Sorty moves, renames, and reorganizes files on your behalf. While it
          always shows a preview before applying changes and supports undo, you
          are responsible for maintaining your own backups. We are not liable
          for any loss of, or damage to, your data resulting from your use of
          the software.
        </p>
      </LegalSection>

      <LegalSection heading="4. Third-party AI providers">
        <p>
          When you connect an AI provider, your use of that provider is subject
          to its own terms and pricing. You are responsible for any costs you
          incur with third-party providers and for complying with their usage
          policies. Sorty does not control and is not responsible for the output
          or availability of third-party models.
        </p>
      </LegalSection>

      <LegalSection heading="5. Limitation of liability">
        <p>
          To the maximum extent permitted by law, the maintainers and
          contributors of Sorty shall not be liable for any indirect,
          incidental, special, consequential, or punitive damages, or any loss
          of data or profits, arising out of or related to your use of the
          software.
        </p>
      </LegalSection>

      <LegalSection heading="6. Trademarks">
        <p>
          &quot;Sorty&quot; and the Sorty logo are project marks. The GPL v3
          grants rights to the code, but does not grant permission to use the
          project name or logo in a way that implies endorsement.
          &quot;Mac&quot; and &quot;macOS&quot; are trademarks of Apple Inc.,
          which does not sponsor or endorse Sorty.
        </p>
      </LegalSection>

      <LegalSection heading="7. Changes to these terms">
        <p>
          We may revise these terms over time. The current version is always
          available here and dated above. Continued use of Sorty after changes
          means you accept the revised terms.
        </p>
      </LegalSection>

      <LegalSection heading="8. Contact">
        <p>
          Questions about these terms? Open an issue on our public repository or
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
