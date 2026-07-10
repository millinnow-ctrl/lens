# Reference engine — ground truth for the SwiftUI FilmEngine

`lib/` is the film engine (canvas implementation, byte-parity twin of
`lensmood-native/src/engine/engine.ts`). `render.cjs` runs it headless in Node
via @napi-rs/canvas and renders `photos/` through any stocks:

    npx tsc lib/*.ts --outDir out --module commonjs --target es2020 --lib es2020,dom --noCheck
    NODE_PATH=../lensmood-native/node_modules node render.cjs golden "disposable,polaroid,film-noir"

Outputs preview grids + parity fixtures the Swift engine's XCTests compare
against. This is how the in-chat lens previews were produced.
