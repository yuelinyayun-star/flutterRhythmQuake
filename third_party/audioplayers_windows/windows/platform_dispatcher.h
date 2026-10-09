#pragma once

#include <windows.h>
#include <functional>
#include <mutex>
#include <queue>
#include <stdexcept>

// Created and destroyed on Flutter's platform thread. Media Foundation workers
// only enqueue tasks; this window dispatches them in the platform message loop.
class PlatformDispatcher {
 public:
  PlatformDispatcher() {
    const auto instance = GetModuleHandleW(nullptr);
    const wchar_t* name = L"RhythmQuake.AudioPlatformDispatcher";
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = WindowProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = name;
    if (!RegisterClassW(&window_class) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      throw std::runtime_error("Cannot register audio platform dispatcher");
    }
    window_ = CreateWindowExW(0, name, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                              nullptr, instance, this);
    if (!window_) {
      throw std::runtime_error("Cannot create audio platform dispatcher");
    }
  }

  ~PlatformDispatcher() {
    HWND window;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      window = window_;
      window_ = nullptr;
      std::queue<std::function<void()>> empty;
      tasks_.swap(empty);
    }
    if (window) DestroyWindow(window);
  }

  PlatformDispatcher(const PlatformDispatcher&) = delete;
  PlatformDispatcher& operator=(const PlatformDispatcher&) = delete;

  void Post(std::function<void()> task) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!window_) return;
    if (!PostMessageW(window_, WM_APP, 0, 0)) return;
    tasks_.push(std::move(task));
  }

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    const auto self = reinterpret_cast<PlatformDispatcher*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_APP && self) {
      self->Drain();
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  void Drain() {
    std::queue<std::function<void()>> pending;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pending.swap(tasks_);
    }
    while (!pending.empty()) {
      pending.front()();
      pending.pop();
    }
  }

  HWND window_ = nullptr;
  std::mutex mutex_;
  std::queue<std::function<void()>> tasks_;
};
