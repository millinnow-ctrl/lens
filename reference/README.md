# Reference engine — ground truth for the SwiftUI FilmEngine

`lib/` is the film engine (canvas twin of `lensmood-native/src/engine/engine.ts`).
Run headless in Node via @napi-rs/canvas:

    npm i -D @napi-rs/canvas --legacy-peer-deps   # in lensmood-native/
    npx tsc lib/*.ts --outDir out --module commonjs --target es2020 --lib es2020,dom --noCheck

    # render preview grids (the in-chat before/afters)
    NODE_PATH=../lensmood-native/node_modules node render.cjs golden "kodachrome,film-noir,polaroid"

    # bake color-core LUTs + measure LUT-vs-reference parity (Stage 2a finding)
    NODE_PATH=../lensmood-native/node_modules node lutbake.cjs

`lutbake.cjs` writes the Class-A LUTs to ../LensMoodApp/Resources/luts and
prints per-stock color-core error. This is how we prove the Swift color port
has zero drift, and how we classified the 18 stocks (see
../LensMoodApp/Sources/Engine/ENGINE.md).
