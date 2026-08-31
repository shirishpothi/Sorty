# Planning quality

Use these rules when creating organize, rename-only, or combined plans. The goal is a coherent result that follows the user's language and the evidence in the inventory. Do not force every item into a category.

## Establish the scheme

Start with the user's stated purpose, vocabulary, exclusions, and desired depth. Then inspect the whole inventory before naming folders or files. Prefer categories supported by several items or an existing structure. Reuse the user's established folder names and naming style when they are clear.

Avoid these weak defaults unless the user asks for them:

- one folder per extension;
- generic buckets such as `Misc`, `Other`, or `Documents` that hide useful distinctions;
- deep hierarchies justified by one file;
- categories inferred from a single ambiguous word;
- moving already well-placed items just to make the plan look busy.

Keep uncertain items under `unorganized` with a concrete reason such as `ambiguous project`, `date not verified`, or `insufficient evidence from filename`. Never use `low confidence` without saying what is missing.

## Organize

Group by the purpose a person will search for later, not just by technical type. Project, client, subject, event, workflow stage, and verified time period are usually stronger signals than extension. Use the current parent folder as evidence. Preserve a useful existing hierarchy unless the user asks to replace it.

Check the finished plan for:

- sibling folders at comparable levels of specificity;
- no folder created for a single item unless it represents a durable category;
- no item moved between equivalent folders without a clear gain;
- packages treated as single items;
- every considered item accounted for once.

## Rename

Choose one naming grammar per sibling group, then apply it consistently. Preserve the real extension and its case unless the user explicitly asks to change it. Keep names concise and searchable.

Use only facts supported by the filename, metadata, authorized content analysis, or the user's instructions. Do not invent titles, people, projects, dates, sequence order, or document status. Dates in names must be verified and use one format. Sequence numbers need consistent padding. Preserve meaningful version markers and distinguish drafts from finals only when the evidence does.

Remove noise only when it is clearly noise, such as duplicated separators, camera boilerplate when a verified date or event replaces it, or download suffixes that do not distinguish versions. Do not erase identifiers that may be needed to match a file to an external system.

For case-only renames, include the intended spelling normally. The helper handles them without treating the existing path as an overwrite.

## Organize and rename

Choose the destination category first. Then rename using the grammar for that destination's sibling group. This prevents a file from receiving a generic name before its context is known.

Review combined plans in two passes:

1. Ignore the new basenames and check whether every destination folder is justified.
2. Ignore the folder moves and check whether names are consistent, factual, unique, and extension-safe.

If either pass is weak, keep the item unchanged or list it as unorganized. A combined request does not require both changes for every file.

## Before presenting the plan

Sort operations by destination and then basename so patterns and outliers are visible. Call out any authorized content reads, absolute destinations, extension changes, packages, or cross-volume moves. Run the helper validator. Fix deterministic errors before showing the plan; present judgment calls as warnings instead of hiding them.
