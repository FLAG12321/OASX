#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// 唤醒已有单实例的窗口消息名（与 main.cpp 同名注册，同会话返回同一消息 ID）。
constexpr wchar_t kOasxActivateWindowMessage[] = L"OASX.ActivateExistingWindow";

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 已注册的“唤醒已有实例”窗口消息 ID（0 表示注册失败，此时忽略该消息）。
  UINT activate_message_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
