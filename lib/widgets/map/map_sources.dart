/// 中国地图数据源配置类
/// 
/// 该类定义了中国境内合规地图服务的URL模板。
/// 包含天地图和高德地图等符合中国法规的地图服务。
/// 
/// 地图合规说明：
/// - 天地图: 国家测绘地理信息局官方服务，国内最权威
/// - 高德地图: 符合中国法规的商业地图服务
/// 
/// 使用注意：
/// - 天地图需要申请API Key
/// - 国内使用需确保地图审图号合规
class ChinaMapSources {
  /// 天地图API密钥
  /// 需要在天地图官网申请: https://console.tianditu.gov.cn/
  static const String tdtKey = "fdeb3c8cb5ae72c62b04c8ed90a1e695";

  /// 天地图矢量底图 (Web墨卡托投影)
  /// 
  /// 提供基础地理信息，包括道路、水系、居民地等
  /// 国内合规权威来源，适合作为主底图
  /// 
  /// 参数说明：
  /// - LAYER=vec: 矢量图层
  /// - TILEMATRIXSET=w: Web墨卡托投影
  /// - {s}: 服务器编号 (0-7)
  static String tiandituVec(String key) =>
      "https://t{s}.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILECOL={x}&TILEROW={y}&TILEMATRIX={z}&tk=$key";

  /// 天地图矢量注记层
  /// 
  /// 提供地名、路网名称等文字标注
  /// 需要与矢量底图叠加使用
  /// 
  /// 参数说明：
  /// - LAYER=cva: 矢量注记图层
  static String tiandituCva(String key) =>
      "https://t{s}.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILECOL={x}&TILEROW={y}&TILEMATRIX={z}&tk=$key";

  /// 天地图影像底图
  /// 
  /// 提供卫星影像和航拍图像
  /// 适合需要真实地表影像的场景
  /// 
  /// 参数说明：
  /// - LAYER=img: 影像图层
  static String tiandituImg(String key) =>
      "https://t{s}.tianditu.gov.cn/img_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILECOL={x}&TILEROW={y}&TILEMATRIX={z}&tk=$key";
  
  /// 天地图影像注记层
  /// 
  /// 提供影像上的地名标注
  /// 需要与影像底图叠加使用
  /// 
  /// 参数说明：
  /// - LAYER=cia: 影像注记图层
  static String tiandituCia(String key) =>
      "https://t{s}.tianditu.gov.cn/cia_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cia&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILECOL={x}&TILEROW={y}&TILEMATRIX={z}&tk=$key";

  /// 高德地图矢量底图
  /// 
  /// 提供详细的中文地图数据
  /// 适合国内应用，加载速度快
  /// 
  /// 参数说明：
  /// - lang=zh_cn: 中文语言
  /// - style=8: 矢量样式
  /// - {s}: 服务器编号 (1-4)
  static const String amapVector =
      "https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}";
}
