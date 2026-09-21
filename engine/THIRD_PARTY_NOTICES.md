# Third-party notices

## idb simulator input protocol

scripts/ios_input.m uses the Indigo single-touch envelope and runtime client interface documented by Meta idb. Reference revision: 0050ce34601a7be830a7042962564083fc51daf7.

Source: https://github.com/facebook/idb/tree/0050ce34601a7be830a7042962564083fc51daf7/FBSimulatorControl/HID

MIT License

Copyright (c) Meta Platforms, Inc. and affiliates.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Bundled structured parser dependencies

Pinned registry packages are included in `bridge/parser/node_modules` without running install scripts. Package tarball integrity and exact versions are recorded in `bridge/parser/dependencies.lock.json`. Each package retains its upstream license file.

- css-tree 3.1.0 — MIT; license in `bridge/parser/node_modules/css-tree/`.
- mdn-data 2.12.2 — CC0-1.0; license in `bridge/parser/node_modules/mdn-data/`.
- source-map-js 1.2.1 — BSD-3-Clause; license in `bridge/parser/node_modules/source-map-js/`.
- ajv 8.17.1 — MIT; license in `bridge/parser/node_modules/ajv/`.
- fast-uri 3.1.0 — BSD-3-Clause; license in `bridge/parser/node_modules/fast-uri/`.
- fast-deep-equal 3.1.3 — MIT; license in `bridge/parser/node_modules/fast-deep-equal/`.
- require-from-string 2.0.2 — MIT; license in `bridge/parser/node_modules/require-from-string/`.
- json-schema-traverse 1.0.0 — MIT; license in `bridge/parser/node_modules/json-schema-traverse/`.
- parse5 7.3.0 — MIT; license in `bridge/parser/node_modules/parse5/`.
- entities 6.0.1 — BSD-2-Clause; license in `bridge/parser/node_modules/entities/`.
