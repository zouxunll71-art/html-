# Structured parser adapter

parse5 tokenizes the strict ui-* fragments; Python retains the protocol tree builder. This intentionally does not use browser tree repair: self-closing custom tags keep their existing meaning, and malformed nesting is an error. The pinned parse5 Tokenizer is an internal API; review this adapter before updating parse5.

CSS Tree parses declarations and class rules. The compiler still enforces the native style whitelist. This does not enable arbitrary browser CSS. Ajv validates app/catalog/action-file structure; existing semantic validation still checks resource references, translations, bindings and routes.

worker.mjs uses a JSON-lines interface and a persistent, serialized Python adapter. Small requests are cached (256 entries, input at most 64 KiB); large requests are not cached. Requests have size limits and a timeout. A crashed read-only worker is restarted once. The app does not download dependencies at startup.

Dependencies are pinned in package.json and dependencies.lock.json, including original tarball integrity. node_modules is part of the distribution; retain license files and include this directory in sharing packages. No npm lifecycle scripts were executed when vendoring.

Verification for this change is syntax/declaration inspection only. Functional execution, build, benchmark and simulator interaction remain for the user under IOS_All.md rule 19.
