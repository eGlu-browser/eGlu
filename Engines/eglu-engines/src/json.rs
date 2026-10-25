//! The envelope every C entry point answers: `{"ok": …}` or
//! `{"error": {"kind": "…", "message": "…"}}`, as UTF-8 C strings the caller
//! frees with `eglu_free`.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// A `char *` holding `json`. JSON escapes U+0000, so no answer can carry a
/// real NUL; the defence below only covers a bug of ours, not real input.
pub(crate) fn into_c(json: String) -> *mut c_char {
    CString::new(json).unwrap_or_else(|_| CString::new("{}").unwrap()).into_raw()
}

/// `{"ok": value}`.
pub(crate) fn ok(value: serde_json::Value) -> *mut c_char {
    into_c(serde_json::json!({ "ok": value }).to_string())
}

/// `{"error": {"kind": kind, "message": message}}`. The message is the error's
/// own text, for logs; the app shows its own words for each kind.
pub(crate) fn error(kind: &str, message: impl Into<String>) -> *mut c_char {
    into_c(serde_json::json!({ "error": { "kind": kind, "message": message.into() } }).to_string())
}

/// Runs the entry point, turning a Rust panic into the `panic` error kind
/// rather than letting it unwind into the app.
pub(crate) fn guard(body: impl FnOnce() -> *mut c_char) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(answer) if !answer.is_null() => answer,
        Ok(_) => error("panic", "the engine answered nothing"),
        Err(_) => error("panic", "the engine panicked"),
    }
}

/// A `const char *` argument as `&str`. Null and non-UTF-8 are both answered
/// as `malformed`: the argument itself could not be read.
pub(crate) unsafe fn read_str<'a>(ptr: *const c_char) -> Result<&'a str, *mut c_char> {
    if ptr.is_null() {
        return Err(error("malformed", "a null string was passed to the engine"));
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|_| error("malformed", "a non-UTF-8 string was passed to the engine"))
}

/// Read-only `bytes`/`length` arguments as a slice. Null is an empty slice:
/// the format detectors then answer on their own, never a crash.
pub(crate) unsafe fn read_bytes<'a>(ptr: *const u8, length: usize) -> &'a [u8] {
    if ptr.is_null() || length == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(ptr, length)
    }
}
