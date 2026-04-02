# Alpha4Sport

Personal self-hosted cross-platform fitness tracker.

## Stack
- Frontend: Flutter
- Backend: FastAPI + SQLAlchemy + Alembic
- Database: PostgreSQL
- Deployment: Docker Compose (optional Nginx reverse proxy)

## Repository layout
- `backend/` FastAPI API + DB migrations
- `frontend/` Flutter app scaffold with feature-based clean architecture
- `deploy/` Compose + Nginx templates
- `docs/` architecture, schema, API, implementation plan

## Quick start (backend + database)
1. Copy env:
   - `copy backend/.env.example backend/.env`
2. Run services:
   - `docker compose -f deploy/docker-compose.yml up --build`
3. API:
   - `http://localhost:8000/docs`
4. Frontend:
   - run separately with `cd frontend && flutter run -d chrome`

## Local test mode without Docker
1. Install backend dependencies once:
   - `cd backend`
   - `python -m pip install -r requirements.txt`
2. Start local API with SQLite:
   - `.\start_local.ps1`
3. Start Flutter web app in another terminal:
   - `cd frontend`
   - `flutter run -d chrome`
4. In debug mode the app uses `http://localhost:8000` automatically.

## PyCharm run configurations
- Shared run configs are stored in `.idea/runConfigurations/`.
- Use `alpha4sport docker` for backend/database and `alpha4sport dev` for Docker + Flutter together.
- Backend runs in Docker with `uvicorn --reload`, so code changes under `backend/app` are picked up without recreating the container.
- If Docker state becomes stale, run:
  - `docker compose -f deploy/docker-compose.yml down`
  - `docker compose -f deploy/docker-compose.yml up --build`

## VPS deploy
1. Backend on VPS:
   - `docker compose -f deploy/docker-compose.yml up -d --build`
2. Frontend on VPS:
   - build locally with `cd frontend && flutter build web`
   - copy contents of `frontend/build/web/` to `/var/www/fit.ileonov.ru/`
3. Host nginx on VPS:
   - use `deploy/nginx/default.conf` as the site config

## Git + VPS workflow
1. Create a remote repository and push this project there:
   - `git init`
   - `git add .`
   - `git commit -m "Initial commit"`
   - `git branch -M main`
   - `git remote add origin <your-repo-url>`
   - `git push -u origin main`
2. On the VPS clone the repository:
   - `git clone <your-repo-url> /opt/alpha4sport2`
3. Create the backend environment file on the VPS:
   - `cp backend/.env.example backend/.env`
   - then edit `backend/.env` and set a real `SECRET_KEY`
4. For production use the dedicated compose file:
   - `docker compose -f deploy/docker-compose.prod.yml up -d --build`
5. For updates on the VPS:
   - `bash deploy/deploy.sh`

Notes:
- `deploy/docker-compose.prod.yml` is for VPS production deploy.
- `deploy/docker-compose.yml` remains the local development setup with live reload.
- The deploy script rebuilds backend containers and also deploys the Flutter web frontend if `flutter` is installed on the VPS.

## Current status
This initial scaffold implements:
- JWT authentication
- workout CRUD (with exercises and sets)
- workout templates CRUD
- body entries CRUD
- progress endpoints (exercise history, weekly volume, bodyweight trend)
- export endpoint (JSON)

Next steps are in `docs/IMPLEMENTATION_PLAN.md`.
