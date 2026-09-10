# Future optional-package migration

[简体中文](package-migration.zh-CN.md)

This is a compatible 0.7.0 evolution: shared execution, smaller examples, and explicit contracts. Dio, Riverpod, flutter_hooks, and Web visibility support remain main-package dependencies. This release publishes the main package without creating separate adapter packages or repositories. Separate export files do not remove pubspec dependencies.

| Unit | Responsibility |
| --- | --- |
| Core and Flutter Hooks | Service execution, state, concurrency, cache, scheduling, and lifecycle; future controller independent of Riverpod StateNotifier and Dio tokens |
| Optional Dio package | HTTP configuration, Dio error policy, token and transport cancellation bridge |
| Optional Riverpod package | Provider/Notifier integration and disposal |
| Website | Full same-repository showcase/deployment against local code; moving repositories does not decouple package dependencies |

Names are placeholders until registration availability is checked. This plan does not require a generic plugin framework.

1. Preserve the unified entry point and public APIs throughout compatible 0.7.0 work; lead documentation with arbitrary Future services.
2. In a later explicitly breaking release, replace the current StateNotifier-based core with a Dio/Riverpod-independent controller, migrate integration-specific types, and provide an old-to-new import/API map.
3. A transitional facade may re-export legacy entry points, but still depends on adapters; its consumers do not gain dependency independence.
4. Build a real minimal core-only consumer and verify its dependency graph excludes Dio/Riverpod. Independently analyze, test, and build Hook, Dio, and Riverpod consumers.
5. Check publication dry-runs, version constraints, and migration examples for every candidate before deciding to publish. Separate repositories are optional.

Persistent caching, parameter restoration, pagination extraction, and a broader ahooks-style hook collection require separate needs and acceptance criteria. They are not implemented speculatively here.
