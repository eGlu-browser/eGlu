//! anydoc and pdf-inspector behind the JSON envelope: Office, OpenDocument,
//! RTF, EPUB and CSV bytes to Markdown, and PDFs page by page.

use std::ffi::c_char;

use anydoc::{to_markdown_bytes, ConvertError, Format};
use pdf_inspector::{detect_pdf_mem, extract_pages_markdown_mem, PdfError};
use serde_json::{json, Value};

use crate::json::error;

/// The most a conversion takes. Past it the engines answer `tooLarge` without
/// reading the bytes.
const MAX_BYTES: usize = 200 * 1024 * 1024;

/// `bytes` of a document to `{"format": …, "markdown": …}`. `format` names the
/// format (`"docx"`, `"csv"`, …) or detects it from the bytes when null or "".
/// CSV has no signature: it must always be given.
pub(crate) fn markdown(bytes: &[u8], format: Option<&str>) -> Result<Value, *mut c_char> {
    if bytes.len() > MAX_BYTES {
        return Err(error("tooLarge", "the file is over 200 MB"));
    }
    let given = match format {
        None | Some("") => None,
        Some(name) => Some(
            format_named(name)
                .ok_or_else(|| error("malformed", format!("unknown format \"{name}\"")))?,
        ),
    };
    let format = given.or_else(|| Format::from_bytes(bytes));
    match to_markdown_bytes(bytes, format) {
        Ok(markdown) => Ok(json!({ "format": format.map(format_name), "markdown": markdown })),
        Err(e) => Err(error(convert_kind(&e), e.to_string())),
    }
}

/// `{"format": "docx"}` or `{"format": null}`.
pub(crate) fn detect(bytes: &[u8]) -> Result<Value, *mut c_char> {
    if bytes.len() > MAX_BYTES {
        return Err(error("tooLarge", "the file is over 200 MB"));
    }
    Ok(json!({ "format": Format::from_bytes(bytes).map(format_name) }))
}

/// A PDF's pages one by one: its metadata, and each page's Markdown with a
/// `needsOCR` flag where the page holds no readable text. `pages_json` is null
/// for every page, or a JSON array of 0-based page numbers.
pub(crate) fn pdf_pages(bytes: &[u8], pages_json: Option<&str>) -> Result<Value, *mut c_char> {
    if bytes.len() > MAX_BYTES {
        return Err(error("tooLarge", "the file is over 200 MB"));
    }
    let pages: Option<Vec<u32>> = match pages_json {
        None => None,
        Some(json_text) => Some(
            serde_json::from_str(json_text)
                .map_err(|e| error("malformed", format!("the pages JSON: {e}")))?,
        ),
    };

    let info = detect_pdf_mem(bytes).map_err(|e| error(pdf_kind(&e), e.to_string()))?;
    let result =
        extract_pages_markdown_mem(bytes, pages.as_deref()).map_err(|e| error(pdf_kind(&e), e.to_string()))?;

    Ok(json!({
        "pageCount": info.page_count,
        "title": info.title,
        "author": info.author,
        "created": info.creation_date,
        // A 0-based page number past the end is dropped, not answered.
        "pages": result.pages.iter().filter(|page| page.page < info.page_count).map(|page| json!({
            "page": page.page,
            "markdown": page.markdown,
            "needsOCR": page.needs_ocr,
            "reason": page.ocr_reason,
        })).collect::<Vec<_>>(),
        // pdf-inspector counts pages_needing_ocr, pages_with_tables and
        // pages_with_columns from 1 (the PageMarkdown.page fields above are
        // 0-based); eGlu's answers count every page number from 0.
        "withTables": result.pages_with_tables.iter().map(|page| page - 1).collect::<Vec<_>>(),
        "withColumns": result.pages_with_columns.iter().map(|page| page - 1).collect::<Vec<_>>(),
    }))
}

/// Every format by the name eGlu's interface gives it: what `format_name`
/// answers, and what Swift's `DocumentFormat` sends.
const FORMATS: [(Format, &str); 12] = [
    (Format::Doc, "doc"),
    (Format::Docx, "docx"),
    (Format::Odt, "odt"),
    (Format::Pdf, "pdf"),
    (Format::Ppt, "ppt"),
    (Format::Pptx, "pptx"),
    (Format::Rtf, "rtf"),
    (Format::Epub, "epub"),
    (Format::Excel, "excel"),
    (Format::Ods, "ods"),
    (Format::Odp, "odp"),
    (Format::Csv, "csv"),
];

/// The format a name gives: one of eGlu's names, or else a file extension
/// anydoc knows ("xlsx", "docm"). eGlu's names come first because anydoc's
/// `from_extension` knows no "excel": a spreadsheet sent by that name would
/// otherwise be an unknown format.
fn format_named(name: &str) -> Option<Format> {
    FORMATS
        .iter()
        .find(|(_, known)| *known == name)
        .map(|(format, _)| *format)
        .or_else(|| Format::from_extension(name))
}

fn format_name(format: Format) -> &'static str {
    match format {
        Format::Doc => "doc",
        Format::Docx => "docx",
        Format::Odt => "odt",
        Format::Pdf => "pdf",
        Format::Ppt => "ppt",
        Format::Pptx => "pptx",
        Format::Rtf => "rtf",
        Format::Epub => "epub",
        Format::Excel => "excel",
        Format::Ods => "ods",
        Format::Odp => "odp",
        Format::Csv => "csv",
    }
}

fn convert_kind(error: &ConvertError) -> &'static str {
    match error {
        ConvertError::Unsupported(_) => "unsupported",
        ConvertError::NeedsOcr { .. } => "needsOCR",
        ConvertError::Malformed { .. } => "malformed",
        ConvertError::Encrypted => "encrypted",
        ConvertError::ResourceLimit { .. } => "resourceLimit",
        ConvertError::MissingPart { .. } => "missingPart",
        ConvertError::Io(_) => "io",
        _ => "unknown",
    }
}

fn pdf_kind(error: &PdfError) -> &'static str {
    match error {
        PdfError::Encrypted => "encrypted",
        PdfError::Io(_) => "io",
        PdfError::Parse(_) | PdfError::InvalidStructure | PdfError::NotAPdf(_) => "malformed",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_format_has_the_name_it_answers() {
        for (format, name) in FORMATS {
            assert_eq!(format_name(format), name);
            assert_eq!(format_named(name), Some(format), "{name}");
        }
    }
}
