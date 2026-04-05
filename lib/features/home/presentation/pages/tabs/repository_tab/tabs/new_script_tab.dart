import 'package:JsxposedX/common/widgets/back_to_top_button.dart';
import 'package:JsxposedX/common/widgets/infinite_scroll_list.dart';
import 'package:JsxposedX/common/widgets/script_card.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/home/domain/models/post.dart';
import 'package:JsxposedX/features/home/presentation/providers/post_infinite_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NewScriptTab extends HookConsumerWidget {
  const NewScriptTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useAutomaticKeepAlive();
    final state = ref.watch(newPostsInfiniteProvider);
    final showBackToTop = useState(false);
    final scrollController = useScrollController();

    // 初始化数据
    useEffect(() {
      if (state.rows.isEmpty && !state.isLoading) {
        Future.microtask(() {
          ref.read(newPostsInfiniteProvider.notifier).loadMore();
        });
      }
      return null;
    }, []);

    // 监听滚动，显示返回顶部按钮
    useEffect(() {
      void onScroll() {
        if (scrollController.hasClients) {
          final currentScroll = scrollController.position.pixels;
          if (currentScroll > 300.h && !showBackToTop.value) {
            showBackToTop.value = true;
          } else if (currentScroll <= 300.h && showBackToTop.value) {
            showBackToTop.value = false;
          }
        }
      }

      scrollController.addListener(onScroll);
      return () => scrollController.removeListener(onScroll);
    }, [scrollController]);

    return Stack(
      children: [
        InfiniteScrollList<Post>.independent(
          items: state.rows,
          isLoading: state.isLoading,
          hasMore: state.hasMore,
          onLoadMore: () {
            ref.read(newPostsInfiniteProvider.notifier).loadMore();
          },
          onRefresh: () async {
            await ref.read(newPostsInfiniteProvider.notifier).refresh();
          },
          itemBuilder: (context, post) {
            return Padding(
              padding: EdgeInsets.only(bottom: 20.h),
              child: ScriptCard(post: post),
            );
          },
          emptyBuilder: (context) => InfiniteScrollList.emptyTip(
            context.l10n.noData,
            context: context,
            onRetry: () {
              ref.read(newPostsInfiniteProvider.notifier).refresh();
            },
          ),
          scrollController: scrollController,
          storageKey: const PageStorageKey('new_scripts_list'),
          completeMessage: context.l10n.noData,
        ),
        // 返回顶部悬浮按钮
        BackToTopButton(
          visible: showBackToTop.value,
          scrollController: scrollController,
          onRefresh: () async {
            await ref.read(newPostsInfiniteProvider.notifier).refresh();
          },
          right: 16.w,
          bottom: 88.h,
          fadeDuration: const Duration(milliseconds: 300),
          scrollDuration: const Duration(milliseconds: 1000),
          heroTag: 'back_to_top_new_scripts',
        ),
      ],
    );
  }
}
