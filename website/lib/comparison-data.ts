export type ComparisonProductId = 'sorty' | 'hazel' | 'folder-tidy' | 'sparkle'

export type ComparisonStatus = 'strong' | 'partial' | 'neutral'

export type ComparisonCell = {
  status: ComparisonStatus
  text: string
}

export type ComparisonProduct = {
  id: ComparisonProductId
  name: string
  logo: string
  logoAlt: string
  url: string
  shortDescription: string
  bestFor: string
}

export type ComparisonRow = {
  feature: string
  explanation: string
  values: Record<ComparisonProductId, ComparisonCell>
}

export const COMPARISON_PRODUCTS: ComparisonProduct[] = [
  {
    id: 'sorty',
    name: 'Sorty',
    logo: '/favicon.png',
    logoAlt: 'Sorty app icon',
    url: 'https://sorty-organizer.github.io/Sorty/',
    shortDescription: 'Review-first AI organization with local and cloud model choices.',
    bestFor: 'People who want semantic organization without surrendering control of each move.',
  },
  {
    id: 'hazel',
    name: 'Hazel',
    logo: '/comparisons/hazel.png',
    logoAlt: 'Hazel app icon',
    url: 'https://www.noodlesoft.com/',
    shortDescription: 'Powerful condition-and-action automation for watched folders.',
    bestFor: 'Power users who want deterministic, always-on rules and broad automation actions.',
  },
  {
    id: 'folder-tidy',
    name: 'Folder Tidy',
    logo: '/comparisons/folder-tidy.png',
    logoAlt: 'Folder Tidy app icon',
    url: 'https://www.tunabellysoftware.com/folder_tidy/',
    shortDescription: 'On-demand folder cleanup with built-in and custom predicate rules.',
    bestFor: 'People who want a focused, rule-based tidy operation with historical undo.',
  },
  {
    id: 'sparkle',
    name: 'Sparkle',
    logo: '/comparisons/sparkle.png',
    logoAlt: 'Sparkle app icon',
    url: 'https://makeitsparkle.co/',
    shortDescription: 'Automatic AI organization with adaptive folders, cleanup, and deduplication.',
    bestFor: 'People who want an always-on organizer that also helps reclaim storage.',
  },
]

export const COMPARISON_ROWS: ComparisonRow[] = [
  {
    feature: 'How files are classified',
    explanation: 'Whether organization comes from semantic AI or rules you define in advance.',
    values: {
      sorty: { status: 'strong', text: 'AI proposes folders from names, metadata, context, and optional Deep Scan.' },
      hazel: { status: 'partial', text: 'User-authored conditions inspect names, dates, contents, metadata, and more.' },
      'folder-tidy': { status: 'partial', text: '22 built-in rules plus custom predicate rules.' },
      sparkle: { status: 'strong', text: 'AI uses file names, types, and supported content to build an adaptive folder structure.' },
    },
  },
  {
    feature: 'Review before files move',
    explanation: 'Whether the app presents the complete proposed organization before applying it.',
    values: {
      sorty: { status: 'strong', text: 'Yes. Review, edit, or reject every proposed move before Apply.' },
      hazel: { status: 'partial', text: 'Preview a rule against an item or inspect rule status; not a full move plan.' },
      'folder-tidy': { status: 'partial', text: 'Configure rules and destinations before a tidy; no item-by-item move plan is documented.' },
      sparkle: { status: 'partial', text: 'You approve the folder structure, then Sparkle automatically sorts new files after a Recents delay.' },
    },
  },
  {
    feature: 'AI processing choice',
    explanation: 'Where AI analysis runs and whether cloud providers are optional.',
    values: {
      sorty: { status: 'strong', text: 'Choose local Ollama or supported Apple models, or a cloud provider.' },
      hazel: { status: 'neutral', text: 'No AI provider required; rules run on the Mac.' },
      'folder-tidy': { status: 'neutral', text: 'No AI provider required; predicates run on the Mac.' },
      sparkle: { status: 'partial', text: 'Sparkle documents encrypted processing and zero content retention, but does not describe a local-model option.' },
    },
  },
  {
    feature: 'Undo and recovery',
    explanation: 'How the app helps reverse organization changes.',
    values: {
      sorty: { status: 'strong', text: 'Organization History records applied runs and supports rollback.' },
      hazel: { status: 'partial', text: 'Revert supported changes per file; some actions cannot be reverted.' },
      'folder-tidy': { status: 'strong', text: 'Immediate and later undo restore files and the original structure.' },
      sparkle: { status: 'strong', text: 'Movement logs show where files went, and Revert restores files to their previous locations.' },
    },
  },
  {
    feature: 'Open source',
    explanation: 'Whether the complete app source is publicly available under an open-source license.',
    values: {
      sorty: { status: 'strong', text: 'Yes. Full source is public under GNU GPL v3.' },
      hazel: { status: 'neutral', text: 'Commercial app; no public source repository is offered.' },
      'folder-tidy': { status: 'neutral', text: 'Commercial app distributed under an end-user license.' },
      sparkle: { status: 'neutral', text: 'Commercial app; no public source repository is linked from the official site.' },
    },
  },
]

export const COMPARISON_SOURCES = [
  {
    label: 'Hazel overview and rules',
    href: 'https://www.noodlesoft.com/manual/hazel/hazel-overview/',
  },
  {
    label: 'Hazel rule preview',
    href: 'https://www.noodlesoft.com/manual/hazel/work-with-folders-rules/create-edit-rules/preview-a-rule/',
  },
  {
    label: 'Hazel file reversion limits',
    href: 'https://www.noodlesoft.com/manual/hazel/work-with-folders-rules/manage-rules/revert-a-file/',
  },
  {
    label: 'Folder Tidy user guide',
    href: 'https://www.tunabellysoftware.com/support/folder_tidy_tutorial/index.php',
  },
  {
    label: 'Folder Tidy release notes',
    href: 'https://www.tunabellysoftware.com/folder_tidy/releasenotes/',
  },
  {
    label: 'Sparkle product page',
    href: 'https://makeitsparkle.co/',
  },
  {
    label: 'Sparkle workflow guide',
    href: 'https://help.makeitsparkle.co/en/articles/13225419-how-sparkle-works',
  },
  {
    label: 'Sorty source and documentation',
    href: 'https://github.com/sorty-organizer/Sorty',
  },
]
