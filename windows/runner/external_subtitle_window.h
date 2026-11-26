#ifndef RUNNER_EXTERNAL_SUBTITLE_WINDOW_H_
#define RUNNER_EXTERNAL_SUBTITLE_WINDOW_H_

#include <windows.h>

#include <flutter/encodable_value.h>

class ExternalSubtitleWindow {
 public:
  ExternalSubtitleWindow() = default;
  ~ExternalSubtitleWindow();

  bool Present(HWND main_window, const flutter::EncodableList& lines);
  void Hide();

 private:
  HWND window_ = nullptr;
  ULONG_PTR graphics_token_ = 0;
};

#endif  // RUNNER_EXTERNAL_SUBTITLE_WINDOW_H_
