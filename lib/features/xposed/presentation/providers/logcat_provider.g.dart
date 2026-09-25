// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'logcat_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Logcat)
const logcatProvider = LogcatProvider._();

final class LogcatProvider
    extends $NotifierProvider<Logcat, List<LogcatEntry>> {
  const LogcatProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'logcatProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$logcatHash();

  @$internal
  @override
  Logcat create() => Logcat();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LogcatEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LogcatEntry>>(value),
    );
  }
}

String _$logcatHash() => r'95f2517226e28b6aa3f2d20a2ba354e72dcdd122';

abstract class _$Logcat extends $Notifier<List<LogcatEntry>> {
  List<LogcatEntry> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<LogcatEntry>, List<LogcatEntry>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<LogcatEntry>, List<LogcatEntry>>,
              List<LogcatEntry>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
