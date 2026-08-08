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

const unsignedPackage = read("tools/release/create-unsigned-ipa.sh");
requireText(
  unsignedPackage,
  "codesign --remove-signature",
  "unsigned IPA packaging does not strip embedded Mach-O signatures"
);
requireText(
  unsignedPackage,
  "embedded.mobileprovision",
  "unsigned IPA packaging does not reject provisioning profiles"
);

const tabStore = read("browser/Reynard/Client/Stores/TabManagementStore.swift");
requireText(tabStore, "privateTabs: []", "private tabs can be returned from persistent storage");
requireText(tabStore, "selectedPrivateTabID: nil", "private tab selection can be persisted");
requireText(tabStore, "purgePersistedPrivateTabsLocked", "legacy private tab records are not purged");
rejectText(tabStore, "insertTabsLocked(persistedPrivateTabs", "private tabs are written to SQLite");

const browserPreferences = read("browser/Reynard/Client/Preferences/BrowserPreferences.swift");
requireText(
  browserPreferences,
  "static var openingScreen: HomepageOpeningScreen",
  "homepage opening-screen preference is missing"
);

const tabManager = read("browser/Reynard/Client/TabManagement/TabManagerImpl.swift");
requireText(tabManager, "guard !tab.isPrivate", "private navigation state is not protected from persistence");
requireText(
  tabManager,
  "func createInitialTab(openingScreen: HomepageOpeningScreen)",
  "session restore preference is not passed into initial-tab creation"
);
requireText(tabManager, "case .lastTab:", "last-session startup mode is not handled");
requireText(tabManager, "restoreTabsIfNeeded()", "last-session startup mode does not restore persisted tabs");

const downloadStore = read("browser/Reynard/Client/Stores/DownloadStore.swift");
requireText(downloadStore, "DownloadCleanupPolicy.partition", "date-based download cleanup does not use the tested policy");
rejectText(downloadStore, "self.persistedDownloads.removeAll()", "download cleanup still contains the original unconditional clear");

const autofillHandler = read("browser/GeckoView/Session/GeckoAutofillHandler.swift");
rejectText(
  autofillHandler,
  'fatalError("Unimplemented")',
  "optional autofill bridge selectors still crash when unavailable"
);

const geckoSession = read("browser/GeckoView/Session/GeckoSession.swift");
rejectText(
  geckoSession,
  'fatalError("GeckoView window has no view")',
  "missing Gecko view still crashes the browser"
);

const faviconStore = read("browser/Reynard/Client/Stores/FaviconStore.swift");
rejectText(
  faviconStore,
  "SafariSharedUI",
  "favicon rendering still calls a private Safari framework"
);
requireText(
  faviconStore,
  "?? fileManager.temporaryDirectory",
  "favicon cache initialization can still crash when Application Support is unavailable"
);
requireText(
  faviconStore,
  "CGImageSourceCopyPropertiesAtIndex",
  "favicon decoding does not validate image dimensions before UIKit decoding"
);
requireText(
  faviconStore,
  "URLUtils.isWebURL(requestedURL)",
  "favicon metadata requests allow non-web URL schemes"
);

const pictureInPictureDelegate = read("browser/GeckoView/Delegates/PictureInPictureDelegate.swift");
rejectText(
  pictureInPictureDelegate,
  "preconditionFailure",
  "an unavailable picture-in-picture candidate still crashes the browser"
);

const pictureInPictureCoordinator = read(
  "browser/Reynard/Client/SessionManagement/Media/PictureInPictureCoordinator.swift"
);
requireText(
  pictureInPictureCoordinator,
  "@available(iOS 15.0, *)",
  "picture-in-picture coordinator is not guarded for iOS 13 and 14"
);
requireText(
  pictureInPictureCoordinator,
  "deinit",
  "picture-in-picture coordinator does not define lifecycle cleanup"
);
requireText(
  pictureInPictureCoordinator,
  "observedSession?.pictureInPictureDelegate = nil",
  "picture-in-picture coordinator leaves the Gecko session delegate attached"
);
requireText(
  pictureInPictureCoordinator,
  "state.presentation?.controller.delegate = nil",
  "picture-in-picture coordinator leaves the AVKit controller delegate attached"
);
requireText(
  pictureInPictureCoordinator,
  "mediaSession.observer = nil",
  "picture-in-picture coordinator leaves the media observer attached"
);
requireText(
  pictureInPictureCoordinator,
  "sessionManager.applicationStateObserver = nil",
  "picture-in-picture coordinator leaves the application observer attached"
);
requireText(
  pictureInPictureCoordinator,
  "sessionManager.pictureInPictureHandler = nil",
  "picture-in-picture coordinator leaves the session handler attached"
);

console.log("Project safety validation passed");
