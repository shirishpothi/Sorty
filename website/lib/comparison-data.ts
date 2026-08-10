export type ComparisonProductId = 'sorty' | 'hazel' | 'folder-tidy' | 'declutter'

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
    logo: '/comparisons/hazel.webp',
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
    id: 'declutter',
    name: 'Declutter',
    logo: '/comparisons/declutter.png',
    logoAlt: 'Declutter app icon',
    url: 'https://declutter.pholidlabs.com/',
    shortDescription: 'Automatic, always-on file organization using local AI.',
    bestFor: 'Apple Silicon users who prefer automatic local classification and search.',
  },
]

export const COMPARISON_ROWS: ComparisonRow[] = [
  {
    feature: 'How files are classified',
    explanation: 'Whether organization comes from semantic AI or rules you define in advance.',
    values: {
      sorty: { status: 'strong', text: 'AI proposes folders from names, metadata, context, and optional Deep Scan.' },
      hazel: { status: 'partial', text: 'User-authored conditions inspect names, dates, contents, metadata, and more.' },
      'folder-tidy': { status: 'partial', text: '20 built-in rules plus custom predicate rules.' },
      declutter: { status: 'strong', text: 'Local extension, visual, OCR, and semantic classification.' },
    },
  },
  {
    feature: 'Review before files move',
    explanation: 'Whether the app presents the complete proposed organization before applying it.',
    values: {
      sorty: { status: 'strong', text: 'Yes. Review, edit, or reject every proposed move before Apply.' },
      hazel: { status: 'partial', text: 'Preview a rule against an item or inspect rule status; not a full move plan.' },
      'folder-tidy': { status: 'partial', text: 'Configure rules and destinations before a tidy; no item-by-item move plan is documented.' },
      declutter: { status: 'neutral', text: 'The official workflow describes automatic moves; a review-first plan is not documented.' },
    },
  },
  {
    feature: 'AI processing choice',
    explanation: 'Where AI analysis runs and whether cloud providers are optional.',
    values: {
      sorty: { status: 'strong', text: 'Choose local Ollama or supported Apple models, or a cloud provider.' },
      hazel: { status: 'neutral', text: 'No AI provider required; rules run on the Mac.' },
      'folder-tidy': { status: 'neutral', text: 'No AI provider required; predicates run on the Mac.' },
      declutter: { status: 'strong', text: 'Local AI on Apple Silicon; the official site says file data stays on-device.' },
    },
  },
  {
    feature: 'Automation model',
    explanation: 'Whether organization is manual, optional automation, or always-on monitoring.',
    values: {
      sorty: { status: 'strong', text: 'Run manually, start from Finder, or configure watched folders.' },
      hazel: { status: 'strong', text: 'Continuously watches selected folders and runs matching rules.' },
      'folder-tidy': { status: 'partial', text: 'Run a tidy on a chosen source and destination folder.' },
      declutter: { status: 'strong', text: 'Always-on monitoring automatically classifies and moves new files.' },
    },
  },
  {
    feature: 'Undo and recovery',
    explanation: 'How the app helps reverse organization changes.',
    values: {
      sorty: { status: 'strong', text: 'Organization History records applied runs and supports rollback.' },
      hazel: { status: 'partial', text: 'Revert supported changes per file; some actions cannot be reverted.' },
      'folder-tidy': { status: 'strong', text: 'Immediate and later undo restore files and the original structure.' },
      declutter: { status: 'neutral', text: 'An undo or organization-history workflow is not documented on the official site.' },
    },
  },
  {
    feature: 'Source availability',
    explanation: 'Whether the complete app source is publicly available under an open-source license.',
    values: {
      sorty: { status: 'strong', text: 'Yes. Full source is public under GNU GPL v3.' },
      hazel: { status: 'neutral', text: 'Commercial app; no public source repository is offered.' },
      'folder-tidy': { status: 'neutral', text: 'Commercial app distributed under an end-user license.' },
      declutter: { status: 'neutral', text: 'No public source repository is linked from the official site.' },
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
    label: 'Declutter product page',
    href: 'https://declutter.pholidlabs.com/',
  },
  {
    label: 'Sorty source and documentation',
    href: 'https://github.com/sorty-organizer/Sorty',
  },
]
