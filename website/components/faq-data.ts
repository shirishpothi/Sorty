export const FAQS = [
  {
    q: 'Does Sorty delete my files?',
    a: 'No. Sorty only moves and renames files into folders — it never deletes anything. Nothing happens until you review the plan and click apply.',
  },
  {
    q: 'Can I undo changes?',
    a: 'Yes. Every organization run is recorded in History, and any run can be fully reversed with one click — even days later.',
  },
  {
    q: 'Are my files uploaded anywhere?',
    a: 'Never to us. Sorty has no servers and no accounts, so the developers can never see your files or anything about them. By default only lightweight metadata (file names, types, sizes, dates) is sent to the AI provider you choose. File contents are only ever shared if you turn on Deep Scan, and even then they go straight to your provider. Pick a local model and nothing leaves your Mac at all.',
  },
  {
    q: 'Which AI providers are supported?',
    a: 'Sorty works with major cloud providers like OpenAI, Anthropic, and Mistral, and with local models through Ollama. You bring your own key or run locally — Sorty does not resell AI usage.',
  },
  {
    q: 'What macOS version do I need?',
    a: 'macOS 15 or later, on both Apple Silicon and Intel Macs.',
  },
  {
    q: 'Does it work with external drives, iCloud Drive, or Dropbox?',
    a: 'Yes. Sorty works with any folder you can grant access to, including external drives and synced folders from iCloud Drive and Dropbox.',
  },
  {
    q: 'What happens if I cancel midway?',
    a: 'Applying changes is atomic and resumable. If you stop midway, only the moves already confirmed are kept, and you can undo the entire run from History.',
  },
]
