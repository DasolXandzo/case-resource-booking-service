-- Сервис бронирования переговорных комнат
-- СУБД: PostgreSQL 14 и выше

-- Расширение нужно, для сочетания равенства и пересечения интервалов времени в EXCLUDE-ограничении.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------
-- Сотрудники
-- ---------------------------------------------------------------
CREATE TABLE users (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email       VARCHAR(255) NOT NULL UNIQUE,
    full_name   VARCHAR(150) NOT NULL,
    department  VARCHAR(100),
    role        VARCHAR(20)  NOT NULL DEFAULT 'employee',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_users_role CHECK (role IN ('employee', 'admin'))
);

-- ---------------------------------------------------------------
-- Переговорные комнаты
-- ---------------------------------------------------------------
CREATE TABLE rooms (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(100) NOT NULL UNIQUE,
    floor       SMALLINT     NOT NULL,
    capacity    SMALLINT     NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_rooms_capacity CHECK (capacity > 0)
);

-- ---------------------------------------------------------------
-- Брони
-- Отклонённые заявки в таблицу не попадают, хранятся только подтверждённые и отменённые брони.
-- Проверки, зависящие от других таблиц или от текущего времени (вместимость комнаты, начало в будущем, права на отмену), выполняет приложение.
-- ---------------------------------------------------------------
CREATE TABLE bookings (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id       BIGINT       NOT NULL REFERENCES rooms (id),
    user_id       BIGINT       NOT NULL REFERENCES users (id),
    title         VARCHAR(200) NOT NULL,
    attendees     SMALLINT     NOT NULL DEFAULT 1,
    starts_at     TIMESTAMPTZ  NOT NULL,
    ends_at       TIMESTAMPTZ  NOT NULL,
    status        VARCHAR(20)  NOT NULL DEFAULT 'confirmed',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    cancelled_at  TIMESTAMPTZ,

    CONSTRAINT chk_bookings_status CHECK (status IN ('confirmed', 'cancelled')),
    CONSTRAINT chk_bookings_period CHECK (ends_at > starts_at),
    CONSTRAINT chk_bookings_duration CHECK (
        ends_at - starts_at BETWEEN interval '15 minutes' AND interval '4 hours'
    ),
    CONSTRAINT chk_bookings_attendees CHECK (attendees > 0),
    CONSTRAINT chk_bookings_cancelled CHECK (
        (status = 'cancelled' AND cancelled_at IS NOT NULL)
        OR (status = 'confirmed' AND cancelled_at IS NULL)
    ),

    -- Главная защита от двойного бронирования: у одной комнаты не может быть двух подтверждённых броней с пересекающимся временем.
    -- Интервал полуоткрытый [начало, конец).
    CONSTRAINT no_overlapping_bookings EXCLUDE USING gist (
        room_id WITH =,
        tstzrange(starts_at, ends_at, '[)') WITH &&
    ) WHERE (status = 'confirmed')
);

-- Индексы под типовые запросы
CREATE INDEX idx_bookings_user_starts ON bookings (user_id, starts_at);
CREATE INDEX idx_bookings_room_starts ON bookings (room_id, starts_at);
