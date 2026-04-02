# Flutter architecture

Feature-based clean structure:
- `core/` shared clients, cache, theme, error handling
- `features/<feature>/data` DTOs, API data sources, repositories impl
- `features/<feature>/domain` entities, repository contracts, use cases
- `features/<feature>/presentation` screens, widgets, state controllers

Planned responsive navigation:
- mobile: bottom navigation
- tablet/desktop/web: navigation rail + detail panes
