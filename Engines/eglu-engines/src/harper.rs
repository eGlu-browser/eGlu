//! Harper behind the JSON envelope: an `Engine` modelled on harper-wasm's
//! `Linter` (`harper-wasm/src/lib.rs`), holding the settings (the dialect,
//! the rules, the person's own words), the lint group and merged dictionary
//! built from them, and the ignored lints.

use std::collections::BTreeMap;
use std::ffi::c_char;
use std::sync::{Arc, OnceLock};

use harper_core::linting::{
    FlatConfig, HumanReadableSetting, HumanReadableStructuredConfig, LintGroup, Suggestion,
};
use harper_core::spell::{FstDictionary, MergedDictionary, MutableDictionary};
use harper_core::{Dialect, DictWordMetadata, Document, IgnoredLints, LintContext};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::json::error;

/// The most text `lint` takes: the caller lints a paragraph or a field, never
/// a book. Counted in UTF-16 units, the unit the answer's spans are in.
const MAX_UTF16: usize = 200_000;

/// Harper's `default_config.json` at the pinned harperSwift tag, embedded so
/// `rules` answers groups, labels and defaults. A test (`tests/harper.rs`)
/// checks it has not drifted from the compiled-in rule set, so updating the
/// tag means re-copying it too.
const DEFAULT_CONFIG_JSON: &str = include_str!("default_config.json");

pub(crate) struct Engine {
    settings: Settings,
    /// Harper's dictionary and rules for `settings`, built on first use
    /// rather than in `new`: building them takes a few hundred milliseconds
    /// (the curated dictionary's search structure once per process, then
    /// this engine's lint group), and `new` runs on whichever thread makes
    /// the engine, which can be the main one. The first lint, or `warm_up`,
    /// builds them on the engine's own thread.
    linter: Option<Linter>,
    ignored: IgnoredLints,
}

struct Linter {
    lint_group: LintGroup,
    dictionary: Arc<MergedDictionary>,
}

/// `{"dialect":"American","rules":{"SpellCheck":false},"words":["eGlu"]}`.
/// `rules` lists only differences from Harper's defaults.
#[derive(Deserialize, Default)]
#[serde(default)]
struct SettingsJson {
    dialect: Option<String>,
    rules: BTreeMap<String, bool>,
    words: Vec<String>,
}

struct Settings {
    dialect: Dialect,
    rules: BTreeMap<String, bool>,
    words: Vec<String>,
}

impl Settings {
    /// Checks everything a later build would trip on, so a bad setting is
    /// an error of `new` or `configure`, not of the first lint.
    fn parse(settings_json: &str) -> Result<Self, String> {
        let given: SettingsJson =
            serde_json::from_str(settings_json).map_err(|e| format!("the settings JSON: {e}"))?;
        Ok(Self {
            dialect: dialect(given.dialect.as_deref())?,
            rules: given.rules,
            words: given.words,
        })
    }
}

impl Linter {
    fn build(settings: &Settings) -> Self {
        let dictionary = merged_dictionary(&settings.words);
        let lint_group = lint_group(dictionary.clone(), settings.dialect, &settings.rules);
        Self { lint_group, dictionary }
    }
}

impl Engine {
    /// Reads the settings only; see `linter`.
    pub(crate) fn new(settings_json: &str) -> Result<Self, String> {
        Ok(Self {
            settings: Settings::parse(settings_json)?,
            linter: None,
            ignored: IgnoredLints::new(),
        })
    }

    /// Same settings as `new`. A linter already built is built again here,
    /// on the engine's thread, so the next lint is as quick as the last; one
    /// not built yet waits for its first use. The ignored lints carry over.
    pub(crate) fn configure(&mut self, settings_json: &str) -> Result<(), String> {
        self.settings = Settings::parse(settings_json)?;
        if self.linter.is_some() {
            self.linter = Some(Linter::build(&self.settings));
        }
        Ok(())
    }

    /// Builds the dictionary and the rules, and runs one lint, so the first
    /// real one is quick.
    pub(crate) fn warm_up(&mut self) -> Result<Value, *mut c_char> {
        // The throwaway lint builds the linter, and loads what Harper keeps
        // per thread (its chunker model among them) on the calling one.
        self.lint("warm", "plain")?;
        Ok(json!(true))
    }

    pub(crate) fn lint(&mut self, text: &str, format: &str) -> Result<Value, *mut c_char> {
        if text.chars().map(char::len_utf16).sum::<usize>() > MAX_UTF16 {
            return Err(error("tooLarge", "the text is over 200,000 UTF-16 units"));
        }
        let markdown = match format {
            "markdown" => true,
            "plain" => false,
            other => {
                return Err(error(
                    "malformed",
                    format!("unknown format \"{other}\"; \"plain\" or \"markdown\""),
                ))
            }
        };
        let linter = self.linter.get_or_insert_with(|| Linter::build(&self.settings));
        let document = if markdown {
            Document::new_markdown_default(text, &*linter.dictionary)
        } else {
            Document::new_plain_english(text, &*linter.dictionary)
        };

        let mut organized = linter.lint_group.organized_lints(&document);
        for lints in organized.values_mut() {
            self.ignored.remove_ignored(lints, &document);
        }

        let offsets = utf16_offsets(document.get_source());
        let utf16 = |index: usize| offsets[index.min(offsets.len() - 1)];
        let mut answers = Vec::new();
        for (rule, lints) in &organized {
            for lint in lints {
                let start = utf16(lint.span.start);
                let end = utf16(lint.span.end);
                answers.push((start, lint.priority, json!({
                    "start": start,
                    "end": end,
                    "rule": rule,
                    "kind": lint.lint_kind.to_string_key(),
                    "message": lint.message,
                    "priority": lint.priority,
                    "suggestions": lint.suggestions.iter().map(suggestion_json).collect::<Vec<_>>(),
                    "context": format!("{:016x}", LintContext::from_lint(lint, &document).default_hash()),
                })));
            }
        }
        answers.sort_by_key(|(start, priority, _)| (*start, *priority));
        Ok(json!({ "lints": answers.into_iter().map(|(_, _, answer)| answer).collect::<Vec<_>>() }))
    }

    /// `context` is the hash a lint carried, as 16 hex digits.
    pub(crate) fn ignore(&mut self, context: &str) -> Result<(), String> {
        let hash = u64::from_str_radix(context, 16)
            .map_err(|_| format!("\"{context}\" is not a lint's context"))?;
        self.ignored.ignore_hash(hash);
        Ok(())
    }
}

fn dialect(name: Option<&str>) -> Result<Dialect, String> {
    Ok(match name.unwrap_or("American") {
        "American" => Dialect::American,
        "Canadian" => Dialect::Canadian,
        "Australian" => Dialect::Australian,
        "British" => Dialect::British,
        "Indian" => Dialect::Indian,
        other => return Err(format!("unknown dialect \"{other}\"")),
    })
}

/// Harper's curated dictionary with the person's own words over it.
fn merged_dictionary(words: &[String]) -> Arc<MergedDictionary> {
    let mut user_dictionary = MutableDictionary::new();
    user_dictionary.extend_words(
        words
            .iter()
            .map(|word| (word.chars().collect::<Vec<char>>(), DictWordMetadata::default())),
    );
    let mut merged = MergedDictionary::new();
    merged.add_dictionary(FstDictionary::curated());
    merged.add_dictionary(Arc::new(user_dictionary));
    Arc::new(merged)
}

fn lint_group(
    dictionary: Arc<MergedDictionary>,
    dialect: Dialect,
    rules: &BTreeMap<String, bool>,
) -> LintGroup {
    // Start from Harper's curated config: `rules` lists only differences.
    let mut config = FlatConfig::new_curated();
    for (name, on) in rules {
        // An unknown rule name is ignored.
        if config.has_rule(name) {
            config.set_rule_enabled(name, *on);
        }
    }
    // "One of many" rules are alternatives (OxfordComma and NoOxfordComma):
    // turning one on turns its siblings off, unless the caller named them too.
    for alternatives in one_of_many() {
        for name in &alternatives {
            if rules.get(name) == Some(&true) {
                for sibling in &alternatives {
                    if sibling != name && !rules.contains_key(sibling) {
                        config.set_rule_enabled(sibling, false);
                    }
                }
            }
        }
    }
    LintGroup::new_curated(dictionary, dialect).with_lint_config(config)
}

/// `{"ok": {"rules": [...]}}`'s list: every rule with its group's label, its
/// own label, a description and whether it is on in Harper's curated set.
pub(crate) fn rules() -> Value {
    let group = LintGroup::new_curated(Arc::new(MutableDictionary::new()), Dialect::American);
    let descriptions: std::collections::HashMap<&str, &str> =
        group.all_descriptions().into_iter().collect();
    let mut rules = Vec::new();
    for setting in &curated_config().settings {
        collect_rules(setting, "", &descriptions, &mut rules);
    }
    json!({ "rules": rules })
}

fn collect_rules(
    setting: &HumanReadableSetting,
    group: &str,
    descriptions: &std::collections::HashMap<&str, &str>,
    rules: &mut Vec<Value>,
) {
    match setting {
        HumanReadableSetting::Group { label, child, .. } => {
            let group = match (group.is_empty(), label) {
                (true, Some(label)) => label.clone(),
                (false, Some(label)) => format!("{group} / {label}"),
                (_, None) => group.to_owned(),
            };
            for setting in &child.settings {
                collect_rules(setting, &group, descriptions, rules);
            }
        }
        HumanReadableSetting::Bool { name, state, label } => rules.push(rule_json(
            name,
            label.as_deref().unwrap_or(name),
            group,
            descriptions.get(name.as_str()).copied().unwrap_or(""),
            *state,
        )),
        HumanReadableSetting::OneOfMany { names, name, labels } => {
            for (index, rule_name) in names.iter().enumerate() {
                let label = labels
                    .as_ref()
                    .and_then(|labels| labels.get(index))
                    .map(String::as_str)
                    .unwrap_or(rule_name);
                rules.push(rule_json(
                    rule_name,
                    label,
                    group,
                    descriptions.get(rule_name.as_str()).copied().unwrap_or(""),
                    name.as_ref() == Some(rule_name),
                ));
            }
        }
    }
}

fn rule_json(name: &str, label: &str, group: &str, description: &str, on: bool) -> Value {
    json!({
        "id": name,
        "label": label,
        "description": description,
        "group": group,
        "isOnByDefault": on,
    })
}

/// Every "one of many" alternative set (OxfordComma / NoOxfordComma and the
/// like) in the curated config, so enabling one disables the rest.
fn one_of_many() -> Vec<Vec<String>> {
    let mut sets = Vec::new();
    collect_one_of_many(&curated_config().settings, &mut sets);
    sets
}

fn collect_one_of_many(settings: &[HumanReadableSetting], sets: &mut Vec<Vec<String>>) {
    for setting in settings {
        match setting {
            HumanReadableSetting::Group { child, .. } => {
                collect_one_of_many(&child.settings, sets)
            }
            HumanReadableSetting::OneOfMany { names, .. } => sets.push(names.clone()),
            HumanReadableSetting::Bool { .. } => {}
        }
    }
}

fn curated_config() -> &'static HumanReadableStructuredConfig {
    static CONFIG: OnceLock<HumanReadableStructuredConfig> = OnceLock::new();
    CONFIG.get_or_init(|| {
        serde_json::from_str(DEFAULT_CONFIG_JSON).expect("default_config.json parses")
    })
}

fn suggestion_json(suggestion: &Suggestion) -> Value {
    match suggestion {
        Suggestion::ReplaceWith(chars) => json!({ "replace": chars.iter().collect::<String>() }),
        Suggestion::InsertAfter(chars) => json!({ "insert": chars.iter().collect::<String>() }),
        Suggestion::Remove => json!({ "remove": true }),
    }
}

/// For each index into `source` (Harper's `Span<char>` counts chars), the
/// UTF-16 code-unit index it stands at, the unit Swift's NSString,
/// JavaScript strings and the Accessibility API count in: a scalar past
/// U+FFFF counts two. One pass for every lint of a call; counting from the
/// start for each lint took lints × length. The last entry is the text's
/// end, so an end-exclusive span's end has one too.
fn utf16_offsets(source: &[char]) -> Vec<usize> {
    let mut offsets = Vec::with_capacity(source.len() + 1);
    let mut offset = 0;
    offsets.push(offset);
    for c in source {
        offset += c.len_utf16();
        offsets.push(offset);
    }
    offsets
}
