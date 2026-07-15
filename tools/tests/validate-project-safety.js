#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

function requireText(value, fragment, message) {
  if (!value.includes(fragment)) {
    throw new Error(message);
  }
}

function rejectText(value, fragment, message) {
  if (value.includes(fragment)) {
    throw new Error(message);
  }
}

const workflow = read(".github/workflows/build-unsigned-ipa.yml");
requireText(workflow, "tools/development/build-gecko.sh", "IPA workflow does not build Gecko from source");
requireText(workflow, "tools/release/build-unsigned-app.sh", "IPA workflow does not build Reynard.app from source");
rejectText(workflow, "releases/download", "IPA workflow downloads a release binary");
rejectText(workflow, "source.ipa", "IPA workflow accepts a prebuilt IPA as its source");

const unsignedBuild = read("tools/release/build-unsigned-app.sh");
requireText(unsignedBuild, "CODE_SIGNING_ALLOWED=NO", "unsigned app build does not disable signing");
requireText(unsignedBuild, "AD_HOC_CODE_SIGNING_ALLOWED=NO", "unsigned app build allows ad-hoc signing");

const tabStore = read("browser/Reynard/Client/Stores/TabManagementStore.swift");
requireText(tabStore, "privateTabs: []", "private tabs can be returned from persistent storage");
requireText(tabStore, "selectedPrivateTabID: nil", "private tab selection can be persisted");
requireText(tabStore, "purgePersistedPrivateTabsLocked", "legacy private tab records are not purged");
rejectText(tabStore, "insertTabsLocked(persistedPrivateTabs", "private tabs are written to SQLite");

const tabManager = read("browser/Reynard/Client/TabManagement/TabManagerImpl.swift");
requireText(tabManager, "guard !tab.isPrivate", "private navigation state is not protected from persistence");
requireText(tabManager, "restoresPreviousSession", "session restore preference is not enforced");

const downloadStore = read("browser/Reynard/Client/Stores/DownloadStore.swift");
requireText(downloadStore, "DownloadCleanupPolicy.partition", "date-based download cleanup does not use the tested policy");
rejectText(downloadStore, "self.persistedDownloads.removeAll()", "download cleanup still contains the original unconditional clear");

console.log("Project safety validation passed");
