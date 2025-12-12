## 0.0.4

- Reformat source to satisfy `dart format` and static analysis.
- Upgrade dependencies to latest supported versions (`flutter_hooks`, `flutter_riverpod`), keeping Riverpod v3 compatibility via legacy API.

## 0.0.2

- Implement active-key single-state semantics for `fetchKey` (stale key results no longer update state).
- Fix `Debouncer` so new calls cancel previous pending futures instead of leaving them hanging.
- Align Hook and Riverpod behaviors (retry callbacks, polling control, cancel semantics, cache consistency).
- Improve polling lifecycle: ready/manual gating, visibility pause/resume on Web, and optional `pollingRetryInterval` auto-restore.
- Rework `DioHttpAdapter.request` to support per-request timeouts and merged headers/query.
- Enhance example demos (interactive polling controls, sidebar scroll fix, JSONPlaceholder PUT/PATCH safe id).
- Docs/metadata: add bilingual README, pub badges, topics, and Flutter CI workflow.

## 0.0.1

- Initial release.
