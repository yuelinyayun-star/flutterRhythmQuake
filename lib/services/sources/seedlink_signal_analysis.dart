// Display-only adaptation of GlobalQuake 0.11.0 BetterAnalysis/AbstractStation.
// Copyright (c) 2023 xspanger3770
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:typed_data';
import 'package:iirjdart/butterworth.dart';
import 'package:iirjdart/direct_form_2.dart';
import '../../core/seedlink_activity.dart';

/// Constant-size state per NSLC. Never stores or changes the input samples.
/// Uses observation seconds, rather than arrival-clock seconds, so packet
/// bursts and replay speed cannot change the history window.
class SeedLinkSignalAnalysis {
  _BandPass? _filter;
  double _rate = 0;
  int? _lastMicros;
  int _progress = 0, _offsetCount = 0, _ratioCount = 0, _records = 0;
  double _offsetSum = 0, _ratioSum = 0, _offset = 0;
  double _short = 0, _medium = 0, _third = 0, _long = 0;
  int _eventTimer = 0;
  int? _eventStart;
  bool _ready = false, _hasPrevious = false;
  double _peak = 0;
  bool _resetPeak = true;
  int? _second;
  // Upstream adds a value and removes the oldest at size >= 60: 59 entries.
  final _history = Float64List(59);
  int _head = 0, _count = 0;
  double _historyMax = 0;
  SeedLinkActivity _snapshot = const SeedLinkActivity();
  SeedLinkActivity get snapshot => _snapshot;

  void _reset(double rate) {
    _rate = rate;
    _filter = rate.isFinite && rate > 10 ? _BandPass(rate) : null;
    _progress = _offsetCount = _ratioCount = _records = 0;
    _offsetSum = _ratioSum = _offset = 0;
    _short = _medium = _third = _long = 0;
    _eventStart = null;
    _eventTimer = 0;
    _ready = _hasPrevious = false;
    _peak = _historyMax = 0;
    _resetPeak = true;
    _head = _count = 0;
    _second = null;
    _snapshot = const SeedLinkActivity();
  }

  SeedLinkActivity accept(List<int> samples, double rate, DateTime start) {
    if (samples.isEmpty || !rate.isFinite || rate <= 0) return _snapshot;
    final begin = start.microsecondsSinceEpoch;
    final step = 1000000 / rate;
    final end = begin + ((samples.length - 1) * step).round();
    // Duplicate/late records must not contaminate a newer baseline.
    if (_lastMicros != null && end <= _lastMicros!) return _snapshot;
    if (_filter == null ||
        (_rate - rate).abs() > .2 ||
        (_lastMicros != null && begin - _lastMicros! > 1000000)) {
      _reset(rate);
    }
    if (_filter == null) {
      _lastMicros = end;
      return _snapshot;
    }
    var filter = _filter!;
    if (_ready) _records++;
    for (var i = 0; i < samples.length; i++) {
      final micros = begin + (i * step).round();
      if (_lastMicros != null && micros <= _lastMicros!) continue;
      _lastMicros = micros;
      final time = micros ~/ 1000;
      final second = micros ~/ 1000000;
      if (_second != null && second != _second) _finishSecond();
      _second = second;
      final v = samples[i];
      if (!_ready) {
        if (_progress <= 4 * rate) {
          _offsetSum += v;
          _offsetCount++;
          if (_progress >= rate) {
            _ratioSum += filter.filter(v - _offsetSum / _offsetCount).abs();
            _ratioCount++;
            _long = _ratioSum / _ratioCount;
          }
        } else if (_progress <= 14 * rate) {
          final value = filter.filter(v - _offsetSum / _offsetCount).abs();
          _long -= (_long - value) / (rate * 6);
        } else {
          _offset = _offsetSum / _offsetCount;
          _short = _medium = _third = _long;
          _long *= .75;
          _ready = true;
        }
        _progress++;
        continue;
      }
      final value = filter.filter(v - _offset).abs();
      _short -= (_short - value) / (rate * .5);
      _medium -= (_medium - value) / (rate * 6);
      _third -= (_third - value) / (rate * 30);
      if (_short / _long < 4) _long -= (_long - value) / (rate * 200);
      final ratio = _short / _long;
      if (_eventStart == null &&
          _hasPrevious &&
          _short / _third > 3 &&
          ((ratio >= 4.75 * 1.3 && time - _eventTimer > 200) ||
              (ratio >= 4.75 * 2.05 && time - _eventTimer > 100))) {
        _eventStart = time;
      }
      if (ratio < 4.75) _eventTimer = time;
      final eventStart = _eventStart;
      if (eventStart != null) {
        final duration = time - eventStart;
        if (duration >= 300000) {
          _reset(rate);
          filter = _filter!;
          continue;
        }
        if ((duration >= 7000 && _medium < _third * .95) ||
            (duration >= 1000 &&
                ((duration < 7500 && _short < _long * 1.25) ||
                    _short < _medium * .12))) {
          _eventStart = null;
        }
      }
      // A zero/invalid background has no meaningful ratio. Never invent one.
      if (ratio.isFinite && ratio >= 0 && (ratio > _peak || _resetPeak)) {
        _peak = ratio * 1.25;
        _resetPeak = false;
      }
      _hasPrevious = true;
    }
    final displayRatio = _ready && _records >= 3 && _historyMax > 0
        ? _historyMax
        : null;
    final event = _ready && _records >= 3 && _eventStart != null;
    if (_snapshot.ratio != displayRatio || _snapshot.event != event) {
      _snapshot = SeedLinkActivity(ratio: displayRatio, event: event);
    }
    return _snapshot;
  }

  void _finishSecond() {
    if (_peak <= 0 || !_peak.isFinite) return;
    final evicted = _history[_head];
    _history[_head] = _peak;
    _head = (_head + 1) % _history.length;
    if (_count < _history.length) _count++;
    if (_peak >= _historyMax) {
      _historyMax = _peak;
    } else if (evicted == _historyMax) {
      _historyMax = 0;
      for (var i = 0; i < _count; i++) {
        if (_history[i] > _historyMax) _historyMax = _history[i];
      }
    }
    _resetPeak = true;
  }
}

// iirj's actual Direct Form II processing; only the immutable filter design is
// shared. Each station retains its own three delay states, with no cross-talk.
class _BandPass {
  static final _designs = <double, Butterworth>{};
  final Butterworth design;
  final _a = DirectFormII(), _b = DirectFormII(), _c = DirectFormII();
  _BandPass(double rate) : design = _design(rate);

  static Butterworth _design(double rate) {
    final cached = _designs[rate];
    if (cached != null) return cached;
    final next = Butterworth()..bandPass(3, rate, 3.5, 3);
    // Malformed/variable rates must not grow a process-wide cache indefinitely.
    if (_designs.length == 32) _designs.remove(_designs.keys.first);
    return _designs[rate] = next;
  }

  double filter(double sample) => _c.process1(
    _b.process1(_a.process1(sample, design.getBiquad(0)), design.getBiquad(1)),
    design.getBiquad(2),
  );
}
