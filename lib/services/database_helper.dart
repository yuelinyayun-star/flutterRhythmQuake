import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/quake_message.dart';

/// 数据库辅助类
/// 
/// 该类提供SQLite数据库操作功能。
/// 用于持久化存储地震历史记录。
/// 
/// 主要功能：
/// - 创建和初始化数据库
/// - 插入地震记录（自动去重）
/// - 查询历史记录
/// - 清理过期数据
/// 
/// 数据库结构：
/// - 表名: history
/// - 主键: id (地震事件ID)
/// - 字段: location, magnitude, latitude, longitude, depth, originTime, maxIntensity, source
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  /// 数据库实例缓存
  static Database? _database;

  /// 获取数据库实例
  /// 
  /// 如果数据库未初始化，则先初始化
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  /// 
  /// 创建数据库文件和表结构
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'rhythm_quake.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE history(
            id TEXT PRIMARY KEY,
            location TEXT,
            magnitude REAL,
            latitude REAL,
            longitude REAL,
            depth REAL,
            originTime TEXT,
            maxIntensity INTEGER,
            source TEXT
          )
        ''');
      },
    );
  }

  /// 保存地震记录
  /// 
  /// 使用REPLACE策略，如果ID已存在则更新
  /// 
  /// [quake] 要保存的地震消息
  Future<void> insertQuake(QuakeMessage quake) async {
    final db = await database;
    await db.insert(
      'history',
      {
        'id': quake.eventId,
        'location': quake.location,
        'magnitude': quake.magnitude,
        'latitude': quake.latitude,
        'longitude': quake.longitude,
        'depth': quake.depth,
        'originTime': quake.originTime.toIso8601String(),
        'maxIntensity': quake.maxIntensity,
        'source': quake.source.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取最近的历史记录
  /// 
  /// 按发震时间降序排列
  /// 
  /// [limit] 返回记录数量限制，默认50条
  /// 返回地震消息列表
  Future<List<QuakeMessage>> getHistory({int limit = 50}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
        'history',
        orderBy: 'originTime DESC',
        limit: limit
    );

    return List.generate(maps.length, (i) {
      return QuakeMessage(
        eventId: maps[i]['id'],
        location: maps[i]['location'],
        magnitude: maps[i]['magnitude'],
        latitude: maps[i]['latitude'],
        longitude: maps[i]['longitude'],
        depth: maps[i]['depth'],
        originTime: DateTime.parse(maps[i]['originTime']),
        maxIntensity: maps[i]['maxIntensity'],
        source: _parseSourceType(maps[i]['source']),
      );
    });
  }

  /// 清理旧数据
  /// 
  /// 删除7天前的历史记录，防止数据库过大
  Future<void> cleanOldData() async {
    final db = await database;
    final String sevenDaysAgo = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    await db.delete(
      'history',
      where: 'originTime < ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  /// 解析数据源类型枚举
  /// 
  /// 从数据库字符串转换为QuakeSourceType枚举
  QuakeSourceType _parseSourceType(String sourceStr) {
    return QuakeSourceType.values.firstWhere(
      (e) => e.toString() == sourceStr,
      orElse: () => QuakeSourceType.wolfx,
    );
  }
}
