import 'package:flutter/widgets.dart';

import 'package:media_core_fvp/src/fvp_player_adapter.dart';

/// Renders the surface owned by [FvpPlayerAdapter].
///
/// This is the reference implementation of a *custom* surface: it does not call
/// `adapter.build()`, it reads the adapter's listenables directly. That keeps
/// the adapter as the single owner of the texture while letting the app own the
/// widget tree, controls and fullscreen behaviour.
///
/// ```dart
/// FvpVideoView(adapter: myAdapter)
/// ```
class FvpVideoView extends StatelessWidget {
  /// Creates the view that renders [adapter]'s texture.
  const FvpVideoView({required this.adapter, super.key});

  /// The adapter whose surface is rendered.
  final FvpPlayerAdapter adapter;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: adapter.textureListenable,
      builder: (context, textureId, _) => ValueListenableBuilder<Size?>(
        valueListenable: adapter.sizeListenable,
        builder: (context, size, _) => ValueListenableBuilder<BoxFit>(
          valueListenable: adapter.fitListenable,
          builder: (context, fit, _) => adapter.buildSurface(textureId: textureId, size: size, fit: fit),
        ),
      ),
    );
  }
}
