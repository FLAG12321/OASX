#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
// 单实例互斥体名（Local\ 前缀按会话隔离，多用户登录互不冲突）。
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\OASX.SingleInstanceMutex";
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 单实例检测：已有实例在运行时唤醒它并退出，不再创建第二个窗口。
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  // 互斥体创建失败（返回 nullptr）时静默降级为允许多实例，属合理兜底。
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // 定位已有窗口（类名 + 标题 "oasx" 精确匹配；若未来窗口改名需同步此约束）。
    HWND existing = ::FindWindowW(GetRunnerWindowClassName(), L"oasx");
    if (existing != nullptr) {
      // 本实例是新启动进程，Windows 通常已授予其前台权限；借此授予任意进程
      // 前台权限，使后台的首个实例收到唤醒消息后能 SetForegroundWindow 抢到
      // 焦点（绕开 Windows 前台锁；该调用失败也无副作用，退化为任务栏闪烁）。
      ::AllowSetForegroundWindow(ASFW_ANY);
      // 通知已有实例自行还原并置前（见 flutter_window.cpp 唤醒处理）。
      // 用 PostMessage 异步投递，避免 SendMessage 在首实例启动期同步阻塞。
      ::PostMessage(existing,
                    ::RegisterWindowMessageW(kOasxActivateWindowMessage), 0, 0);
    }
    // 本实例持有的互斥体引用释放；主实例句柄在 wWinMain 存活期间不关闭，
    // 保证互斥体一直存在，进程退出时由 OS 自动回收。
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"oasx", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
