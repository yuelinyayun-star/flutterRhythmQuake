#pragma once

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>

#include <cstdint>
#include <memory>
#include <mutex>
#include "platform_dispatcher.h"

using namespace flutter;

template <typename T = EncodableValue>
class EventStreamHandler : public StreamHandler<T> {
 public:
  explicit EventStreamHandler(std::shared_ptr<PlatformDispatcher> dispatcher)
      : dispatcher_(std::move(dispatcher)), state_(std::make_shared<State>()) {}

  ~EventStreamHandler() override { Cancel(); }

  void Success(std::unique_ptr<T> data) {
    auto value = std::shared_ptr<T>(std::move(data));
    Send([value](EventSink<T>& sink) { sink.Success(*value); });
  }

  void Error(const std::string& error_code,
             const std::string& error_message,
             const T& error_details) {
    Send([error_code, error_message, error_details](EventSink<T>& sink) {
      sink.Error(error_code, error_message, error_details);
    });
  }

 protected:
  std::unique_ptr<StreamHandlerError<T>> OnListenInternal(
      const T* arguments,
      std::unique_ptr<EventSink<T>>&& events) override {
    std::lock_guard<std::mutex> lock(state_->mutex);
    ++state_->generation;
    state_->sink = std::move(events);
    return nullptr;
  }

  std::unique_ptr<StreamHandlerError<T>> OnCancelInternal(
      const T* arguments) override {
    Cancel();
    return nullptr;
  }

 private:
  struct State {
    std::mutex mutex;
    std::unique_ptr<EventSink<T>> sink;
    uint64_t generation = 0;
  };

  void Cancel() {
    std::lock_guard<std::mutex> lock(state_->mutex);
    ++state_->generation;
    state_->sink.reset();
  }

  void Send(std::function<void(EventSink<T>&)> send) {
    uint64_t generation;
    {
      std::lock_guard<std::mutex> lock(state_->mutex);
      if (!state_->sink) return;
      generation = state_->generation;
    }
    std::weak_ptr<State> weak_state = state_;
    dispatcher_->Post([weak_state, generation, send = std::move(send)] {
      auto state = weak_state.lock();
      if (!state) return;
      std::lock_guard<std::mutex> lock(state->mutex);
      if (state->sink && state->generation == generation) send(*state->sink);
    });
  }

  std::shared_ptr<PlatformDispatcher> dispatcher_;
  std::shared_ptr<State> state_;
};
