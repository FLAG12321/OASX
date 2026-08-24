enum StorageKey {
  dark,
  language,
  logFontPreset,
  logFontSize,
  username,
  password,
  address,
  // 自动启动脚本条目，存储对象数组 JSON（[{"name":..,"delaySeconds":..}]），
  // 兼容读取历史的脚本名数组格式
  autoScriptList,
  // 开机自启开关缓存（真实状态仍以系统注册项为准）
  launchAtStartup,
}
