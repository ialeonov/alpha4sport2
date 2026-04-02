# Architecture

## Goals
- self-hosted personal app on VPS
- simple maintainable monolith
- responsive UX with local cache

## High-level design
- Flutter client (mobile + desktop/web)
- FastAPI backend (single service)
- PostgreSQL (single database)
- Docker Compose deployment
- optional Nginx reverse proxy

## Backend layers
- `app/api` REST routes
- `app/schemas` request/response validation
- `app/models` SQLAlchemy ORM models
- `app/core` config + security utilities
- `app/db` session + metadata

## Frontend layers
- feature-based clean architecture
- repository pattern
- API client (Dio)
- local cache (Hive) with online-first reads and queued writes

## Sync strategy (v1)
- server is source of truth
- cache successful GET responses locally
- on write failure, keep draft locally and retry manually (next phase: background retry queue)

## Security baseline
- JWT access token auth
- password hashing with bcrypt
- CORS allowlist
- input validation via Pydantic
- per-user ownership checks on all entities
