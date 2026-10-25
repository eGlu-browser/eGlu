//! eGlu's engines: Harper's linting and anydoc + pdf-inspector's documents,
//! behind a small C interface (`include/eglu_engines.h`). Every call takes and
//! answers JSON as UTF-8 C strings; every answer is `{"ok": …}` or
//! `{"error": {"kind": "…", "message": "…"}}`; a panic answers
//! `{"error":{"kind":"panic"}}` instead of unwinding into the app.

mod documents;
mod harper;
mod json;

use std::ffi::{c_char, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// The linter's handle, made by `eglu_harper_new` and dropped by
/// `eglu_harper_free`.
pub struct EgluHarper(harper::Engine);

/// `settings_json`: `{"dialect":"American","rules":{"SpellCheck":false},"words":["eGlu","Figma"]}`;
/// every field optional. `rules` lists only differences from Harper's
/// defaults; an unknown rule name is ignored. On failure answers null and
/// writes an error envelope to `*error_json` (freed with `eglu_free`).
#[no_mangle]
pub extern "C" fn eglu_harper_new(
    settings_json: *const c_char,
    error_json: *mut *mut c_char,
) -> *mut EgluHarper {
    let built = catch_unwind(AssertUnwindSafe(|| -> Result<*mut EgluHarper, *mut c_char> {
        let settings = unsafe { json::read_str(settings_json) }?;
        match harper::Engine::new(settings) {
            Ok(engine) => Ok(Box::into_raw(Box::new(EgluHarper(engine)))),
            Err(message) => Err(json::error("malformed", message)),
        }
    }));
    let error = match built {
        Ok(Ok(linter)) => return linter,
        Ok(Err(error)) => error,
        Err(_) => json::error("panic", "the engine panicked"),
    };
    if !error_json.is_null() {
        unsafe { *error_json = error }
    }
    std::ptr::null_mut()
}

/// Drops a linter made by `eglu_harper_new`. Null is fine.
#[no_mangle]
pub extern "C" fn eglu_harper_free(linter: *mut EgluHarper) {
    if !linter.is_null() {
        drop(unsafe { Box::from_raw(linter) });
    }
}

/// Same settings shape as `eglu_harper_new`; rebuilds the lint group and the
/// merged dictionary. `{"ok": true}` or an error envelope.
#[no_mangle]
pub extern "C" fn eglu_harper_configure(
    linter: *mut EgluHarper,
    settings_json: *const c_char,
) -> *mut c_char {
    json::guard(|| unsafe {
        let Some(engine) = linter.as_mut() else {
            return json::error("malformed", "a null linter was passed");
        };
        let settings = match json::read_str(settings_json) {
            Ok(settings) => settings,
            Err(error) => return error,
        };
        match engine.0.configure(settings) {
            Ok(()) => json::ok(serde_json::json!(true)),
            Err(message) => json::error("malformed", message),
        }
    })
}

/// Builds the dictionary's search structure and runs one lint, so the first
/// real one is quick. `{"ok": true}` or an error envelope.
#[no_mangle]
pub extern "C" fn eglu_harper_warm_up(linter: *mut EgluHarper) -> *mut c_char {
    json::guard(|| unsafe {
        let Some(engine) = linter.as_mut() else {
            return json::error("malformed", "a null linter was passed");
        };
        match engine.0.warm_up() {
            Ok(answer) => json::ok(answer),
            Err(error) => error,
        }
    })
}

/// Lints `text` ( `"plain"` or `"markdown"` ), answering
/// `{"ok": {"lints": [...]}}` with spans in UTF-16 code units.
#[no_mangle]
pub extern "C" fn eglu_harper_lint(
    linter: *mut EgluHarper,
    text: *const c_char,
    format: *const c_char,
) -> *mut c_char {
    json::guard(|| unsafe {
        let Some(engine) = linter.as_mut() else {
            return json::error("malformed", "a null linter was passed");
        };
        let text = match json::read_str(text) {
            Ok(text) => text,
            Err(error) => return error,
        };
        let format = match json::read_str(format) {
            Ok(format) => format,
            Err(error) => return error,
        };
        match engine.0.lint(text, format) {
            Ok(answer) => json::ok(answer),
            Err(error) => error,
        }
    })
}

/// Hides one lint from now on, by the `context` hex a lint carried.
/// `{"ok": true}` or an error envelope.
#[no_mangle]
pub extern "C" fn eglu_harper_ignore(
    linter: *mut EgluHarper,
    context: *const c_char,
) -> *mut c_char {
    json::guard(|| unsafe {
        let Some(engine) = linter.as_mut() else {
            return json::error("malformed", "a null linter was passed");
        };
        let context = match json::read_str(context) {
            Ok(context) => context,
            Err(error) => return error,
        };
        match engine.0.ignore(context) {
            Ok(()) => json::ok(serde_json::json!(true)),
            Err(message) => json::error("malformed", message),
        }
    })
}

/// Every rule: its group, name, label, description and default, from
/// default_config.json. `{"ok": {"rules": [...]}}`.
#[no_mangle]
pub extern "C" fn eglu_harper_rules() -> *mut c_char {
    json::guard(|| json::ok(harper::rules()))
}

/// `bytes` of a document to `{"ok":{"format":"docx","markdown":"…"}}`.
/// `format` names the format or is "" / null to detect it from the bytes.
#[no_mangle]
pub extern "C" fn eglu_document_markdown(
    bytes: *const u8,
    length: usize,
    format: *const c_char,
) -> *mut c_char {
    json::guard(|| unsafe {
        let bytes = json::read_bytes(bytes, length);
        let format = match optional_str(format) {
            Ok(format) => format,
            Err(error) => return error,
        };
        match documents::markdown(bytes, format) {
            Ok(answer) => json::ok(answer),
            Err(error) => error,
        }
    })
}

/// `{"ok":{"format":"docx"}}` or `{"ok":{"format":null}}` for the unknown.
#[no_mangle]
pub extern "C" fn eglu_document_detect(bytes: *const u8, length: usize) -> *mut c_char {
    json::guard(|| unsafe {
        match documents::detect(json::read_bytes(bytes, length)) {
            Ok(answer) => json::ok(answer),
            Err(error) => error,
        }
    })
}

/// A PDF's pages one by one. `pages_json` is null for every page, or a JSON
/// array of 0-based page numbers. See documents.rs for the answer's shape.
#[no_mangle]
pub extern "C" fn eglu_pdf_pages(
    bytes: *const u8,
    length: usize,
    pages_json: *const c_char,
) -> *mut c_char {
    json::guard(|| unsafe {
        let bytes = json::read_bytes(bytes, length);
        let pages_json = match optional_str(pages_json) {
            Ok(pages_json) => pages_json,
            Err(error) => return error,
        };
        match documents::pdf_pages(bytes, pages_json) {
            Ok(answer) => json::ok(answer),
            Err(error) => error,
        }
    })
}

/// A null `char *` is `None`; a non-UTF-8 one is the malformed error.
unsafe fn optional_str<'a>(ptr: *const c_char) -> Result<Option<&'a str>, *mut c_char> {
    if ptr.is_null() {
        Ok(None)
    } else {
        json::read_str(ptr).map(Some)
    }
}

/// Frees any `char *` the engine answered. Null is fine.
#[no_mangle]
pub extern "C" fn eglu_free(string: *mut c_char) {
    if !string.is_null() {
        drop(unsafe { CString::from_raw(string) });
    }
}

/// Test-only, debug builds only: answers the `panic` error kind, proving a
/// panic stays inside the engine.
#[cfg(debug_assertions)]
#[no_mangle]
pub extern "C" fn eglu_test_panic() -> *mut c_char {
    json::guard(|| panic!("a test panic"))
}
