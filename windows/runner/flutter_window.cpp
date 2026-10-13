#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The supplied studio design includes its own Flutter title bar. Keep native
  // resizing while removing the duplicate OS caption; all controls use Win32.
  const HWND host = GetHandle();
  SetWindowLongPtr(host, GWL_STYLE, GetWindowLongPtr(host, GWL_STYLE) & ~WS_CAPTION);
  SetWindowPos(host, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "aurora/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this, host](const auto& call, auto result) {
        if (call.method_name() == "minimize") {
          ShowWindow(host, SW_MINIMIZE);
        } else if (call.method_name() == "maximize") {
          ShowWindow(host, IsZoomed(host) ? SW_RESTORE : SW_MAXIMIZE);
        } else if (call.method_name() == "close") {
          PostMessage(host, WM_CLOSE, 0, 0);
        } else if (call.method_name() == "guardClose") {
          const auto* enabled = call.arguments()
              ? std::get_if<bool>(call.arguments()) : nullptr;
          close_guard_enabled_ = enabled && *enabled;
        } else if (call.method_name() == "drag") {
          ReleaseCapture();
          PostMessage(host, WM_NCLBUTTONDOWN, HTCAPTION, GetMessagePos());
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      });


  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Native audio tests can keep their window hidden without stealing focus.
    wchar_t hidden[2] = {};
    if (GetEnvironmentVariableW(L"AURORA_HIDE_WINDOW", hidden, 2) != 1 ||
        hidden[0] != L'1') {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Cover both Aurora's title bar and system close shortcuts such as Alt+F4.
  if (message == WM_CLOSE && close_guard_enabled_ && !close_confirmed_ &&
      window_channel_) {
    if (!close_request_pending_) {
      close_request_pending_ = true;
      window_channel_->InvokeMethod("confirmClose", nullptr,
          std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [this, hwnd](const flutter::EncodableValue* result) {
                close_request_pending_ = false;
                const auto* accepted = result ? std::get_if<bool>(result) : nullptr;
                if (accepted && *accepted) {
                  close_confirmed_ = true;
                  PostMessage(hwnd, WM_CLOSE, 0, 0);
                }
              },
              [this](const std::string&, const std::string&, const flutter::EncodableValue*) {
                close_request_pending_ = false;
              },
              [this]() { close_request_pending_ = false; }));
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
