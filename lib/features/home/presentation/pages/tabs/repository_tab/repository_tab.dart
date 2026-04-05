import 'package:JsxposedX/common/widgets/custom_tab_bar.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/home/presentation/pages/tabs/repository_tab/tabs/new_script_tab.dart';
import 'package:JsxposedX/features/home/presentation/pages/tabs/repository_tab/tabs/star_script_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 仓库 Tab
class RepositoryTab extends HookConsumerWidget {
  const RepositoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabController = useTabController(initialLength: 2);
    final currentTabIndex = useState(0);

    return Scaffold(
      appBar: AppBar(
        title: CustomTabBar(
          tabController: tabController,
          tabs: [
            Tab(text: context.l10n.news), //最新
            Tab(text: context.l10n.star), //收藏
          ],
        ),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 10.w),
        child: TabBarView(
          controller: tabController,
          children: const [NewScriptTab(), StarScriptTab()],
        ),
      ),
    );
  }
}
