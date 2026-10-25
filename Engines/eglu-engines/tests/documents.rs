//! The document calls through their C signatures, against tests/fixtures.

use std::ffi::{c_char, CString};

use eglu_engines::{
    eglu_document_detect, eglu_document_markdown, eglu_pdf_pages,
};
use serde_json::Value;

fn c(text: &str) -> CString {
    CString::new(text).unwrap()
}

fn answer(ptr: *mut c_char) -> Value {
    assert!(!ptr.is_null(), "the engine answered a null string");
    let text = unsafe { CString::from_raw(ptr) }.into_string().unwrap();
    serde_json::from_str(&text).unwrap()
}

fn fixture(name: &str) -> Vec<u8> {
    std::fs::read(format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"))).unwrap()
}

fn markdown(bytes: &[u8], format: Option<&str>) -> Value {
    let format = format.map(|f| c(f));
    answer(eglu_document_markdown(
        bytes.as_ptr(),
        bytes.len(),
        format.as_ref().map_or(std::ptr::null(), |f| f.as_ptr()),
    ))
}

#[test]
fn docx_heading_list_and_table_become_markdown() {
    let bytes = fixture("hello.docx");
    let answer = markdown(&bytes, None);
    assert_eq!(answer["ok"]["format"], "docx", "{answer}");
    let md = answer["ok"]["markdown"].as_str().unwrap();
    assert!(md.contains("Quarterly Report"), "{md}");
    assert!(md.contains("First item") && md.contains("Second item"), "{md}");
    assert!(md.contains("Ada") && md.contains("42"), "{md}");
}

#[test]
fn xlsx_keeps_both_sheets() {
    let bytes = fixture("sheets.xlsx");
    let answer = markdown(&bytes, Some("xlsx"));
    let md = answer["ok"]["markdown"].as_str().unwrap();
    assert!(md.contains("Grace"), "{md}");
    assert!(md.contains("Seoul"), "{md}");
}

#[test]
fn pptx_keeps_the_speaker_notes() {
    let bytes = fixture("talk.pptx");
    let answer = markdown(&bytes, None);
    assert_eq!(answer["ok"]["format"], "pptx", "{answer}");
    let md = answer["ok"]["markdown"].as_str().unwrap();
    assert!(md.contains("Launch Plan"), "{md}");
    assert!(md.contains("beta testers"), "{md}");
}

/// Each fixture by the name its format is detected as, the name Swift's
/// `DocumentFormat` sends back: a name anydoc doesn't know ("excel") would
/// fail every file of that format.
#[test]
fn each_fixture_converts_by_its_detected_name() {
    for (file, name, words) in [
        ("hello.docx", "docx", "Quarterly Report"),
        ("talk.pptx", "pptx", "Launch Plan"),
        ("sheets.xlsx", "excel", "Seoul"),
        ("text.pdf", "pdf", "Hello"),
    ] {
        let bytes = fixture(file);
        let detected = answer(eglu_document_detect(bytes.as_ptr(), bytes.len()));
        assert_eq!(detected["ok"]["format"], name, "{file}: {detected}");
        let given = markdown(&bytes, Some(name));
        assert_eq!(given["ok"]["format"], name, "{file}: {given}");
        let md = given["ok"]["markdown"].as_str().unwrap_or("");
        assert!(md.contains(words), "{file} as {name}: {given}");
    }
}

#[test]
fn detect_names_the_format_or_null() {
    assert_eq!(
        answer(eglu_document_detect(fixture("hello.docx").as_ptr(), 1679))["ok"]["format"],
        "docx"
    );
    let garbage = [0x11u8, 0x22, 0x33, 0x44];
    assert_eq!(
        answer(eglu_document_detect(garbage.as_ptr(), garbage.len()))["ok"]["format"],
        Value::Null
    );
}

#[test]
fn a_text_pdf_gives_pages_and_metadata() {
    let bytes = fixture("text.pdf");
    let answer = answer(eglu_pdf_pages(bytes.as_ptr(), bytes.len(), std::ptr::null()));
    let ok = &answer["ok"];
    assert_eq!(ok["pageCount"], 1, "{answer}");
    let pages = ok["pages"].as_array().unwrap();
    assert_eq!(pages.len(), 1);
    assert_eq!(pages[0]["page"], 0);
    assert_eq!(pages[0]["needsOCR"], false);
    assert!(pages[0]["markdown"].as_str().unwrap().contains("Hello"), "{answer}");
}

#[test]
fn a_picture_pdf_marks_its_page_for_ocr() {
    let bytes = fixture("picture.pdf");
    let answer = answer(eglu_pdf_pages(bytes.as_ptr(), bytes.len(), std::ptr::null()));
    let pages = answer["ok"]["pages"].as_array().unwrap();
    assert_eq!(pages[0]["needsOCR"], true, "{answer}");
}

#[test]
fn page_selection_is_zero_based() {
    let bytes = fixture("text.pdf");
    let first = answer(eglu_pdf_pages(
        bytes.as_ptr(),
        bytes.len(),
        c("[0]").as_ptr(),
    ));
    assert_eq!(first["ok"]["pages"].as_array().unwrap().len(), 1);
    let outside = answer(eglu_pdf_pages(
        bytes.as_ptr(),
        bytes.len(),
        c("[3]").as_ptr(),
    ));
    assert!(
        outside["ok"]["pages"].as_array().map_or(true, |p| p.is_empty()) || outside.get("error").is_some(),
        "out-of-range page: {outside}"
    );
}

#[test]
fn random_bytes_never_crash() {
    let mut bytes = [0u8; 512];
    let mut seed = 0x12345678u64;
    for byte in bytes.iter_mut() {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
        *byte = (seed >> 33) as u8;
    }
    let answer = markdown(&bytes, None);
    let kind = answer["error"]["kind"].as_str().unwrap_or("");
    assert!(
        kind == "unsupported" || kind == "malformed",
        "garbage answered {answer}"
    );
}

#[test]
fn csv_needs_its_format_given() {
    let csv = b"a,b\n1,2\n";
    let detected = markdown(csv, None);
    assert!(detected.get("error").is_some() || detected["ok"]["format"].is_null());
    let given = markdown(csv, Some("csv"));
    assert_eq!(given["ok"]["format"], "csv", "{given}");
}
