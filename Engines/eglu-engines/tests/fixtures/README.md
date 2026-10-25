# Fixtures

Every file here was written by hand for eGlu's tests: no real documents, no
licensed content, nothing to ask anyone's permission for. Regenerate any of
them with the same approach; they only need to hold the feature they test.

- `hello.docx` (1.7 KB): a heading ("Quarterly Report"), a two-item bullet
  list, and a two-row table. Minimal OOXML written by hand: `document.xml`,
  `numbering.xml`, content types and rels.
- `sheets.xlsx` (2 KB): two sheets ("People", "Cities") of inline strings.
- `talk.pptx` (2.5 KB): one slide ("Launch Plan") with a speaker note
  ("Remember to thank the beta testers.").
- `text.pdf` (589 bytes): one page, Helvetica, "Hello PDF world". Minimal
  hand-written PDF 1.4: catalog, pages, page, content stream, font.
- `picture.pdf` (750 bytes): one page holding only a 4x4 RGB image XObject —
  no text, so its page must come back `needsOCR: true`.
