import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'native_station_core_library_io.dart';
import 'native_ka_history_io.dart';

/// Thin projection bridge. All maxima, ties, region assignment, sorting and
/// retained summary state belong to the native owner. Buffers are reused and
/// returned projections own their memory before any subsequent native call.
final class NativeStationSummary implements Finalizable {
  NativeStationSummary() {
    _owner = _bindings.create();
    if (_owner == nullptr) {
      throw StateError('Station summary allocation failed');
    }
    _finalizer.attach(this, _owner, detach: this);
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _bindings = _Bindings();
  static final _finalizer = NativeFinalizer(_bindings.destroyPointer);
  static final _emptyNumbers = Float64List(0);
  static final _emptyOffsets = Uint32List(0);
  static final _emptyLevels = Int32List(0);
  static final _emptyActive = Uint8List(0);
  static Map<String, int> get diagnostics => {
    'sessions': _bindings.sessions(),
    'calls': _bindings.calls(),
    'rows': _bindings.rows(),
  };
  late final Pointer<Void> _owner;
  StationCoreBuffer? _numbers, _text, _offsets;
  bool _disposed = false;

  void _check() {
    if (_disposed) throw StateError('Station summary disposed');
  }

  Float64List _input(int length) {
    if (_numbers == null || _numbers!.length < length * 8) {
      _numbers?.dispose();
      _numbers = StationCoreBuffer(length * 8);
      // Some networks use only selected columns. Initialize the complete
      // allocation once, so Rust never copies indeterminate unused fields.
      _numbers!.pointer
          .asTypedList(_numbers!.length)
          .fillRange(0, _numbers!.length, 0);
    }
    return length == 0
        ? _emptyNumbers
        : _numbers!.pointer.cast<Double>().asTypedList(length);
  }

  void update(
    int kind,
    int count,
    void Function(Float64List) write, {
    List<String> codes = const [],
    List<String> regions = const [],
    bool reuseText = false,
  }) {
    _check();
    if (count < 0 ||
        count > 1000000 ||
        kind < 0 ||
        kind > 5 ||
        (codes.isNotEmpty && codes.length != count) ||
        (regions.isNotEmpty && regions.length != count)) {
      throw ArgumentError('Station summary frame layout');
    }
    write(_input(count * 5));
    if (reuseText) {
      final status = _bindings.update(
        _owner,
        kind,
        _numbers!.pointer.cast(),
        count,
        nullptr,
        0,
        nullptr,
      );
      if (status != 0) {
        throw StateError('Station summary catalogue reuse failed ($status)');
      }
      return;
    }
    if (_offsets == null || _offsets!.length < count * 16) {
      _offsets?.dispose();
      _offsets = StationCoreBuffer(count * 16);
    }
    // Do not create a zero-length external view. Switching this call site
    // from empty to nonempty can crash the Windows Debug JIT on the first
    // Uint32 write; keep empty display frames in an owned empty Dart list.
    final offsets = count == 0
        ? _emptyOffsets
        : _offsets!.pointer.cast<Uint32>().asTypedList(count * 4);
    final units = <int>[];
    for (var i = 0; i < count; i++) {
      final code = codes.isEmpty ? '' : codes[i];
      final region = regions.isEmpty ? '' : regions[i];
      offsets[i * 4] = units.length;
      offsets[i * 4 + 1] = code.length;
      units.addAll(code.codeUnits);
      offsets[i * 4 + 2] = units.length;
      offsets[i * 4 + 3] = region.length;
      units.addAll(region.codeUnits);
    }
    if (_text == null || _text!.length < units.length * 2) {
      _text?.dispose();
      _text = StationCoreBuffer(units.length * 2);
    }
    if (units.isNotEmpty) {
      _text!.pointer.cast<Uint16>().asTypedList(units.length).setAll(0, units);
    }
    final status = _bindings.update(
      _owner,
      kind,
      _numbers!.pointer.cast(),
      count,
      _text!.pointer.cast(),
      units.length,
      _offsets!.pointer.cast(),
    );
    if (status != 0) {
      throw StateError('Station summary update failed ($status)');
    }
  }

  void cells(int count, void Function(Float64List) write) {
    _check();
    if (count < 0 || count > 1000000) throw ArgumentError.value(count);
    write(_input(count * 3));
    final status = _bindings.cells(_owner, _numbers!.pointer.cast(), count);
    if (status != 0) throw StateError('Station summary cells failed ($status)');
  }

  void niedLevels(int count, void Function(Int32List) write) {
    _check();
    if (count < 0 || count > 1000000) throw ArgumentError.value(count);
    _input(count); // Reuse the aligned native input allocation (8 bytes/row).
    write(
      count == 0
          ? _emptyLevels
          : _numbers!.pointer.cast<Int32>().asTypedList(count * 2),
    );
    final status = _bindings.niedLevels(
      _owner,
      _numbers!.pointer.cast(),
      count,
    );
    if (status != 0) {
      throw StateError('Station summary NIED levels failed ($status)');
    }
  }

  List<int> get indices {
    _check();
    return List<int>.of(_bindings.indices(_owner).asTypedList(17));
  }

  void niedKaResults(
    NativeKaHistorySession producer,
    void Function(Uint8List) writeActive,
  ) {
    _check();
    _input((producer.count + 7) ~/ 8);
    writeActive(
      producer.count == 0
          ? _emptyActive
          : _numbers!.pointer.asTypedList(producer.count),
    );
    producer.withNativeResults((results, count) {
      final status = _bindings.niedKaResults(
        _owner,
        results,
        _numbers!.pointer,
        count,
      );
      if (status != 0) {
        throw StateError('Station summary native KA results failed ($status)');
      }
    });
  }

  Int32List? _indicesView;

  /// Bind display fields synchronously. The borrowed indices must not escape
  /// the callback; unlike [indices], this does not allocate a vector per tick.
  T readIndices<T>(T Function(List<int>) bind) {
    _check();
    return bind(_indicesView ??= _bindings.indices(_owner).asTypedList(17));
  }

  List<(String, int)> get areas {
    _check();
    return using((arena) {
      final length = arena<Size>();
      final rank = arena<Int32>();
      return List.generate(_bindings.areaCount(_owner), (i) {
        final text = _bindings.area(_owner, i, length, rank);
        if (text == nullptr) throw StateError('Station summary area missing');
        return (
          length.value == 0
              ? ''
              : String.fromCharCodes(text.asTypedList(length.value)),
          rank.value,
        );
      }, growable: false);
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    _bindings.destroy(_owner);
    _indicesView = null;
    _numbers?.dispose();
    _text?.dispose();
    _offsets?.dispose();
    _numbers = _text = _offsets = null;
  }
}

final class _Bindings {
  _Bindings() {
    final lib = StationCoreLibrary.library;
    if (lib.lookupFunction<Uint32 Function(), int Function()>(
          'rq_station_summary_abi_version',
        )() !=
        1) {
      throw StateError('Unsupported station summary ABI');
    }
    create = lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'rq_station_summary_create',
        );
    destroy = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('rq_station_summary_destroy');
    destroyPointer = lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
      'rq_station_summary_destroy',
    );
    update = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Uint32,
            Pointer<Double>,
            Size,
            Pointer<Uint16>,
            Size,
            Pointer<Uint32>,
          ),
          int Function(
            Pointer<Void>,
            int,
            Pointer<Double>,
            int,
            Pointer<Uint16>,
            int,
            Pointer<Uint32>,
          )
        >('rq_station_summary_update');
    cells = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Double>, Size),
          int Function(Pointer<Void>, Pointer<Double>, int)
        >('rq_station_summary_cells');
    niedLevels = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Int32>, Size),
          int Function(Pointer<Void>, Pointer<Int32>, int)
        >('rq_station_summary_nied_levels');
    indices = lib
        .lookupFunction<
          Pointer<Int32> Function(Pointer<Void>),
          Pointer<Int32> Function(Pointer<Void>)
        >('rq_station_summary_indices');
    areaCount = lib
        .lookupFunction<
          Size Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('rq_station_summary_area_count');
    area = lib
        .lookupFunction<
          Pointer<Uint16> Function(
            Pointer<Void>,
            Size,
            Pointer<Size>,
            Pointer<Int32>,
          ),
          Pointer<Uint16> Function(
            Pointer<Void>,
            int,
            Pointer<Size>,
            Pointer<Int32>,
          )
        >('rq_station_summary_area');
    sessions = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_summary_sessions',
    );
    calls = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_summary_calls',
    );
    rows = lib.lookupFunction<Uint64 Function(), int Function()>(
      'rq_station_summary_rows',
    );
  }
  late final Pointer<Void> Function() create;
  late final void Function(Pointer<Void>) destroy;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>>
  destroyPointer;
  late final int Function(
    Pointer<Void>,
    int,
    Pointer<Double>,
    int,
    Pointer<Uint16>,
    int,
    Pointer<Uint32>,
  )
  update;
  late final int Function(Pointer<Void>, Pointer<Double>, int) cells;
  late final int Function(Pointer<Void>, Pointer<Int32>, int) niedLevels;
  late final niedKaResults = StationCoreLibrary.library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Uint8>, Size),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Uint8>, int)
      >('rq_station_summary_nied_ka_results');
  late final Pointer<Int32> Function(Pointer<Void>) indices;
  late final int Function(Pointer<Void>) areaCount;
  late final Pointer<Uint16> Function(
    Pointer<Void>,
    int,
    Pointer<Size>,
    Pointer<Int32>,
  )
  area;
  late final int Function() sessions, calls, rows;
}
