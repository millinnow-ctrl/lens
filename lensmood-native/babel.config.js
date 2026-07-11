module.exports = function (api) {
  api.cache(true)
  return {
    presets: ['babel-preset-expo'],
    // react-native-worklets/plugin replaces the old reanimated/plugin in
    // Reanimated 4. It must be listed LAST. Skia's animated values ride on it.
    plugins: ['react-native-worklets/plugin'],
  }
}
