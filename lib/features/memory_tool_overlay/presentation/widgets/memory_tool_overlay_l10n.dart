import 'package:JsxposedX/l10n/app_localizations.dart';

extension MemoryToolOverlayL10n on AppLocalizations {
  bool get _isZh => localeName.toLowerCase().startsWith('zh');

  String get memoryToolTabSearch => _isZh ? '搜索' : 'Search';
  String get memoryToolTabEdit => _isZh ? '修改' : 'Edit';
  String get memoryToolTabWatch => _isZh ? '监视' : 'Watch';

  String get memoryToolSearchTabTitle =>
      _isZh ? '搜索参数' : 'Search Parameters';
  String get memoryToolSearchTabSubtitle => _isZh
      ? '用于放首次搜索、范围缩小和读取入口。'
      : 'Use this area for first scan, narrowing, and read entry points.';
  String get memoryToolSearchModeLabel => _isZh ? '模式' : 'Mode';

  String get memoryToolFieldValue => _isZh ? '数值' : 'Value';
  String get memoryToolFieldValuePlaceholder => '100.0';
  String get memoryToolFieldType => _isZh ? '类型' : 'Type';
  String get memoryToolFieldTypePlaceholder => _isZh ? '自动' : 'Auto';
  String get memoryToolFieldScope => _isZh ? '范围' : 'Scope';
  String get memoryToolFieldScopePlaceholder =>
      _isZh ? '全部内存' : 'All memory';
  String get memoryToolSearchExact => _isZh ? '精确搜索' : 'Exact Scan';

  String get memoryToolActionPanelTitle =>
      _isZh ? '操作入口' : 'Action Panel';
  String get memoryToolActionPanelSubtitle => _isZh
      ? '保留给首次扫描、继续筛选和读取操作。'
      : 'Reserved for first scan, next scan, and read operations.';
  String get memoryToolActionFirstScan => _isZh ? '首次扫描' : 'First Scan';
  String get memoryToolActionNextScan => _isZh ? '继续筛选' : 'Next Scan';
  String get memoryToolActionRead => _isZh ? '读取' : 'Read';

  String get memoryToolEditTabTitle =>
      _isZh ? '修改工作区' : 'Edit Workspace';
  String get memoryToolEditTabSubtitle => _isZh
      ? '这里适合放指定地址写入、批量修改和冻结入口。'
      : 'A good place for address writes, batch edits, and freeze entry points.';
  String get memoryToolEditActionWriteValue => _isZh
      ? '向目标地址写入新数值'
      : 'Write a new value to the target address';
  String get memoryToolEditActionFreezeValue => _isZh
      ? '把结果加入冻结列表并保持值不变'
      : 'Add the result to the freeze list and keep it stable';
  String get memoryToolEditActionBatchWrite => _isZh
      ? '对筛选结果执行批量写入'
      : 'Apply a batch write to filtered results';

  String get memoryToolPatchTabTitle =>
      _isZh ? '补丁与脚本' : 'Patches & Scripts';
  String get memoryToolPatchTabSubtitle => _isZh
      ? '适合放 Hex 补丁、汇编修改和恢复原值。'
      : 'Suitable for hex patches, asm edits, and restore actions.';
  String get memoryToolPatchActionHex =>
      _isZh ? 'Hex Patch 编辑入口' : 'Hex patch entry';
  String get memoryToolPatchActionAsm =>
      _isZh ? '汇编修改入口' : 'Assembly edit entry';
  String get memoryToolPatchActionRestore => _isZh
      ? '恢复原始值与补丁'
      : 'Restore original values and patches';

  String get memoryToolWatchTabTitle => _isZh ? '监视列表' : 'Watch List';
  String get memoryToolWatchTabSubtitle => _isZh
      ? '这里适合展示常驻监视值和冻结状态。'
      : 'Use this tab for persistent watch values and freeze states.';
}
