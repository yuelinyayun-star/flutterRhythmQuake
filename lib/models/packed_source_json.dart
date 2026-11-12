part of 'source_payload.dart';

/// Independently owned, deeply immutable JSON tree produced by the native
/// decoder. No native pointer or mutable receive buffer survives in this tree.
final class PackedSourceJson {
  // Takes sole ownership of a freshly copied buffer; callers must not retain
  // mutable aliases. The native adapter copies before calling this constructor.
  PackedSourceJson(this._bytes) : _data = ByteData.sublistView(_bytes) {
    final layout = _data.getUint32(0, Endian.little);
    final nodes = layout & 0x7fffffff;
    _header = layout & 0x80000000 != 0 ? 24 : 16;
    final byteCount = _header == 24 ? _data.getUint32(16, Endian.little) : 0;
    final children = _data.getUint32(4, Endian.little);
    final units = _data.getUint32(8, Endian.little);
    final numbers = _data.getUint32(12, Endian.little);
    _children = _header + nodes * 16;
    _strings = _children + children * 4;
    _strings8 = _strings + units * 2;
    _numbers = (_strings8 + byteCount + 7) & ~7;
    if (nodes == 0 || _numbers + numbers * 8 != _bytes.length) {
      throw const FormatException('Invalid packed JSON layout');
    }
  }

  final Uint8List _bytes;
  final ByteData _data;
  late final int _header, _children, _strings, _strings8, _numbers;
  final _texts = <int, String>{};
  dynamic get root => _value(0);
  int _offset(int id) => _header + id * 16;
  int _aux(int id) => _data.getUint32(_offset(id) + 4, Endian.little);
  int _count(int id) => _data.getUint32(_offset(id) + 8, Endian.little);
  int _child(int id, int index) =>
      _data.getUint32(_offset(id), Endian.little) >= 9
      ? _aux(id) + index
      : _data.getUint32(_children + (_aux(id) + index) * 4, Endian.little);
  String _text(int id) => _texts.putIfAbsent(id, () {
    if (_data.getUint32(_offset(id), Endian.little) == 11) {
      final start = _strings8 + _aux(id);
      final bytes = Uint8List.sublistView(_bytes, start, start + _count(id));
      final text = utf8.decode(bytes);
      // This is JSON field content, not a transport BOM. Utf8Decoder consumes
      // one leading BOM, so restore it for both keys and values.
      return bytes.length >= 3 &&
              bytes[0] == 0xef &&
              bytes[1] == 0xbb &&
              bytes[2] == 0xbf
          ? '\uFEFF$text'
          : text;
    }
    final start = _strings + _aux(id) * 2;
    final count = _count(id);
    return String.fromCharCodes(
      Endian.host == Endian.little
          ? Uint16List.view(_bytes.buffer, _bytes.offsetInBytes + start, count)
          : List.generate(
              count,
              (i) => _data.getUint16(start + i * 2, Endian.little),
            ),
    );
  });
  dynamic _value(int id) {
    final offset = _offset(id);
    return switch (_data.getUint32(offset, Endian.little)) {
      0 => null,
      1 => false,
      2 => true,
      3 => _data.getInt64(offset + 8, Endian.little),
      4 => _data.getFloat64(offset + 8, Endian.little),
      5 => _text(id),
      6 => _PackedJsonList(this, id),
      7 => _PackedJsonMap(this, id),
      8 => PackedJsonNumberList(this, id),
      9 => PackedJsonNumberList(this, id),
      10 => _PackedJsonList(this, id),
      11 => _text(id),
      _ => throw const FormatException('Invalid packed JSON tag'),
    };
  }
}

/// Opaque immutable transport for a native-owned replay reader. Root selection
/// preserves the original tree; Dart never expands/re-encodes station values.
(Uint8List, int)? packedSourceJsonTransport(Map<String,dynamic> value) =>
    value is _PackedJsonMap ? (value._tree._bytes, value._id) : null;

sealed class _PackedSourceJsonValue {}

base class _PackedJsonList extends ListBase<dynamic>
    implements _PackedSourceJsonValue {
  _PackedJsonList(this._tree, this._id) : length = _tree._count(_id);
  final PackedSourceJson _tree;
  final int _id;
  @override
  final int length;
  @override
  dynamic operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _tree._value(_tree._child(_id, index));
  }

  @override
  set length(int value) => throw UnsupportedError('Frozen packed JSON');
  @override
  void operator []=(int index, dynamic value) =>
      throw UnsupportedError('Frozen packed JSON');
}

/// Original integer/double elements remain available through the List API.
/// The independently owned numeric view is the original toDouble conversion,
/// validated in Rust once for all consumers of this array.
final class PackedJsonNumberList extends _PackedJsonList {
  PackedJsonNumberList(super._tree, super._id);
  int get storageBytes => _tree._bytes.length;
  List<double>? doublesInRange(double minimum, double maximum) {
    final index = _tree._data.getUint32(_tree._offset(_id) + 12, Endian.little);
    final offset = _tree._numbers + index * 8;
    if (_tree._data.getFloat64(offset + 16, Endian.little) != 1 ||
        _tree._data.getFloat64(offset, Endian.little) < minimum ||
        _tree._data.getFloat64(offset + 8, Endian.little) > maximum) {
      return null;
    }
    return Float64List.view(
      _tree._bytes.buffer,
      _tree._bytes.offsetInBytes + offset + 24,
      length,
    ).asUnmodifiableView();
  }
}

final class _PackedJsonMap extends MapBase<String, dynamic>
    implements _PackedSourceJsonValue {
  _PackedJsonMap(this._tree, this._id);
  final PackedSourceJson _tree;
  final int _id;
  late final Map<String, int> _indices = _buildIndex();
  Map<String, int> _buildIndex() {
    final indices = <String, int>{};
    for (var i = 0; i < _tree._count(_id); i += 2) {
      indices[_tree._text(_tree._child(_id, i))] = _tree._child(_id, i + 1);
    }
    return indices;
  }

  @override
  Iterable<String> get keys => _indices.keys;
  @override
  int get length => _indices.length;
  @override
  bool containsKey(Object? key) => _indices.containsKey(key);
  @override
  dynamic operator [](Object? key) {
    final id = _indices[key];
    return id == null ? null : _tree._value(id);
  }

  @override
  void forEach(void Function(String, dynamic) action) {
    _indices.forEach((key, id) => action(key, _tree._value(id)));
  }

  @override
  void operator []=(String key, dynamic value) =>
      throw UnsupportedError('Frozen packed JSON');
  @override
  dynamic remove(Object? key) => throw UnsupportedError('Frozen packed JSON');
  @override
  void clear() => throw UnsupportedError('Frozen packed JSON');
}
