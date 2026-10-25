//! The Harper calls through their C signatures, envelopes included.

use std::ffi::{c_char, CString};

use eglu_engines::{
    eglu_harper_configure, eglu_harper_free, eglu_harper_ignore, eglu_harper_lint,
    eglu_harper_new, eglu_harper_rules, eglu_harper_warm_up, EgluHarper,
};
use serde_json::{json, Value};

fn c(text: &str) -> CString {
    CString::new(text).unwrap()
}

fn answer(ptr: *mut c_char) -> Value {
    assert!(!ptr.is_null(), "the engine answered a null string");
    let text = unsafe { CString::from_raw(ptr) }.into_string().unwrap();
    serde_json::from_str(&text).unwrap()
}

fn linter(settings: &str) -> *mut EgluHarper {
    let mut error: *mut c_char = std::ptr::null_mut();
    let linter = eglu_harper_new(c(settings).as_ptr(), &mut error);
    if linter.is_null() {
        panic!("eglu_harper_new failed: {}", answer(error));
    }
    linter
}

fn lint(linter: *mut EgluHarper, text: &str) -> Vec<Value> {
    let answer = answer(eglu_harper_lint(
        linter,
        c(text).as_ptr(),
        c("plain").as_ptr(),
    ));
    assert!(answer.get("ok").is_some(), "lint failed: {answer}");
    answer["ok"]["lints"].as_array().unwrap().clone()
}

#[test]
fn a_bad_sentence_gives_lints_with_suggestions() {
    let linter = linter("{}");
    let lints = lint(linter, "I has a apple.");
    let rules: Vec<&str> = lints.iter().map(|l| l["rule"].as_str().unwrap()).collect();
    assert!(
        rules.iter().any(|r| r.contains("Agreement")),
        "expected an agreement lint, got {rules:?}"
    );
    assert!(
        lints.iter().any(|l| !l["suggestions"].as_array().unwrap().is_empty()),
        "expected a lint with suggestions, got {lints:?}"
    );
    eglu_harper_free(linter);
}

/// The settings are read in eglu_harper_new, though the linter is built
/// later: a bad one fails there, not at the first lint.
#[test]
fn an_unknown_dialect_fails_at_once() {
    let mut error: *mut c_char = std::ptr::null_mut();
    let linter = eglu_harper_new(c(r#"{"dialect":"Martian"}"#).as_ptr(), &mut error);
    assert!(linter.is_null());
    assert_eq!(answer(error)["error"]["kind"], "malformed");
}

/// A caller may pass no place for the error; the failure is still null.
#[test]
fn a_failure_without_an_error_pointer_is_null() {
    let linter = eglu_harper_new(c(r#"{"dialect":"Martian"}"#).as_ptr(), std::ptr::null_mut());
    assert!(linter.is_null());
}

/// "lakh" is Indian English only: a spelling and a regionalism lint in
/// American, none in Indian.
#[test]
fn the_indian_dialect_takes_its_own_words() {
    let american = linter(r#"{"dialect":"American"}"#);
    let indian = linter(r#"{"dialect":"Indian"}"#);
    let text = "It cost one lakh rupees.";
    assert!(!lint(american, text).is_empty(), "American took \"lakh\"");
    let lints = lint(indian, text);
    assert!(lints.is_empty(), "Indian flagged: {lints:?}");
    eglu_harper_free(american);
    eglu_harper_free(indian);
}

#[test]
fn an_off_rule_gives_nothing() {
    let linter = linter(r#"{"rules":{"SpellCheck":false}}"#);
    let lints = lint(linter, "I havv teh answer.");
    assert!(
        lints.iter().all(|l| l["rule"] != "SpellCheck"),
        "SpellCheck fired while off: {lints:?}"
    );
    eglu_harper_free(linter);
}

#[test]
fn a_dictionary_word_stops_being_a_lint() {
    let linter = linter("{}");
    let before = lint(linter, "Safience works.");
    assert!(
        before.iter().any(|l| l["rule"] == "SpellCheck"),
        "expected Safience to be flagged, got {before:?}"
    );
    let configured = answer(eglu_harper_configure(
        linter,
        c(r#"{"words":["Safience"]}"#).as_ptr(),
    ));
    assert_eq!(configured, json!({"ok": true}));
    let after = lint(linter, "Safience works.");
    assert!(
        after.iter().all(|l| l["rule"] != "SpellCheck"),
        "Safience still flagged: {after:?}"
    );
    eglu_harper_free(linter);
}

#[test]
fn an_ignored_context_stays_ignored() {
    let linter = linter("{}");
    let lints = lint(linter, "I has a apple.");
    let context = lints[0]["context"].as_str().unwrap().to_owned();
    drop(lints);
    assert_eq!(context.len(), 16, "context is a 16-hex u64: {context}");
    u64::from_str_radix(&context, 16).expect("context is hex");
    let ignored = answer(eglu_harper_ignore(linter, c(&context).as_ptr()));
    assert_eq!(ignored, json!({"ok": true}));
    let after = lint(linter, "I has a apple.");
    assert!(
        after.iter().all(|l| l["context"] != context),
        "the ignored lint came back: {after:?}"
    );
    eglu_harper_free(linter);
}

#[test]
fn rules_lists_groups_labels_and_defaults() {
    let envelope = answer(eglu_harper_rules());
    let rules = envelope["ok"]["rules"].as_array().unwrap();
    assert!(rules.len() > 50, "expected Harper's rule set, got {}", rules.len());
    let spell = rules.iter().find(|r| r["id"] == "SpellCheck").unwrap();
    for key in ["label", "description", "group", "isOnByDefault"] {
        assert!(spell.get(key).is_some(), "SpellCheck lacks {key}: {spell}");
    }
    assert!(
        rules.iter().any(|r| r["id"] == "OxfordComma"),
        "rules lacks OxfordComma"
    );
}

#[test]
fn spans_count_utf16_units() {
    let linter = linter("{}");
    // "😀 teh": the emoji is a surrogate pair (2 UTF-16 units) plus a space, so
    // "teh" starts at UTF-16 index 3 — the index Swift's NSString gives.
    let lints = lint(linter, "\u{1F600} teh");
    assert!(
        lints.iter().any(|l| l["start"] == 3 && l["end"] == 6),
        "no lint over \"teh\" at 3..6: {lints:?}"
    );

    // "한국어 teh": three BMP scalars are 3 UTF-16 units, plus the space.
    let lints = lint(linter, "한국어 teh");
    assert!(
        lints.iter().any(|l| l["start"] == 4 && l["end"] == 7),
        "no lint over \"teh\" at 4..7: {lints:?}"
    );
    eglu_harper_free(linter);
}

#[test]
fn many_lints_in_a_long_text_keep_their_utf16_spans() {
    let linter = linter("{}");
    // 2,000 misspellings, each after an emoji: "😀 teh " is 7 UTF-16 units
    // (2 + 1 + 3 + 1), so the k-th "teh" starts at 7k + 3.
    let text = "\u{1F600} teh ".repeat(2_000);
    let lints = lint(linter, &text);
    let spans: std::collections::HashSet<(u64, u64)> = lints
        .iter()
        .filter_map(|l| Some((l["start"].as_u64()?, l["end"].as_u64()?)))
        .collect();
    for k in 0..2_000u64 {
        let start = 7 * k + 3;
        assert!(
            spans.contains(&(start, start + 3)),
            "no lint over the {k}th \"teh\" at {start}..{}",
            start + 3
        );
    }
    eglu_harper_free(linter);
}

#[test]
fn too_much_text_answers_too_large() {
    let linter = linter("{}");
    let big = "a".repeat(200_001);
    let answer = answer(eglu_harper_lint(linter, c(&big).as_ptr(), c("plain").as_ptr()));
    assert_eq!(answer["error"]["kind"], "tooLarge");
    eglu_harper_free(linter);
}

#[test]
fn warm_up_and_markdown_lint() {
    let linter = linter("{}");
    let warmed = answer(eglu_harper_warm_up(linter));
    assert_eq!(warmed, json!({"ok": true}));
    let answer = answer(eglu_harper_lint(
        linter,
        c("# A Titel\n\nSome text.").as_ptr(),
        c("markdown").as_ptr(),
    ));
    assert!(answer.get("ok").is_some(), "markdown lint failed: {answer}");
    eglu_harper_free(linter);
}

#[test]
fn a_panic_answers_the_panic_kind() {
    let answer = answer(eglu_engines::eglu_test_panic());
    assert_eq!(answer["error"]["kind"], "panic");
}
