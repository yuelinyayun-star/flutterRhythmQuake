# P-Alert 下载页面灰色遮罩检查（2026-11-26）

## 已观察到的状态

- Edge 当前仍有 P-Alert 事件下载页标签：`https://palert.earth.sinica.edu.tw/database/download/20261125084717`。
- Browser 只读页面文本快照能够读取到事件信息、地图、测站列表和下载按钮。
- 测站表格显示 `713 / 713`，说明列表数据已渲染完成。
- 页面文本快照中没有出现 `Loading`、`loading`、`載入中`、`加载中` 或 `請稍候` 字样。
- 页面DOM文本中包含筛选面板、显示效果面板及下载表单字段；但文本快照不能证明下载表单当前是否可见，也不能读取元素CSS、遮罩层z-index或按钮disabled状态。

## 无法确认的部分

- Browser tab context工具只返回页面文本，不提供DOM属性、CSS计算样式、Console日志或Network请求列表。
- 本地 Codex ACP 尝试读取 Edge 窗口/浏览器状态时，浏览器访问宿主返回 `Browsers: Error: The browser access host is unavailable`，Edge窗口状态读取也超时。
- 因此目前没有证据确认是否存在Pending请求、失败XHR、未完成Promise或全局Loading计数器未归零。

## 当前判断

测站列表已经渲染，不像是713个测站数据本身仍在加载。灰色遮罩可能是筛选/下载模态框的backdrop，也可能是独立的全局Loading遮罩；仅凭文本快照无法区分，不能提前认定根因。

## 下一步需要的最少证据

保持当前页面不刷新、不关闭、不提交下载：

1. F12 -> Network -> Fetch/XHR，查看是否存在持续Pending或红色失败请求。
2. F12 -> Console，查看页面初始化或下载表单相关异常。
3. 如果有Pending，请提供该请求的Name、Status、Duration和错误信息；不要复制请求Headers、Cookie、验证码token、邮箱或其他个人字段。
4. 如果没有Pending，再检查遮罩元素的DOM/CSS和页面是否存在打开的模态框。

本轮未点击页面控件、未刷新或关闭标签、未提交表单、未读取或使用验证码token，也未修改网站或项目生产代码。

