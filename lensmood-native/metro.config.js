// Native React Native Skia requires no special Metro configuration.
// This passthrough is the place to add web/WASM (canvaskit) support later,
// e.g. config.resolver.assetExts.push('wasm').
const { getDefaultConfig } = require('expo/metro-config')

const config = getDefaultConfig(__dirname)

module.exports = config
