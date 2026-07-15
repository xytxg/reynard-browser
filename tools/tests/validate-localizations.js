#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const mainCatalogPath = path.join(root, "browser/Reynard/Resources/Localizable.xcstrings");
const mainStringsPath = path.join(root, "browser/Reynard/Resources/zh-Hans.lproj/Localizable.strings");
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

function parseStrings(filePath) {
  const result = new Map();
  const linePattern = /^("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");$/;
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);

  lines.forEach((line, index) => {
    if (!line) return;
    const match = line.match(linePattern);
    if (!match) fail("invalid .strings syntax at " + filePath + ":" + (index + 1));
    const key = JSON.parse(match[1]);
    const value = JSON.parse(match[2]);
    if (result.has(key)) fail("duplicate key in " + filePath + ": " + key);
    result.set(key, value);
  });

  return result;
}

const mainCatalog = JSON.parse(fs.readFileSync(mainCatalogPath, "utf8"));
const mainTranslations = parseStrings(mainStringsPath);
const expectedExtraKeys = new Set([
  'Are you sure you want to upload all files from "%@"? Only do this if you trust the site.',
]);

for (const key of Object.keys(mainCatalog.strings)) {
  if (!mainTranslations.has(key)) fail("missing zh-Hans translation: " + key);
  const expected = placeholders(key);
  const actual = placeholders(mainTranslations.get(key));
  if (expected.join("|") !== actual.join("|")) {
    fail('placeholder mismatch for "' + key + '": ' + expected + " != " + actual);
  }
}

for (const key of mainTranslations.keys()) {
  if (!mainCatalog.strings[key] && !expectedExtraKeys.has(key)) {
    fail("unexpected zh-Hans key: " + key);
  }
}

const addonCatalog = JSON.parse(fs.readFileSync(addonCatalogPath, "utf8"));
for (const [key, entry] of Object.entries(addonCatalog.strings)) {
  const english = entry.localizations?.en?.stringUnit?.value ?? key;
  const chinese = entry.localizations?.["zh-Hans"]?.stringUnit?.value;
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
