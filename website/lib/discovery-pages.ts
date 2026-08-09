export type DiscoveryPage = {
  slug: string
  eyebrow: string
  title: string
  description: string
  summary: string
  image: string
  imageAlt: string
  keywords: string[]
  steps: { title: string; text: string }[]
  sections: { title: string; paragraphs: string[]; points?: string[] }[]
  faqs: { question: string; answer: string }[]
}

export const DISCOVERY_PAGES: DiscoveryPage[] = [
  {
    slug: 'mac-folder-organizer',
    eyebrow: 'Mac folder organizer',
    title: 'A Mac folder organizer that lets you review the plan first',
    description:
      'Sorty is a free, open-source AI folder organizer for macOS. Organize files by meaning, preview every proposed move, customize the plan, and undo applied changes.',
    summary:
      'Sorty is a native macOS app for people who want AI-assisted file organization without giving up control. It proposes folders and file moves, then waits for approval before changing anything.',
    image: '/sorty-apply.webp',
    imageAlt:
      'Sorty on macOS showing a preview of proposed folders and file moves before the user applies them.',
    keywords: [
      'Mac folder organizer',
      'macOS file organizer',
      'AI file organizer for Mac',
      'automatic file organizer Mac',
      'open source Mac organizer',
    ],
    steps: [
      {
        title: 'Choose any folder',
        text: 'Select a folder in Sorty or start from Finder. Sorty can work with local folders, external drives, iCloud Drive, and Dropbox folders that macOS lets you access.',
      },
      {
        title: 'Generate an organization plan',
        text: 'Your chosen AI provider uses the available file names, types, dates, folder context, and optional Deep Scan information to propose meaningful destinations.',
      },
      {
        title: 'Review, edit, and apply',
        text: 'Inspect every proposed move before it happens. Adjust the plan, apply it when ready, and reverse an organization later from History if needed.',
      },
    ],
    sections: [
      {
        title: 'What makes Sorty different from rule-based file organizers?',
        paragraphs: [
          'Traditional automation depends on rules such as file extensions, dates, or fixed destination names. Sorty can use the context in names and folder structure to group related files even when they have different formats.',
          'The result is still a proposal, not an automatic command. Sorty shows the destination for each file and does not apply the organization until you approve it.',
        ],
      },
      {
        title: 'Built for repeatable Mac workflows',
        paragraphs: [
          'Use the Finder extension to start from a folder, save personas for different kinds of work, or add a watched folder for recurring organization. Sorty also learns from accepted placements and corrections so future suggestions can better match your preferences.',
        ],
        points: [
          'Native SwiftUI app for macOS 15 or later',
          'Works on Apple Silicon and Intel Macs',
          'Finder integration, menu bar access, and watched folders',
          'Organization History with rollback support',
          'Free under the GNU GPL v3, with source code on GitHub',
        ],
      },
      {
        title: 'Privacy depends on the provider you choose',
        paragraphs: [
          'Sorty has no account system and no developer-operated service that receives your folder data. With Ollama or supported Apple on-device models, processing can stay on your Mac. If you choose a cloud provider, relevant metadata—and optional content only when Deep Scan is enabled—goes directly to that provider under its terms.',
        ],
      },
    ],
    faqs: [
      {
        question: 'What is the best use for Sorty?',
        answer:
          'Sorty is best for folders whose files need semantic grouping rather than simple extension-based rules: Downloads, project folders, study materials, creative assets, cloud-synced folders, and external drives.',
      },
      {
        question: 'Does Sorty organize files automatically?',
        answer:
          'A normal organization waits for you to review and apply the plan. Watched folders can automate recurring workflows after you configure their behavior.',
      },
      {
        question: 'Can Sorty undo file organization?',
        answer:
          'Yes. Applied organization runs are recorded in History and can be rolled back later.',
      },
      {
        question: 'Is Sorty free?',
        answer:
          'Yes. Sorty is free and open-source under the GNU GPL v3. Cloud AI providers may charge separately for API usage; local AI avoids provider API charges.',
      },
    ],
  },
  {
    slug: 'organize-downloads-folder',
    eyebrow: 'Organize Downloads on Mac',
    title: 'Turn a messy Downloads folder into a plan you can approve',
    description:
      'Organize your Mac Downloads folder with Sorty. AI groups related files into meaningful folders, shows every proposed move, and lets you undo the result.',
    summary:
      'Sorty can organize a crowded Downloads folder by context instead of relying only on file extensions. You see the proposed folder structure and every move before approving it.',
    image: '/sorty-app.webp',
    imageAlt: 'Sorty ready to organize a selected folder on a Mac.',
    keywords: [
      'organize Downloads folder Mac',
      'clean up Downloads Mac',
      'automatic Downloads organizer',
      'AI Downloads folder organizer',
      'sort files on Mac',
    ],
    steps: [
      {
        title: 'Select Downloads',
        text: 'Choose your Downloads folder in Sorty. macOS asks you to grant folder access, and Sorty stores that permission as a security-scoped bookmark.',
      },
      {
        title: 'Review the suggested groups',
        text: 'Sorty proposes semantic folders such as projects, receipts, installers, documents, or media based on the files that are actually present—not a fixed template.',
      },
      {
        title: 'Apply once or keep it organized',
        text: 'Apply the reviewed plan for a one-time cleanup, or configure Downloads as a watched folder for recurring organization.',
      },
    ],
    sections: [
      {
        title: 'Why AI helps with Downloads',
        paragraphs: [
          'Downloads usually mixes PDFs, screenshots, archives, installers, exports, and project files. Sorting only by extension separates files that belong together. Sorty can use names and surrounding context to propose folders around purpose instead.',
          'No generic category list is forced onto the folder. The generated plan reflects the current files and any custom instructions or persona you provide.',
        ],
      },
      {
        title: 'A safer cleanup workflow',
        paragraphs: [
          'Sorty separates planning from file operations. You can inspect destinations, resolve conflicts, and reject unwanted suggestions before applying the plan. Organization moves or renames files; it does not delete them.',
        ],
        points: [
          'Preview each source and destination',
          'Customize instructions for the current folder',
          'Exclude files and patterns that should stay in place',
          'Reverse an applied run from History',
          'Use a local model when folder metadata should remain on-device',
        ],
      },
      {
        title: 'Use watched folders carefully',
        paragraphs: [
          'After a successful manual run, you can add Downloads to Watched Folders and choose per-folder settings. Start with review-oriented settings until the generated structure consistently matches your preferences, then enable more automation if it fits your workflow.',
        ],
      },
    ],
    faqs: [
      {
        question: 'Can Sorty continuously organize my Downloads folder?',
        answer:
          'Yes. Downloads can be configured as a watched folder, with per-folder behavior for recurring organization.',
      },
      {
        question: 'Will Sorty use the same folders for everyone?',
        answer:
          'No. The plan is generated from the files present, folder context, your instructions, persona, and learned preferences.',
      },
      {
        question: 'Does cleaning Downloads delete files?',
        answer:
          'No. Sorty’s organization workflow moves and renames files into folders; it does not delete them. Duplicate management is a separate feature with its own review and safety controls.',
      },
    ],
  },
  {
    slug: 'local-ai-file-organizer',
    eyebrow: 'Private, local AI organization',
    title: 'Organize files with AI that can stay on your Mac',
    description:
      'Use Sorty with Ollama or supported Apple on-device models for private local AI file organization on macOS. No Sorty account or developer-operated cloud is required.',
    summary:
      'Sorty supports local AI providers for users who do not want folder metadata sent to a cloud model. The same preview-and-approve workflow works with Ollama and supported Apple on-device models.',
    image: '/sorty-settings.webp',
    imageAlt: 'Sorty settings on macOS for configuring an AI provider.',
    keywords: [
      'local AI file organizer',
      'private AI folder organizer Mac',
      'Ollama file organizer',
      'offline file organizer macOS',
      'on-device AI file organization',
    ],
    steps: [
      {
        title: 'Choose a local provider',
        text: 'Connect Sorty to Ollama, or use supported Apple on-device models when your Mac and macOS version meet their requirements.',
      },
      {
        title: 'Select a folder',
        text: 'Sorty scans the folder locally and prepares bounded context for the model. Your folder access remains controlled by macOS permissions.',
      },
      {
        title: 'Approve the local model’s plan',
        text: 'Review the generated structure and individual file moves before applying anything, just as you would with a cloud provider.',
      },
    ],
    sections: [
      {
        title: 'What “local AI” means in Sorty',
        paragraphs: [
          'When Sorty uses Ollama on your Mac or an Apple on-device model, model requests are processed locally rather than being sent to a commercial cloud AI API. Sorty itself has no account requirement and does not operate an intermediary service for file analysis.',
          'Offline availability depends on the provider. Ollama must be installed with an appropriate model available; Apple on-device support depends on compatible hardware, macOS, and Apple Intelligence availability.',
        ],
      },
      {
        title: 'Local and cloud providers remain your choice',
        paragraphs: [
          'Local models provide the strongest data boundary, while cloud models may offer different speed, context, or vision capabilities. Sorty supports both without locking the organization workflow to one vendor.',
        ],
        points: [
          'Local options: Ollama and supported Apple on-device models',
          'Cloud options include OpenAI, Anthropic, Gemini, Groq, OpenRouter, and GitHub Copilot',
          'Custom OpenAI-compatible endpoints are supported',
          'API credentials are stored in the macOS Keychain',
          'Deep Scan is optional and separately controlled',
        ],
      },
      {
        title: 'Know what cloud mode sends',
        paragraphs: [
          'When you select a cloud provider, Sorty sends available folder context and file metadata directly to that provider. Deep Scan can additionally extract supported content locally and send bounded text or metadata summaries. Review the provider’s terms and keep Deep Scan off when names and metadata are sufficient.',
        ],
      },
    ],
    faqs: [
      {
        question: 'Can Sorty organize files completely offline?',
        answer:
          'Yes, when using a functioning local provider such as Ollama or a supported Apple on-device model. Downloads, model installation, and some app services may still require connectivity at other times.',
      },
      {
        question: 'Does Sorty require an account?',
        answer:
          'No. Sorty has no account system. Cloud providers may require their own API key or authentication.',
      },
      {
        question: 'Does Sorty upload file contents by default?',
        answer:
          'No. Deep Scan is optional. With local AI, analysis stays on-device; with a cloud provider, available metadata goes directly to that provider and optional Deep Scan content is only included when enabled.',
      },
    ],
  },
]

export function getDiscoveryPage(slug: string) {
  return DISCOVERY_PAGES.find((page) => page.slug === slug)
}
