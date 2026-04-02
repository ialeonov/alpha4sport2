# Implementation plan

## Phase 1 (done in this scaffold)
- base backend architecture
- DB models + initial Alembic migration
- core auth/workout/template/body/progress/export endpoints
- docker compose + nginx config template
- base Flutter feature folders and screen stubs

## Phase 2
- finish backend validation and error model
- photo upload endpoint and local file storage
- CSV export endpoint + backup/restore import endpoint
- seed script for first admin user
- OpenAPI examples

## Phase 3
- Flutter login and token persistence
- workout flow UI optimized for gym usage
- history/detail/edit/delete workflows
- template reorder UX

## Phase 4
- progress charts with real backend data
- body tracking forms + photos
- robust cache strategy and offline queue for writes

## Phase 5
- end-to-end tests (backend)
- widget/integration tests (flutter)
- VPS deployment guide and hardening checklist
