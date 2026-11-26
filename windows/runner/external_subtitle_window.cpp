#include "external_subtitle_window.h"

#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <string>

namespace {

constexpr wchar_t kWindowClass[] = L"RhythmQuakeExternalSubtitle";
constexpr wchar_t kWindowTitle[] =
    L"RhythmQuake \u5730\u9707\u5B57\u5E55";
constexpr float kSubtitleWidth = 660.0f;
constexpr float kInfoLeftMargin = 16.0f;
constexpr float kSubtitleTopMargin = 38.0f;
constexpr float kEewBottomMargin = 24.0f;

const flutter::EncodableValue* Field(const flutter::EncodableMap& row,
                                     const char* name) {
  const auto field = row.find(flutter::EncodableValue(name));
  return field == row.end() ? nullptr : &field->second;
}

std::string Text(const flutter::EncodableMap& row, const char* name) {
  const auto* field = Field(row, name);
  const auto* text = field ? std::get_if<std::string>(field) : nullptr;
  return text ? *text : std::string();
}

bool Flag(const flutter::EncodableMap& row, const char* name) {
  const auto* field = Field(row, name);
  const auto* value = field ? std::get_if<bool>(field) : nullptr;
  return value && *value;
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int length = static_cast<int>(value.size());
  const int count = MultiByteToWideChar(CP_UTF8, 0, value.data(), length,
                                        nullptr, 0);
  std::wstring result(count, L'\0');
  if (count > 0) {
    MultiByteToWideChar(CP_UTF8, 0, value.data(), length, result.data(), count);
  }
  return result;
}

float MeasureLineHeight(Gdiplus::Graphics& graphics,
                        const flutter::EncodableMap& row, float width) {
  using namespace Gdiplus;
  const auto style = Text(row, "style");
  const auto text = Wide(Text(row, "text"));
  if (text.empty()) return 0.0f;

  const auto badge = Wide(Text(row, "badge"));
  const bool title = style == "eewTitle";
  const bool info_title = style == "infoTitle";
  const bool japanese = Flag(row, "japanese");
  const bool info = info_title || style == "info" || style == "infoDetail";
  const bool eew_text_block = !title && !info;
  const wchar_t* family_name = japanese ? L"Yu Gothic UI"
                                        : L"Microsoft YaHei UI";
  const float size = title ? 28.0f
                           : (info_title || style == "info" ||
                              style == "eewBody")
                               ? 23.0f
                               : 20.0f;
  FontFamily custom_family(family_name);
  const auto* family = custom_family.GetLastStatus() == Ok
                           ? &custom_family
                           : FontFamily::GenericSansSerif();
  Font font(family, size, FontStyleBold, UnitPixel);
  StringFormat format;
  const bool left_aligned =
      info_title || style == "info" || style == "infoDetail" ||
      style == "eewBody" || style == "jmaAreas" || style == "eewDetail";
  format.SetAlignment(left_aligned ? StringAlignmentNear
                                   : StringAlignmentCenter);
  RectF measured;
  const float block_width =
      eew_text_block ? std::min(394.0f, width - 32.0f) : width - 32.0f;
  const float badge_width = badge.empty() ? 0.0f : 110.0f;
  const float text_width = block_width - badge_width;
  graphics.MeasureString(text.c_str(), -1, &font,
                         RectF(0, 0, text_width, 1024.0f), &format, &measured);
  const float single_line_height = std::ceil(size * 1.35f);
  const float height = std::max(single_line_height, std::ceil(measured.Height));
  return height + 8.0f;
}

void DrawLine(Gdiplus::Graphics& graphics, const flutter::EncodableMap& row,
              float content_left, float width, float& y) {
  using namespace Gdiplus;
  const auto style = Text(row, "style");
  const auto text = Wide(Text(row, "text"));
  if (text.empty()) return;

  const auto badge = Wide(Text(row, "badge"));
  const bool title = style == "eewTitle";
  const bool info_title = style == "infoTitle";
  const bool japanese = Flag(row, "japanese");
  const bool jma_intensity = japanese && !badge.empty();
  const bool info = info_title || style == "info" || style == "infoDetail";
  const bool eew_text_block = !title && !info;
  const bool left_aligned =
      info_title || style == "info" || style == "infoDetail" ||
      style == "eewBody" || style == "jmaAreas" || style == "eewDetail";
  const wchar_t* family_name = japanese ? L"Yu Gothic UI" : L"Microsoft YaHei UI";
  const float size = title ? 28.0f
                           : (info_title || style == "info" ||
                              style == "eewBody")
                               ? 23.0f
                               : 20.0f;
  FontFamily custom_family(family_name);
  const auto* family = custom_family.GetLastStatus() == Ok
                           ? &custom_family
                           : FontFamily::GenericSansSerif();
  Font font(family, size, FontStyleBold, UnitPixel);
  StringFormat format;
  format.SetAlignment(left_aligned ? StringAlignmentNear
                                  : StringAlignmentCenter);
  RectF measured;
  const float block_width =
      eew_text_block ? std::min(394.0f, width - 32.0f) : width - 32.0f;
  const float block_x = content_left + (width - block_width) / 2.0f;
  const float badge_width = badge.empty() ? 0.0f : 110.0f;
  const float text_width = block_width - badge_width;
  const float x = block_x + badge_width;
  graphics.MeasureString(text.c_str(), -1, &font,
                         RectF(0, 0, text_width, 1024.0f), &format, &measured);
  const float single_line_height = std::ceil(size * 1.35f);
  const float height = std::max(single_line_height, std::ceil(measured.Height));
  if (!Flag(row, "hidden")) {
    const RectF area(x, y + 4.0f, text_width, height + 4.0f);
    if (title) {
      const float banner_width = std::min(width - 16.0f, measured.Width + 32.0f);
      SolidBrush red(Color(255, 219, 16, 23));
      graphics.FillRectangle(&red, content_left + (width - banner_width) / 2.0f,
                             y,
                             banner_width, height + 8.0f);
    }
    if (!badge.empty()) {
      SolidBrush green(Color(255, 8, 134, 45));
      SolidBrush white(Color(255, 255, 255, 255));
      const float badge_height = jma_intensity ? single_line_height : height;
      const RectF badge_area(block_x, y + 4.0f, badge_width - 8.0f,
                             badge_height);
      StringFormat badge_format;
      badge_format.SetAlignment(StringAlignmentCenter);
      if (jma_intensity) {
        badge_format.SetFormatFlags(StringFormatFlagsNoWrap);
      }
      graphics.FillRectangle(&green, badge_area);
      graphics.DrawString(badge.c_str(), -1, &font, badge_area, &badge_format,
                          &white);
    }
    GraphicsPath glyphs;
    glyphs.AddString(text.c_str(), -1, family, FontStyleBold, size, area,
                     &format);
    if (!title) {
      Pen outline(Color(225, 0, 0, 0), 3.0f);
      outline.SetLineJoin(LineJoinRound);
      graphics.DrawPath(&outline, &glyphs);
    }
    SolidBrush white(Color(255, 255, 255, 255));
    graphics.FillPath(&white, &glyphs);
  }
  y += height + 8.0f;
}

}  // namespace

ExternalSubtitleWindow::~ExternalSubtitleWindow() {
  if (window_) DestroyWindow(window_);
  if (graphics_token_) Gdiplus::GdiplusShutdown(graphics_token_);
}

bool ExternalSubtitleWindow::Present(HWND main_window,
                                     const flutter::EncodableList& lines) {
  if (!graphics_token_) {
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&graphics_token_, &input, nullptr) !=
        Gdiplus::Ok) {
      return false;
    }
  }
  if (!window_) {
    const auto module = GetModuleHandle(nullptr);
    WNDCLASSW definition{};
    definition.hInstance = module;
    definition.lpfnWndProc = DefWindowProcW;
    definition.lpszClassName = kWindowClass;
    if (!RegisterClassW(&definition) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return false;
    }
    // An unowned, titled top-level window remains selectable in OBS. Avoid
    // WS_EX_TOOLWINDOW, which capture pickers can omit.
    // WS_DISABLED keeps this display-only window out of input handling.
    // WS_EX_NOACTIVATE prevented Windows Graphics Capture on the Win10 host.
    window_ = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST,
                              kWindowClass, kWindowTitle, WS_POPUP | WS_DISABLED,
                              0, 0, 1, 1, nullptr, nullptr, module, nullptr);
    if (!window_) return false;
  }

  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfo(MonitorFromWindow(main_window, MONITOR_DEFAULTTONEAREST),
                      &monitor)) {
    return false;
  }
  const auto screen = monitor.rcMonitor;
  const auto work = monitor.rcWork;
  const UINT dpi = GetDpiForWindow(main_window);
  const float scale = dpi ? static_cast<float>(dpi) / 96.0f : 1.0f;
  // OBS captures a stable, monitor-sized surface. Place the captions within
  // the work area so a taskbar does not cover them on the desktop.
  const LONG width = screen.right - screen.left;
  const LONG height = screen.bottom - screen.top;
  if (width <= 0 || height <= 0) return false;
  const LONG top =
      work.top + static_cast<LONG>(std::lround(kSubtitleTopMargin * scale));
  if (work.right <= work.left || work.bottom <= top) return false;

  const HDC memory = CreateCompatibleDC(nullptr);
  if (!memory) return false;
  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  const HBITMAP dib = CreateDIBSection(memory, &bitmap_info, DIB_RGB_COLORS,
                                       &bits, nullptr, 0);
  if (!dib) {
    DeleteDC(memory);
    return false;
  }
  {
    Gdiplus::Bitmap pixels(width, height, width * 4, PixelFormat32bppPARGB,
                           static_cast<BYTE*>(bits));
    Gdiplus::Graphics graphics(&pixels);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.ScaleTransform(scale, scale);
    const float work_left = (work.left - screen.left) / scale;
    const float work_width = (work.right - work.left) / scale;
    const float caption_top = (top - screen.top) / scale;
    const float work_bottom = (work.bottom - screen.top) / scale;
    const float content_width =
        std::min(kSubtitleWidth, work_width - kInfoLeftMargin * 2.0f);
    const float eew_left = work_left + (work_width - content_width) / 2.0f;
    const float info_left = work_left + kInfoLeftMargin;
    float eew_body_height = 0.0f;
    for (const auto& encoded : lines) {
      const auto* row = std::get_if<flutter::EncodableMap>(&encoded);
      if (!row) continue;
      const auto style = Text(*row, "style");
      if (style == "belowEew" || style == "gap" || style == "eewTitle") {
        continue;
      }
      if (style == "infoTitle" || style == "info" || style == "infoDetail") {
        continue;
      }
      eew_body_height += MeasureLineHeight(graphics, *row, content_width);
    }
    const float eew_body_top =
        std::max(caption_top, work_bottom - kEewBottomMargin - eew_body_height);
    float eew_y = caption_top;
    float info_y = caption_top;
    bool eew_title_seen = false;
    for (const auto& encoded : lines) {
      const auto* row = std::get_if<flutter::EncodableMap>(&encoded);
      if (!row) continue;
      const auto style = Text(*row, "style");
      if (style == "belowEew") continue;
      if (style == "gap") {
        info_y += 6.0f;
        continue;
      }
      const bool info = style == "infoTitle" || style == "info" ||
                        style == "infoDetail";
      if (!info && style == "eewTitle") {
        DrawLine(graphics, *row, eew_left, content_width, eew_y);
        eew_y = eew_body_top;
        eew_title_seen = true;
      } else {
        if (!info && !eew_title_seen) eew_y = eew_body_top;
        DrawLine(graphics, *row, info ? info_left : eew_left, content_width,
                 info ? info_y : eew_y);
      }
    }
  }

  const HGDIOBJ old_bitmap = SelectObject(memory, dib);
  POINT position{screen.left, screen.top};
  POINT source{};
  SIZE size{width, height};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  const BOOL drawn = UpdateLayeredWindow(window_, nullptr, &position, &size,
                                         memory, &source, 0, &blend, ULW_ALPHA);
  SelectObject(memory, old_bitmap);
  DeleteObject(dib);
  DeleteDC(memory);
  if (drawn) ShowWindow(window_, SW_SHOWNOACTIVATE);
  return drawn != FALSE;
}

void ExternalSubtitleWindow::Hide() {
  if (window_) ShowWindow(window_, SW_HIDE);
}
