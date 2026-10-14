## Unreleased

- A download now says how it ended. `DownloadManager` reports through the core's `MediaJobReporting` slot when a file finishes or when its retry budget is spent — the label is the file's own name, plus the bytes it wrote and the error it stopped on. An intermediate failure is not reported, because the retry is still coming, and a cancel is not, because the viewer asked for it. Nothing here depends on a notification plugin: with no reporter installed the call does nothing at all, which is the same for a host that has its own tray.

- Progress is published on a 200 ms window per task instead of once per received chunk. The chunk loop already computed the transfer rate on a 200 ms clock but emitted the task anyway, so a fast link paid a task copy, a memory report and a listener wake for every chunk - hundreds a second on one download, multiplied by `maxConcurrent`. The first chunk still reports immediately, the terminal state carries the exact byte count, and the window is per task so concurrent downloads cannot starve one another.

## 0.1.0

Initial release.

- Task queue: `DownloadManager` runs a set of `DownloadTask`s with a concurrency limit and queue state.
- Resumable transfers: `DownloadResumePlanner` produces a `DownloadResumePlan` (resume or restart) by proving the partial file still matches the remote (`DownloadResumeDecision`), checking ETag / size / bytes on disk before appending.
- Retry policy: per-task retry budget with `RetryUtils.backoff` delays from the core; failures surface on the task stream rather than as a private taxonomy.
- Transport abstraction: the `DownloadTransport` interface with a default implementation, writing through `DownloadFileSink`.
- Progress and status: `DownloadProgress` and `DownloadStatus` are ready to feed straight into host UI.
