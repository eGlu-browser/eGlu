//! Harper behind the JSON envelope: a `Linter` modelled on harper-wasm's
//! (`harper-wasm/src/lib.rs`), holding the lint group, the person's own
//! dictionary, the merged dictionary, the ignored lints and the dialect.

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
    lint_group: LintGroup,
    user_dictionary: MutableDictionary,
    dictionary: Arc<MergedDictionary>,
    ignored: IgnoredLints,
    dialect: Dialect,
}

/// `{"dialect":"American","rules":{"SpellCheck":false},"words":["eGlu"]}`.
/// `rules` lists only differences from Harper's defaults.
#[derive(Deserialize, Default)]
#[serde(default)]
struct Settings {
    dialect: Option<String>,
    rules: BTreeMap<String, bool>,
    words: Vec<String>,
}

impl Engine {
    pub(crate) fn new(settings_json: &str) -> Result<Self, String> {
        let settings: Settings =
            serde_json::from_str(settings_json).map_err(|e| format!("the settings JSON: {e}"))?;
        let dialect = dialect(settings.dialect.as_deref())?;
        let user_dictionary = user_dictionary(&settings.words);
        let dictionary = merged_dictionary(&user_dictionary);
        let lint_group = lint_group(dictionary.clone(), dialect, &settings.rules);

        Ok(Self {
            lint_group,
            user_dictionary,
            dictionary,
            ignored: IgnoredLints::new(),
            dialect,
        })
    }

    /// Same settings as `new`: rebuilds the lint group and the merged
    /// dictionary. The ignored lints carry over.
    pub(crate) fn configure(&mut self, settings_json: &str) -> Result<(), String> {
        let settings: Settings =
            serde_json::from_str(settings_json).map_err(|e| format!("the settings JSON: {e}"))?;
        self.dialect = dialect(settings.dialect.as_deref())?;
        self.user_dictionary = user_dictionary(&settings.words);
        self.dictionary = merged_dictionary(&self.user_dictionary);
        self.lint_group = lint_group(self.dictionary.clone(), self.dialect, &settings.rules);
        Ok(())
    }

    /// Builds the dictionary's search structure and runs one lint, so the
    /// first real one is quick.
    pub(crate) fn warm_up(&mut self) -> Result<Value, *mut c_char> {
        // FstDictionary::curated builds its search structure the first time a
        // word is looked up; one throwaway lint does that here.
        self.lint("warm", "plain")?;
        Ok(json!(true))
    }

    pub(crate) fn lint(&mut self, text: &str, format: &str) -> Result<Value, *mut c_char> {
        if text.chars().map(char::len_utf16).sum::<usize>() > MAX_UTF16 {
            return Err(error("tooLarge", "the text is over 200,000 UTF-16 units"));
        }
        let document = match format {
            "markdown" => Document::new_markdown_default(text, &*self.dictionary),
            "plain" => Document::new_plain_english(text, &*self.dictionary),
            other => {
                return Err(error(
                    "malformed",
                    format!("unknown format \"{other}\"; \"plain\" or \"markdown\""),
                ))
            }
        };

        let mut organized = self.lint_group.organized_lints(&document);
        for lints in organized.values_mut() {
            self.ignored.remove_ignored(lints, &document);
        }

        let source = document.get_source();
        let mut answers = Vec::new();
        for (rule, lints) in &organized {
            for lint in lints {
                let start = utf16_index(lint.span.start, source);
                let end = utf16_index(lint.span.end, source);
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

fn user_dictionary(words: &[String]) -> MutableDictionary {
    let mut dictionary = MutableDictionary::new();
    dictionary.extend_words(
        words
            .iter()
            .map(|word| (word.chars().collect::<Vec<char>>(), DictWordMetadata::default())),
    );
    dictionary
}

fn merged_dictionary(user_dictionary: &MutableDictionary) -> Arc<MergedDictionary> {
    let mut merged = MergedDictionary::new();
    merged.add_dictionary(FstDictionary::curated());
    merged.add_dictionary(Arc::new(user_dictionary.clone()));
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

/// Harper's `Span<char>` index as a UTF-16 code-unit index, the unit Swift's
/// NSString, JavaScript strings and the Accessibility API count in: a scalar
/// past U+FFFF counts two.
fn utf16_index(char_index: usize, source: &[char]) -> usize {
    source.iter().take(char_index).map(|c| c.len_utf16()).sum()
}
