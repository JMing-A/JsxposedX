import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/memory_tool_overlay/presentation/widgets/memory_tool_feature_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MemoryToolEditTab extends StatelessWidget {
  const MemoryToolEditTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(12.r),
      children: <Widget>[
        MemoryToolFeatureCard(
          title: context.l10n.memoryToolEditTabTitle,
          subtitle: context.l10n.memoryToolEditTabSubtitle,
          items: <String>[
            context.l10n.memoryToolEditActionWriteValue,
            context.l10n.memoryToolEditActionFreezeValue,
            context.l10n.memoryToolEditActionBatchWrite,
          ],
        ),
        SizedBox(height: 12.r),
        MemoryToolFeatureCard(
          title: context.l10n.memoryToolPatchTabTitle,
          subtitle: context.l10n.memoryToolPatchTabSubtitle,
          items: <String>[
            context.l10n.memoryToolPatchActionHex,
            context.l10n.memoryToolPatchActionAsm,
            context.l10n.memoryToolPatchActionRestore,
          ],
        ),
      ],
    );
  }
}
