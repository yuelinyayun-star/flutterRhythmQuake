import 'dart:convert';
import 'dart:typed_data';

class _JavaObjectStreamDecoder {
  Uint8List _bytes = Uint8List(0);
  int _offset = 0;
  bool _headerRead = false;
  final List<dynamic> _handles = [];

  void reset() {
    _bytes = Uint8List(0);
    _offset = 0;
    _headerRead = false;
    _handles.clear();
  }

  List<_JavaObject> add(Uint8List chunk) {
    _bytes = Uint8List.fromList([..._bytes.sublist(_offset), ...chunk]);
    _offset = 0;
    final objects = <_JavaObject>[];
    while (true) {
      final mark = _offset;
      final handlesMark = List<dynamic>.of(_handles);
      try {
        if (!_headerRead) {
          if (_remaining < 4) break;
          final magic = _readU2();
          final version = _readU2();
          if (magic != 0xaced || version != 5) {
            throw FormatException('Invalid Java stream header');
          }
          _headerRead = true;
        }
        if (_remaining <= 0) break;
        final value = _readContent();
        if (value is _JavaObject) {
          objects.add(value);
        }
      } on _NeedMore {
        _offset = mark;
        _handles
          ..clear()
          ..addAll(handlesMark);
        break;
      }
    }
    if (_offset > 0) {
      _bytes = _bytes.sublist(_offset);
      _offset = 0;
    }
    return objects;
  }

  int get _remaining => _bytes.length - _offset;

  dynamic _readContent() {
    final tc = _readU1();
    switch (tc) {
      case 0x70:
        return null;
      case 0x71:
        return _handle(_readU4());
      case 0x72:
        return _readClassDescBody();
      case 0x73:
        return _readObjectBody();
      case 0x74:
        return _readNewString();
      case 0x75:
        return _readArrayBody();
      case 0x77:
        final len = _readU1();
        return _JavaBlockData(_readBytes(len));
      case 0x7a:
        final len = _readU4();
        return _JavaBlockData(_readBytes(len));
      case 0x79:
        _handles.clear();
        return _readContent();
      default:
        throw FormatException(
          'Unsupported Java serialization token 0x${tc.toRadixString(16)}',
        );
    }
  }

  _JavaClassDesc _readClassDesc() {
    final value = _readContent();
    if (value is _JavaClassDesc) return value;
    throw FormatException('Expected Java class descriptor');
  }

  _JavaClassDesc _readClassDescBody() {
    final className = _readUtf();
    _readI8();
    final desc = _JavaClassDesc(className);
    _handles.add(desc);
    desc.flags = _readU1();
    final fieldCount = _readU2();
    for (var i = 0; i < fieldCount; i++) {
      final typeCode = String.fromCharCode(_readU1());
      final name = _readUtf();
      String? typeName;
      if (typeCode == 'L' || typeCode == '[') {
        final type = _readContent();
        typeName = type?.toString();
      }
      desc.fields.add(_JavaField(typeCode, name, typeName));
    }
    while (true) {
      final tc = _readU1();
      if (tc == 0x78) break;
      _offset--;
      _readContent();
    }
    final superDesc = _readContent();
    if (superDesc is _JavaClassDesc) {
      desc.superDesc = superDesc;
    }
    return desc;
  }

  String _readNewString() {
    final text = _readUtf();
    _handles.add(text);
    return text;
  }

  _JavaObject _readObjectBody() {
    final desc = _readClassDesc();
    final object = _JavaObject(desc.className);
    _handles.add(object);
    for (final current in desc.hierarchy) {
      for (final field in current.fields) {
        object.fields[field.name] = _readField(field.typeCode);
      }
      if ((current.flags & 0x01) != 0) {
        object.customData[current.className] = _readCustomData();
      }
    }
    return object;
  }

  dynamic _readArrayBody() {
    final desc = _readClassDesc();
    final list = <dynamic>[];
    _handles.add(list);
    final length = _readU4();
    final type = desc.className.length > 1 ? desc.className[1] : 'L';
    for (var i = 0; i < length; i++) {
      list.add(_readField(type));
    }
    return list;
  }

  dynamic _readField(String typeCode) {
    switch (typeCode) {
      case 'B':
        return _readU1();
      case 'C':
        return _readU2();
      case 'D':
        return _readF8();
      case 'F':
        return _readF4();
      case 'I':
        return _readI4();
      case 'J':
        return _readI8();
      case 'S':
        return _readI2();
      case 'Z':
        return _readU1() != 0;
      case 'L':
      case '[':
        return _readContent();
      default:
        throw FormatException('Unsupported Java field type $typeCode');
    }
  }

  List<dynamic> _readCustomData() {
    final values = <dynamic>[];
    while (true) {
      final tc = _readU1();
      if (tc == 0x78) return values;
      _offset--;
      values.add(_readContent());
    }
  }

  dynamic _handle(int wireHandle) {
    final index = wireHandle - 0x7e0000;
    if (index < 0 || index >= _handles.length) {
      throw FormatException(
        'Invalid Java handle 0x${wireHandle.toRadixString(16)}',
      );
    }
    return _handles[index];
  }

  int _readU1() {
    if (_remaining < 1) throw const _NeedMore();
    return _bytes[_offset++];
  }

  int _readU2() {
    final b = _readBytes(2);
    return (b[0] << 8) | b[1];
  }

  int _readI2() {
    final value = _readU2();
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  int _readU4() {
    final b = _readBytes(4);
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  int _readI4() {
    final value = _readU4();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  int _readI8() {
    final b = _readBytes(8);
    var value = BigInt.zero;
    for (final byte in b) {
      value = (value << 8) | BigInt.from(byte);
    }
    if ((b[0] & 0x80) != 0) {
      value -= BigInt.one << 64;
    }
    return value.toInt();
  }

  double _readF4() {
    final b = _readBytes(4);
    return ByteData.sublistView(
      Uint8List.fromList(b),
    ).getFloat32(0, Endian.big);
  }

  double _readF8() {
    final b = _readBytes(8);
    return ByteData.sublistView(
      Uint8List.fromList(b),
    ).getFloat64(0, Endian.big);
  }

  String _readUtf() {
    final len = _readU2();
    return utf8.decode(_readBytes(len), allowMalformed: true);
  }

  List<int> _readBytes(int count) {
    if (_remaining < count) throw const _NeedMore();
    final out = _bytes.sublist(_offset, _offset + count);
    _offset += count;
    return out;
  }
}

class _JavaClassDesc {
  _JavaClassDesc(this.className);

  final String className;
  int flags = 0;
  final List<_JavaField> fields = [];
  _JavaClassDesc? superDesc;

  List<_JavaClassDesc> get hierarchy {
    final parent = superDesc;
    return [if (parent != null) ...parent.hierarchy, this];
  }
}

class _JavaField {
  const _JavaField(this.typeCode, this.name, this.typeName);

  final String typeCode;
  final String name;
  final String? typeName;
}

class _JavaObject {
  _JavaObject(this.className);

  final String className;
  final Map<String, dynamic> fields = {};
  final Map<String, List<dynamic>> customData = {};
}

/// A self-contained JSON representation of a decoded Java object graph.
/// References and non-finite numbers are tagged rather than discarded.
class _JavaPayloadSnapshot {
  final _references = Map<Object, int>.identity();

  dynamic encode(dynamic value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double) {
      return value.isFinite ? value : {'number': value.toString()};
    }
    final previousId = _references[value];
    if (previousId != null) return {'ref': previousId};
    final id = _references.length;
    _references[value as Object] = id;
    if (value is _JavaObject) {
      return {
        'id': id,
        'className': value.className,
        'fields': value.fields.map(
          (key, field) => MapEntry(key, encode(field)),
        ),
        if (value.customData.isNotEmpty)
          'customData': value.customData.map(
            (key, items) => MapEntry(key, encode(items)),
          ),
      };
    }
    if (value is List) {
      return {'id': id, 'items': value.map(encode).toList(growable: false)};
    }
    if (value is _JavaBlockData) {
      return {'id': id, 'blockDataBase64': base64Encode(value.bytes)};
    }
    if (value is _JavaClassDesc) {
      return {
        'id': id,
        'className': value.className,
        'flags': value.flags,
        'fields': [
          for (final field in value.fields)
            {
              'name': field.name,
              'typeCode': field.typeCode,
              'typeName': field.typeName,
            },
        ],
        'superDesc': encode(value.superDesc),
      };
    }
    throw FormatException(
      'Unsupported decoded Java value ${value.runtimeType}',
    );
  }
}

class _JavaBlockData {
  const _JavaBlockData(this.bytes);

  final List<int> bytes;
}

class _NeedMore implements Exception {
  const _NeedMore();
}

class FrozenGlobalQuakeDecoder {
  int get pendingBytes => _decoder._bytes.length;
  final _decoder = _JavaObjectStreamDecoder();
  List<dynamic> add(Uint8List chunk) => [
    for (final packet in _decoder.add(chunk))
      _JavaPayloadSnapshot().encode(packet),
  ];
  void reset() => _decoder.reset();
}
