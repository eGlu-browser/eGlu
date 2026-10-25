/*
 * eglu-engines: Harper's grammar linting and anydoc + pdf-inspector's
 * document conversion behind one small C interface.
 *
 * Every function takes and answers JSON as UTF-8 C strings. Every answer is
 * `{"ok": …}` or `{"error": {"kind": "…", "message": "…"}}`; a panic inside
 * the engine answers `{"error":{"kind":"panic"}}` instead of unwinding.
 *
 * Ownership: every `char *` the engine returns is heap-allocated by Rust and
 * must be freed with `eglu_free`. Strings passed in are borrowed for the
 * duration of the call only. `eglu_harper_new` writes its error into
 * `*error_json`, which is freed with `eglu_free` too.
 *
 * No function makes a network call.
 */

#ifndef EGLU_ENGINES_H
#define EGLU_ENGINES_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The linter's handle: made by eglu_harper_new, dropped by eglu_harper_free.
 * Not thread-safe; the Swift wrapper serializes calls on an actor. */
typedef struct EgluHarper EgluHarper;

/*
 * Makes a linter. `settings_json` looks like
 * {"dialect":"American","rules":{"SpellCheck":false},"words":["eGlu","Figma"]};
 * every field is optional, `rules` lists only differences from Harper's
 * defaults and an unknown rule name is ignored. On failure returns NULL and
 * writes an `{"error":…}` envelope to `*error_json` (free with eglu_free).
 * Quick: it only reads the settings. The dictionary and the rules, a few
 * hundred milliseconds of work, are built by eglu_harper_warm_up or the
 * first lint, on the thread that makes that call.
 */
EgluHarper *eglu_harper_new(const char *settings_json, char **error_json);

/* Drops a linter made by eglu_harper_new. NULL is fine. */
void eglu_harper_free(EgluHarper *linter);

/* Same settings shape as eglu_harper_new; rebuilds the lint group and the
 * merged dictionary. Answers {"ok":true} or an error envelope. */
char *eglu_harper_configure(EgluHarper *linter, const char *settings_json);

/* Builds the dictionary and the rules and runs one lint, so the first real
 * one is quick. Answers {"ok":true} or an error envelope. */
char *eglu_harper_warm_up(EgluHarper *linter);

/*
 * Lints `text` ("plain" or "markdown" format). Answers
 * {"ok":{"lints":[{"start":…,"end":…,"rule":…,"kind":…,"message":…,
 * "priority":…,"suggestions":[{"replace":…}|{"insert":…}|{"remove":true}],
 * "context":"0123456789abcdef"}]}} with spans in UTF-16 code units, sorted by
 * start then priority. `context` feeds eglu_harper_ignore. Over 200,000
 * UTF-16 units of text answers {"error":{"kind":"tooLarge"}}.
 */
char *eglu_harper_lint(EgluHarper *linter, const char *text, const char *format);

/* Hides one lint from now on, by the `context` hex a lint carried.
 * Answers {"ok":true} or an error envelope. */
char *eglu_harper_ignore(EgluHarper *linter, const char *context);

/* Every rule: {"ok":{"rules":[{"id":…,"label":…,"description":…,"group":…,
 * "isOnByDefault":…}]}}. */
char *eglu_harper_rules(void);

/*
 * `bytes` of a document to {"ok":{"format":"docx","markdown":"…"}}.
 * `format` names the format ("docx", "csv", …) or is "" / NULL to detect it
 * from the bytes; CSV has no signature and must always be given. Over 200 MB
 * answers {"error":{"kind":"tooLarge"}} without reading the bytes.
 */
char *eglu_document_markdown(const unsigned char *bytes, size_t length,
                             const char *format);

/* {"ok":{"format":"docx"}} or {"ok":{"format":null}} for the unknown. */
char *eglu_document_detect(const unsigned char *bytes, size_t length);

/*
 * A PDF's pages one by one. `pages_json` is NULL for every page or a JSON
 * array of 0-based page numbers. Answers
 * {"ok":{"pageCount":…,"title":…,"author":…,"created":…,
 * "pages":[{"page":0,"markdown":…,"needsOCR":false,"reason":…}],
 * "withTables":[…],"withColumns":[…]}}; every page number is 0-based.
 */
char *eglu_pdf_pages(const unsigned char *bytes, size_t length,
                     const char *pages_json);

/* Frees any `char *` the engine answered. NULL is fine. */
void eglu_free(char *string);

#ifdef __cplusplus
}
#endif

#endif /* EGLU_ENGINES_H */
