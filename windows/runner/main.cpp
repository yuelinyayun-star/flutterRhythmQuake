#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kRhythmQuakeWindowClass[] =
    L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWAuthReturnUri[] = L"rhythmquake://wauth-complete";

bool FocusRunningRhythmQuake(const wchar_t* command_line) {
  const std::wstring arguments = command_line == nullptr ? L"" : command_line;
  if (arguments.find(kWAuthReturnUri) == std::wstring::npos) {
    return false;
  }

  const HWND existing_window =
      ::FindWindow(kRhythmQuakeWindowClass, nullptr);
  if (existing_window == nullptr) {
    return false;
  }

  ::ShowWindow(existing_window,
               ::IsIconic(existing_window) ? SW_RESTORE : SW_SHOW);
  ::BringWindowToTop(existing_window);
  ::SetForegroundWindow(existing_window);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (FocusRunningRhythmQuake(command_line)) {
    return EXIT_SUCCESS;
  }

  EnableProcessEfficiencyMode();

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
  if (!window.Create(L"flutterrhythmquake", origin, size)) {
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
