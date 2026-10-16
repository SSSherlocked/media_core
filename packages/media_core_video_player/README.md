# media_core_video_player

AVPlayer backend for media_core on macOS and iOS. It drives the official
`video_player_avfoundation` plugin through `video_player_platform_interface`
directly, so the app does not also pull `video_player_android`.
