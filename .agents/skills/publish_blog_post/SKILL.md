---
name: Format and Publish 0xAkr4m Blog Post
description: Triggers when the user asks to "make and insert a readme file", publish a walkthrough, or format a raw text/README into a new post for the 0xAkr4m blog.
---

When the user provides a raw walkthrough or README to publish to the 0xAkr4m blog, follow these strict instructions:

1. **Frontmatter**: Generate the correct YAML frontmatter required by the Astro site's architecture. The format MUST be:
   ```yaml
   ---
   title: "[Catchy Title]"
   description: "[One-liner description]"
   date: YYYY-MM-DD
   tags: ["tag1", "tag2"]
   authors: ["0xakr4m"]
   image: ../images/headers/vagabond-0[1-6].png
   draft: false
   ---
   ```
   *Note: Select a random number between 1 and 6 for the vagabond header image.*

2. **The Vibe Check (Intro & Outro)**: Rewrite the introduction and conclusion using the 0xAkr4m signature tone: Gen-Z, Reddit-style humor, a bit shitpost-y, but mixed with elite hacker/Miyamoto Musashi energy. It should sound like a highly skilled Red Teamer who doesn't take themselves too seriously.

3. **The Vagabond Rule**: Ensure there is a Musashi quote right under the frontmatter. For example: `> "Perceive that which cannot be seen with the eye." — Miyamoto Musashi, *Vagabond*`

4. **Technical Integrity**: Do not alter any of the actual technical steps, commands, payloads, or code blocks provided by the user. Ensure all code blocks have the correct syntax highlighting tags (e.g., `bash`, `python`, `powershell`, `sql`). Keep the technical explanations clear, but you can sprinkle in a little of the persona where it fits naturally.

5. **The Fingerprint**: Follow the exact structural fingerprint, pacing, and layout of previous blog posts (e.g. Quick Info Card, The Game Plan, The Execution, How to Patch This, Final Thoughts). Match the formatting quirks so this new post blends in perfectly and keeps the overarching site aesthetic cohesive.

6. **Execution**: After generating the content, save the file to `src/content/blog/[post-slug-name]/index.md` inside the workspace.
