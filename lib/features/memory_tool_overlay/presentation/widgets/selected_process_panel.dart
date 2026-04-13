import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_edit_tab.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_process_header.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_search_tab.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_watch_tab.dart';
import 'package:JsxposedX/generated/memory_tool.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SelectedProcessPanel extends StatelessWidget {
  const SelectedProcessPanel({super.key, required this.selectedProcess});

  final ProcessInfo? selectedProcess;

  @override
  Widget build(BuildContext context) {
    if (selectedProcess == null) {
      return Center(
        child: Text(
          context.l10n.selectApp,
          style: TextStyle(
            color: context.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(12.r, 10.r, 12.r, 10.r),
          child: MemoryToolProcessHeader(process: selectedProcess!),
        ),
        const Expanded(
          child: TabBarView(
            children: <Widget>[
              MemoryToolSearchTab(),
              MemoryToolEditTab(),
              MemoryToolWatchTab(),
            ],
          ),
        ),
      ],
    );
  }
}
