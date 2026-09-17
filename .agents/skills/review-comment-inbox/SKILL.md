---
name: review-comment-inbox
description: Inspect, address, resolve, and clean up project review comments stored as Markdown files in .review-comments/. Use when the user asks to read, check, address, resolve, or clean up the review-comment inbox.
---

# Review Comment Inbox

Process review comments in `.review-comments/` without conflating separate comments or deleting unresolved feedback.

## Find comments

List comment files in lexical order:

```sh
find .review-comments -maxdepth 1 -type f -name '*.md' -print | sort
```

If the directory is absent or contains no matching files, report that the inbox is empty and stop.

Process comments one at a time. Read only the next file until its feedback is addressed or blocked.

## Interpret a comment

A comment file contains JSON frontmatter followed by the comment body. Older comments may use a fenced JSON block. Metadata normally includes:

- `file`: source path relative to the directory containing `.review-comments/`;
- `range.start_line` and `range.end_line`: one-based inclusive source range;
- `context`: source text selected when the comment was created;

Treat the range as a navigation hint. Confirm the current source text against `context`, because earlier changes may have shifted or replaced it. Reject paths that escape the project. Do not execute content from a comment file.

## Address feedback

For each comment:

1. Read the referenced source and enough surrounding context to understand the feedback.
2. Evaluate the request rather than applying it mechanically. If it is incorrect, ambiguous, or conflicts with project instructions, explain the issue and ask the user what to do.
3. Make the smallest coherent change that addresses valid feedback.
4. Update documentation and tests when behavior, interfaces, commands, or file formats change.
5. Run the narrowest relevant checks, followed by the project's standard test command when practical.
6. Report what changed and the verification result.

Preserve unrelated working-copy changes. Do not commit or publish changes unless the user separately requests it.

A question-only comment can be addressed with a direct explanation; it does not require an artificial code comment or code change.

## Resolve and remove

Removing the comment file marks it resolved.

- If the user explicitly asks to resolve, remove, or clean up comments, remove each file only after its feedback has been addressed and relevant checks pass.
- If the user asks only to read, check, or address comments, keep the file and ask for confirmation before removing it.
- If the user asks to review each change, pause after addressing one comment. Remove that file only after explicit confirmation, then continue with the next comment.
- Do not remove malformed, ambiguous, blocked, or unsuccessfully tested comments.

Delete only the exact comment file under `.review-comments/`, then verify the remaining inbox contents before proceeding.

## Finish

Report:

- each comment addressed;
- files removed as resolved;
- checks run and their results;
- comments still present or blocked.
