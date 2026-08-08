#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const mainCatalogPath = path.join(root, "browser/Reynard/Resources/Localizable.xcstrings");
const addonCatalogPath = path.join(
  root,
  "browser/Reynard/Client/Interface/Addons/AddonLocalizable.xcstrings"
);

function fail(message) {
  console.error("Localization validation failed: " + message);
  process.exit(1);
}

function placeholders(value) {
  return [...value.matchAll(/%(?:\d+\$)?(?:@|d|lld|ld|s)/g)]
    .map((match) => match[0].replace(/%\d+\$/, "%"))
    .sort();
}

function localizedValue(entry, language) {
  const localization = entry.localizations?.[language];
  return (
    localization?.stringUnit?.value ??
    localization?.variations?.plural?.other?.stringUnit?.value
  );
}

const mainCatalog = JSON.parse(fs.readFileSync(mainCatalogPath, "utf8"));
for (const [key, entry] of Object.entries(mainCatalog.strings)) {
  const chinese = localizedValue(entry, "zh-Hans");
  if (!chinese) fail("missing zh-Hans translation: " + key);
  const expected = placeholders(key);
  const actual = placeholders(chinese);
  if (expected.join("|") !== actual.join("|")) {
    fail('placeholder mismatch for "' + key + '": ' + expected + " != " + actual);
  }
}

const legacyMainStringsPath = path.join(
  root,
  "browser/Reynard/Resources/zh-Hans.lproj/Localizable.strings"
);
if (fs.existsSync(legacyMainStringsPath)) {
  fail("Localizable.strings conflicts with Localizable.xcstrings in the Reynard target");
}

const addonCatalog = JSON.parse(fs.readFileSync(addonCatalogPath, "utf8"));
for (const [key, entry] of Object.entries(addonCatalog.strings)) {
  const english = entry.localizations?.en?.stringUnit?.value ?? key;
  const chinese = localizedValue(entry, "zh-Hans");
  if (!chinese) fail("missing add-on zh-Hans translation: " + key);
  if (placeholders(english).join("|") !== placeholders(chinese).join("|")) {
    fail('add-on placeholder mismatch for "' + key + '"');
  }
}

const projectFile = fs.readFileSync(
  path.join(root, "browser/Reynard.xcodeproj/project.pbxproj"),
  "utf8"
);
if (!projectFile.includes('"zh-Hans"')) fail("Xcode project does not declare zh-Hans");

console.log(
  "Localization validation passed: " +
    Object.keys(mainCatalog.strings).length +
    " app strings and " +
    Object.keys(addonCatalog.strings).length +
    " add-on strings"
);
