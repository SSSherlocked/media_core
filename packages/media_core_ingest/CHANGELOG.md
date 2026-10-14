## Unreleased

- The loopback relay now streams a proxied child instead of buffering it (`bufferOutput = false`). With dart:io's default the child sat in this process until the output buffer filled or the response closed, so a small child - an init segment, a low-bitrate slice - added a needless wait to every range request.
- A child that fails mid-body now always gets its response closed. The old `_fail` set the status and closed inside one `try`, so once the body had started, the status assignment threw and the close was skipped - the relay's own teardown then dropped the headers and the bytes already forwarded, and the player saw an unexplained connection reset where it should see a segment that ended early.

## 0.1.0

- `IngestNeed` / `IngestStrategy` / `resolveIngestPlan`: one place that decides
  whether a source is handed to the player directly or through a relay, instead
  of a per-host branch in every playback transport.
- `LoopbackIngestRelay`: rewrites an HLS manifest tree (children, keys, maps,
  nested playlists) to absolute loopback URLs and proxies the children upstream
  with the caller's headers. Fixes sources whose bare or absolute-path children
  a native resolver turns into local paths.
- `FfmpegIngestRelay`: remuxes an upstream into a rolling loopback HLS tree for
  containers the player cannot parse and for URLs that expire mid-stream.
