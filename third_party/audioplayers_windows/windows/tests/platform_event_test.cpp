#include "../event_stream_handler.h"

#include <cassert>
#include <iostream>
#include <thread>
#include <vector>

struct Received {
  std::vector<int> values;
  int errors = 0;
  int destroyed = 0;
  DWORD platform_thread = GetCurrentThreadId();
};

class RecordingSink : public flutter::EventSink<flutter::EncodableValue> {
 public:
  explicit RecordingSink(Received& received) : received_(received) {}
  ~RecordingSink() override { ++received_.destroyed; }

 protected:
  void SuccessInternal(const flutter::EncodableValue* value) override {
    assert(GetCurrentThreadId() == received_.platform_thread);
    received_.values.push_back(std::get<int>(*value));
  }
  void ErrorInternal(const std::string& code, const std::string& message,
                     const flutter::EncodableValue* details) override {
    assert(GetCurrentThreadId() == received_.platform_thread);
    assert(code == "test-error");
    ++received_.errors;
  }
  void EndOfStreamInternal() override {}

 private:
  Received& received_;
};

void Pump() {
  MSG message;
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
}

int main() {
  Received received;
  auto dispatcher = std::make_shared<PlatformDispatcher>();
  auto handler = std::make_unique<EventStreamHandler<>>(dispatcher);
  handler->OnListen(nullptr, std::make_unique<RecordingSink>(received));
  std::thread worker([&] {
    for (int i = 0; i < 100; ++i) {
      handler->Success(std::make_unique<flutter::EncodableValue>(i));
    }
    handler->Error("test-error", "message", flutter::EncodableValue(1));
  });
  worker.join();
  assert(received.values.empty());
  Pump();
  assert(received.values.size() == 100 && received.errors == 1);
  for (int i = 0; i < 100; ++i) assert(received.values[i] == i);

  // Cancellation frees the sink and prevents queued events reaching the next
  // subscription, even when an old media callback was already queued.
  handler->Success(std::make_unique<flutter::EncodableValue>(100));
  handler->OnCancel(nullptr);
  assert(received.destroyed == 1);
  handler->OnListen(nullptr, std::make_unique<RecordingSink>(received));
  Pump();
  assert(received.values.size() == 100);
  handler->Success(std::make_unique<flutter::EncodableValue>(101));
  Pump();
  assert(received.values.back() == 101);

  // Disposal while events are queued must neither send nor dereference freed
  // stream-handler state.
  handler->Success(std::make_unique<flutter::EncodableValue>(102));
  handler.reset();
  Pump();
  assert(received.values.size() == 101 && received.destroyed == 2);
  bool called_after_shutdown = false;
  dispatcher->Post([&] { called_after_shutdown = true; });
  dispatcher.reset();
  Pump();
  assert(!called_after_shutdown);
  std::cout << "PASS: worker events, platform thread, order, cancellation, "
               "resubscribe, handler disposal, dispatcher shutdown\n";
}
