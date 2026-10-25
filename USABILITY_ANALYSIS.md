# 🎯 АНАЛИЗ ЖИЗНЕСПОСОБНОСТИ И ПЕРЕОСМЫСЛЕНИЯ ЮЗАБИЛЬНОСТИ

## Матрица: Сложность × Проблемы × Приоритет

```
ВЫСОКИЙ ПРИОРИТЕТ (много проблем, часто используется)
════════════════════════════════════════════════════════════

🔴 КРИТИЧНЫЕ (требуют срочного переосмысления):

1. XP СИСТЕМА И ПРОГРЕССИРОВАНИЕ
   ├─ Сложность: 💥💥💥 (многоуровневая логика)
   ├─ Проблемы: 
   │  ├─ Legacy XP vs New XP (дата: 2026-03-20) → несогласованность
   │  ├─ Нет миграции для старых пользователей
   │  ├─ Каждый запрос профиля = полный пересчёт (O(n))
   │  ├─ Streak не учитывает sick leaves (unfair)
   │  ├─ Нет кэширования результатов
   │  └─ Edge case: удаление тренировки → полный пересчёт
   ├─ Частота использования: ⭐⭐⭐⭐⭐ (постоянно)
   └─ Что нужно переосмыслить:
      ├─ Финализировать XP систему (выбрать одну версию)
      ├─ Добавить кэширование (redis или in-memory)
      ├─ Мигрировать старые рекорды (один раз)
      ├─ Добавить версионирование (v1, v2, v3...)
      └─ Оптимизировать пересчёт (incremental, не full)

2. БЕЗОПАСНОСТЬ ДОСТУПА К ДАННЫМ
   ├─ Сложность: 💥💥 (относительно простая, но критична)
   ├─ Проблемы:
   │  ├─ Шаблоны шарятся по plain токену (не хешируется, нет expiry)
   │  ├─ Ссылка вида /shared/{token} доступна без auth
   │  ├─ Возможен перебор токена (brute force)
   │  ├─ Нет logирования доступа к чужим шаблонам
   │  ├─ Импорт шаблона теряет привязку к оригиналу
   │  └─ Нет защиты от CSRF (если есть, не очевидна)
   ├─ Частота использования: ⭐⭐⭐⭐ (социальная фишка)
   └─ Что нужно переосмыслить:
      ├─ Добавить expiry на токены (7 дней по умолчанию?)
      ├─ Хешировать токены в БД (как в Django)
      ├─ Добавить rate limiting на /shared/{token}
      ├─ Логировать импорты
      └─ Отслеживать оригинальный шаблон (для updates)

3. ТРЕНИРОВКА (WORKOUT) И ПРОГРЕСС
   ├─ Сложность: 💥💥💥 (взаимозависимости)
   ├─ Проблемы:
   │  ├─ Нет валидации: weight может быть -100, reps может быть -1
   │  ├─ set_type может быть любое значение (нет enum)
   │  ├─ Если finished_at = null → прогресс не пересчитывается
   │  ├─ Нет пагинации в списке тренировок (может быть 1000+)
   │  ├─ Редактирование тренировки → полное заменяет упражнения
   │  ├─ Удаление упражнения из каталога → рассинхрон с тренировками
   │  └─ История упражнения берёт только последний подход (странно)
   ├─ Частота использования: ⭐⭐⭐⭐⭐ (основной feature)
   └─ Что нужно переосмыслить:
      ├─ Валидация: weight >= 0, reps >= 1, max 500 reps
      ├─ set_type из enum: warmup, work, drop, amrap, rest_pause
      ├─ finished_at должен быть required (или черновик?)
      ├─ Пагинация: list_workouts(..., page=1, per_page=50)
      ├─ Partial edit упражнений (не полная замена)
      └─ Мягкое удаление упражнений из каталога (deprecated, не delete)

════════════════════════════════════════════════════════════

🟠 ВЫСОКИЕ (много проблем, средняя частота использования):

4. УПРАЖНЕНИЯ И КАТАЛОГ
   ├─ Сложность: 💥💥 (множество мышц, валидация)
   ├─ Проблемы:
   │  ├─ slug вычисляется, но не используется (dead code?)
   │  ├─ muscle names жёстко закодированы (нет таблицы)
   │  ├─ Встроенный каталог в JSON (нет синхронизации)
   │  ├─ ensure_seed_catalog вызывается на каждом запросе (n+1)
   │  ├─ Нет проверки похожих имён (case-insensitive дубли)
   │  └─ target_reps в шаблоне это String, а не Int
   ├─ Частота использования: ⭐⭐⭐ (при создании тренировок)
   └─ Что нужно переосмыслить:
      ├─ Удалить неиспользуемый slug или использовать
      ├─ Таблица muscle_groups (пример: id, name, ru_name)
      ├─ Синхронизация встроенного каталога (migration или seed command)
      ├─ Кэширование ensure_seed_catalog (флаг в user_profiles)
      └─ Нормализация target_reps на Int

5. АВАТАР И ЗАГРУЗКА ФАЙЛОВ
   ├─ Сложность: 💥 (простая, но неполная)
   ├─ Проблемы:
   │  ├─ Нет оптимизации изображений (может быть 10МБ JPEG)
   │  ├─ Нет удаления старого аватара при загрузке нового
   │  ├─ Валидация только по расширению (уязвимость)
   │  ├─ Нет обработки EXIF (приватность)
   │  ├─ photo_path в BodyEntry упоминается, но не реализовано
   │  └─ Путь хранится в БД (что если перенести /uploads?)
   ├─ Частота использования: ⭐⭐ (один раз при регистрации)
   └─ Что нужно переосмыслить:
      ├─ Сжатие: ImageMagick/Pillow при загрузке
      ├─ Удаление старого файла при новой загрузке
      ├─ Валидация MIME type (не только расширение)
      ├─ Обработка EXIF: удалить metadata
      └─ Реализовать upload для body photos

6. ПРОИЗВОДИТЕЛЬНОСТЬ И МАСШТАБИРУЕМОСТЬ
   ├─ Сложность: 💥💥💥 (много слоёв)
   ├─ Проблемы:
   │  ├─ Нет пагинации: list_workouts, list_templates, list_users
   │  ├─ N+1 queries: list_users → каждый юзер = доп queries
   │  ├─ Нет индексов на часто фильтруемые поля
   │  ├─ Нет кэша (Redis, Memcached)
   │  ├─ Нет connection pooling явного
   │  ├─ Нет rate limiting на API
   │  ├─ AI коуч может быть дорогим (нет логирования затрат)
   │  └─ Пересчёт прогресса = O(all workouts) каждый раз
   ├─ Частота использования: ⭐⭐⭐⭐ (всегда важна)
   └─ Что нужно переосмыслить:
      ├─ Добавить paginate wrapper для всех list endpoints
      ├─ Оптимизировать queries (явные joinedload, select)
      ├─ Добавить индексы (user_id, created_at DESC)
      ├─ Redis для кэша (progression, user list)
      ├─ Incremental progression updates
      └─ Rate limiting: redis-backed sliding window

════════════════════════════════════════════════════════════

🟡 СРЕДНИЕ (некоторые проблемы, редко используется):

7. WELLNESS И САМОЧУВСТВИЕ
   ├─ Сложность: 💥 (очень простая)
   ├─ Проблемы:
   │  ├─ Только 3 поля (sleep, stress, energy)
   │  ├─ Не валидируется min/max (stress может быть 0 или 1000)
   │  ├─ Не интегрировано нигде (кроме AI коуча)
   │  ├─ Нет истории или тренда
   │  └─ Не влияет на расчёт streak (хотя должно?)
   ├─ Частота использования: ⭐⭐ (опциональная фишка)
   └─ Что нужно переосмыслить:
      ├─ Расширить структуру (mood, injuries, notes)
      ├─ Валидация: 1-10 для stress/energy
      ├─ Graph endpoint для wellness trend
      └─ AI коуч использует wellness в рекомендациях (OK)

8. СОБЫТИЯ И ЛЕНТА АКТИВНОСТИ
   ├─ Сложность: 💥💥 (фильтрация, социальность)
   ├─ Проблемы:
   │  ├─ Нет фильтрации по типам событий
   │  ├─ Нет поиска
   │  ├─ Лайки видны только в профиле (не в ленте)
   │  ├─ Нет пагинации (может быть 1000+ событий)
   │  ├─ Как создаются события? (LoggingService нужна?)
   │  └─ Некоторые события скрыты (workout_completed) → почему?
   ├─ Частота использования: ⭐⭐⭐ (средняя)
   └─ Что нужно переосмыслить:
      ├─ Filter?event_type=pr,record,achievement
      ├─ Search?q=название упражнения
      ├─ Показать лайки в ленте (с аватарами)
      ├─ Пагинация
      └─ Документировать логику создания событий

9. ОБЪЯВЛЕНИЯ
   ├─ Сложность: 💥 (очень простая)
   ├─ Проблемы:
   │  ├─ Только одно активное объявление
   │  ├─ Нет расписания (scheduled announcements)
   │  ├─ Нет целевой аудитории (все видят)
   │  ├─ Нет A/B testing
   │  ├─ История есть, но нет endpoint для просмотра
   │  └─ Нет аналитики (кто прочитал?)
   ├─ Частота использования: ⭐ (редко)
   └─ Что нужно переосмыслить:
      ├─ Scheduling: published_at, expired_at
      ├─ Targeting: for_all, for_level_above, for_goals
      └─ Analytics: view count, click tracking

════════════════════════════════════════════════════════════

🟢 НИЗКИЕ (мало проблем, работает OK):

10. ЭКСОПРТ ДАННЫХ
   ├─ Сложность: 💥 (простая)
   ├─ Проблемы:
   │  ├─ Только JSON (нет CSV, Excel)
   │  ├─ Нет фильтрации по датам
   │  ├─ Может быть очень большой файл
   │  └─ Экспортирует только workouts + body (нет events, progress)
   ├─ Частота использования: ⭐ (очень редко)
   └─ Что нужно переосмыслить:
      ├─ Добавить CSV export
      ├─ Filter?from=2025-01-01&to=2025-03-31
      └─ Streaming response для больших файлов

11. АУТЕНТИФИКАЦИЯ
   ├─ Сложность: 💥💥 (JWT, bcrypt, CORS)
   ├─ Проблемы:
   │  ├─ Нет восстановления пароля (forgot password)
   │  ├─ Нет 2FA (двухфакторной аутентификации)
   │  ├─ Пароль не валидируется на сложность
   │  ├─ Email не подтверждается (confirmation link)
   │  ├─ Нет логирования попыток входа
   │  └─ JWT token не имеет expiry (всегда живой?)
   ├─ Частота использования: ⭐⭐⭐ (разово при входе)
   └─ Что нужно переосмыслить:
      ├─ Password strength validation (min 8 chars, mixed case, digits)
      ├─ Email verification (отправить confirmation link)
      ├─ Reset password flow (отправить reset link)
      ├─ Логирование: login attempts, IP, user-agent
      └─ JWT expiry: 24h access token + refresh token

════════════════════════════════════════════════════════════
```

---

## 📊 Таблица Приоритеты × Сложность

| № | Функция | Приоритет | Сложность | % Готовности | Рекомендация |
|---|---------|-----------|-----------|--------------|-------------|
| 1 | XP система | 🔴 Критичный | 💥💥💥 | 80% | **Финализировать, кэшировать** |
| 2 | Безопасность доступа | 🔴 Критичный | 💥💥 | 40% | **Добавить expiry, хеширование** |
| 3 | Тренировки (CRUD) | 🔴 Критичный | 💥💥💥 | 85% | **Валидация, пагинация, оптимизация** |
| 4 | Упражнения/Каталог | 🟠 Высокий | 💥💥 | 70% | **Таблица мышц, кэширование** |
| 5 | Аватар/Файлы | 🟠 Высокий | 💥 | 60% | **Сжатие, EXIF, photo upload** |
| 6 | Производительность | 🟠 Высокий | 💥💥💥 | 30% | **Пагинация, кэш, индексы, profiling** |
| 7 | Wellness | 🟡 Средний | 💥 | 50% | **Расширить, валидация** |
| 8 | События/Лента | 🟡 Средний | 💥💥 | 65% | **Фильтрация, пагинация** |
| 9 | Объявления | 🟡 Средний | 💥 | 60% | **Scheduling, targeting** |
| 10 | Экспорт | 🟢 Низкий | 💥 | 50% | **CSV, filter, streaming** |
| 11 | Аутентификация | 🟢 Низкий | 💥💥 | 65% | **2FA, email verification, reset** |

---

## 🎬 РЕКОМЕНДУЕМЫЙ ПЛАН ДЕЙСТВИЙ (ROADMAP)

### ФАЗА 1: Критичные (2-3 недели)

**SPRINT 1:**
- [ ] Финализировать XP систему (выбрать версию, мигрировать)
- [ ] Добавить кэширование progression (Redis)
- [ ] Добавить валидацию на weight, reps, set_type

**SPRINT 2:**
- [ ] Добавить expiry и хеширование на share tokens
- [ ] Rate limiting на API (redis-backed)
- [ ] Пагинация на list_workouts

### ФАЗА 2: Высокие (2-3 недели)

**SPRINT 3:**
- [ ] Таблица muscle_groups (миграция)
- [ ] Сжатие и оптимизация аватаров
- [ ] Реализовать upload для body photos

**SPRINT 4:**
- [ ] N+1 query fixes (list_users, list_templates)
- [ ] Добавить индексы на часто фильтруемые поля
- [ ] Incremental progression updates

### ФАЗА 3: Средние (1-2 недели)

**SPRINT 5:**
- [ ] Расширить wellness структуру + валидация
- [ ] Фильтрация и поиск в событиях
- [ ] Scheduling для объявлений

### ФАЗА 4: Низкие (1 неделя)

**SPRINT 6:**
- [ ] CSV export
- [ ] Email verification + reset password
- [ ] JWT expiry + refresh token

---

## 🔍 ДЕТАЛЬНЫЕ ПРЕДЛОЖЕНИЯ ПО КАЖДОМУ КОМПОНЕНТУ

### 1. XP СИСТЕМА - Переосмысление

**ТЕКУЩЕЕ СОСТОЯНИЕ:**
```python
# Две системы XP в одном коде
if created_at < 2026-03-20:
    xp = LEGACY_XP[event_type]  # old: workout=20
else:
    xp = REBALANCED_XP[event_type]  # new: workout=10
```

**ПРОБЛЕМЫ:**
- Никто не знает какая версия активна для какого пользователя
- Миграция не запущена (recalculate_all.py существует, но не задокументирована)
- Разные пользователи имеют разные коэффициенты

**РЕКОМЕНДАЦИЯ:**
```python
# Вариант 1: Финализировать одну версию
VERSION = "v2"  # выбрать одну
if VERSION == "v2":
    XP_CONFIG = REBALANCED_XP  # новая версия

# Вариант 2: Миграция с сохранением истории
class XPVersion(Base):
    __tablename__ = 'xp_versions'
    user_id: int
    version: str = "v1"  # v1 или v2
    migrated_at: datetime
    
# Вариант 3: Гибридная система (рекомендуется)
class UserXPConfig(Base):
    user_id: int
    version: str  # v1 или v2
    created_before_2026_03_20: bool
    # Если created_before → автоматически мигрируется на v2
```

**ДЕЙСТВИЕ:**
1. Запустить recalculate_all.py для всех пользователей
2. Добавить флаг version в user_progressions
3. Удалить LEGACY_XP из кода
4. Документировать систему

---

### 2. БЕЗОПАСНОСТЬ ДОСТУПА - Переосмысление

**ТЕКУЩЕЕ:**
```python
# share_token = secrets.token_urlsafe(16)
# GET /templates/shared/{token} → no auth needed
```

**ПРОБЛЕМЫ:**
- token_urlsafe → не хеширован (если кто-то найдёт БД → все токены скомпрометированы)
- Нет expiry (шаблон может делиться 10 лет)
- Нет rate limiting (можно перебирать токены)

**РЕКОМЕНДАЦИЯ:**
```python
class WorkoutTemplateShare(Base):
    __tablename__ = 'workout_template_shares'
    
    id: int = primary_key()
    template_id: int = foreign_key('workout_templates')
    token_hash: str  # SHA256(token)
    token_salt: str  # PBKDF2
    created_at: datetime
    expires_at: datetime = created_at + timedelta(days=7)
    max_imports: int = None  # None = unlimited
    import_count: int = 0
    created_by_user_id: int  # who shared
    shared_with_email: str = None  # specific user or None=public
    
    # Methods
    def is_valid(self) -> bool:
        return expires_at > datetime.now() and (max_imports is None or import_count < max_imports)

# На фронте:
POST /templates/{id}/share → {share_url, expires_in_days}
```

**ДЕЙСТВИЕ:**
1. Добавить таблицу WorkoutTemplateShare
2. Хешировать всё в цикле
3. Проверять expiry при доступе
4. Логировать все импорты

---

### 3. ТРЕНИРОВКИ - Переосмысление

**ВАЛИДАЦИЯ:**
```python
# Сейчас:
@router.post('/workouts')
def create_workout(payload: WorkoutCreate, ...):
    # Ничего не проверяет

# Должно быть:
class ExerciseSetCreate(BaseModel):
    position: int = Field(ge=1, le=50)
    reps: int = Field(ge=0, le=500)
    weight: float | None = Field(ge=0, le=1000)
    set_type: Literal['warmup', 'work', 'drop', 'amrap', 'rest_pause'] = 'work'
    rpe: float | None = Field(ge=0, le=10)
    notes: str | None = Field(max_length=500)
```

**ПАГИНАЦИЯ:**
```python
# Сейчас:
@router.get('')
def list_workouts(...) -> list[WorkoutOut]:
    # SELECT * всё сразу

# Должно быть:
from fastapi import Query

@router.get('')
def list_workouts(
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=100),
    ...
) -> PaginatedResponse[WorkoutOut]:
    offset = (page - 1) * per_page
    # SELECT ... LIMIT per_page OFFSET offset
    return {
        'items': items,
        'total': total_count,
        'page': page,
        'per_page': per_page,
        'total_pages': ceil(total_count / per_page)
    }
```

**РЕДАКТИРОВАНИЕ:**
```python
# Сейчас:
# PUT заменяет ВСЕ упражнения

# Должно быть: 
# PUT /workouts/{id}/exercises/{ex_id} → edit specific exercise
# POST /workouts/{id}/exercises → add one
# DELETE /workouts/{id}/exercises/{ex_id} → remove one
```

---

### 4. ПРОИЗВОДИТЕЛЬНОСТЬ - Переосмысление

**ТЕКУЩИЕ УЗКИЕ МЕСТА:**

```python
# 1. N+1 Query при list_users
users = db.query(User).all()  # 1 query
for user in users:  # N iteration
    progression = db.query(UserProgression).filter(...).one()  # N queries
    
# ПРАВИЛЬНО:
query = (
    select(User).options(selectinload(User.progression))
)

# 2. Полный пересчёт прогресса
def recalculate_for_user(user_id):
    all_workouts = db.query(Workout).filter(user_id=user_id).all()
    for workout in all_workouts:  # может быть 1000+ 
        # пересчитать всё с нуля (O(n))
        
# ПРАВИЛЬНО: Incremental
def add_xp_for_workout(workout_id):
    # Только для этой тренировки
    # += вместо = 
    
# 3. Нет кэша
def get_user_list():
    return db.query(User).all()  # Every time
    
# ПРАВИЛЬНО:
@cache(ttl=60)  # 1 min cache
def get_user_list():
    return ...
```

**ДЕЙСТВИЕ:**
1. Профилировать узкие места (py-spy, nydump)
2. Добавить selectinload вместо joinedload
3. Кэширование с Redis (простой пример ниже)

```python
from redis import Redis

redis_client = Redis(host='localhost')

def cached_get_user_list(ttl=60):
    cache_key = 'users:list'
    cached = redis_client.get(cache_key)
    if cached:
        return json.loads(cached)
    
    users = db.query(User).all()
    redis_client.setex(cache_key, ttl, json.dumps(users))
    return users
```

---

## 📝 ЧЕКЛИСТ ДЛЯ ПЕРЕОСМЫСЛЕНИЯ

Перед переосмыслением каждой функции проверьте:

- [ ] **Полнота**: Какие части недореализованы? (50%, 70%, 90%?)
- [ ] **Зависимости**: Какие компоненты зависят от этой функции?
- [ ] **Проблемы**: Какие баги или UX issues?
- [ ] **Масштабируемость**: Будет ли работать с 10x пользователями?
- [ ] **Безопасность**: Есть ли уязвимости?
- [ ] **Альтернативы**: Есть ли лучший способ?
- [ ] **Стоимость**: Сколько времени на переосмысление?

---

## 🎯 БЫСТРОЕ РЕЗЮМЕ

```
ПЕРЕОСМЫСЛЯТЬ В ПЕРВУЮ ОЧЕРЕДЬ:
1. XP система (финализировать, мигрировать) — 3 дня
2. Валидация + пагинация тренировок — 2 дня
3. Безопасность share tokens — 1 день
4. Кэширование + индексы БД — 2 дня
5. Аватар/файлы оптимизация — 1 день

ИТОГО: ~10 дней для критичной части
```

