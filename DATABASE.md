-- =========================
-- PROJECTS
-- =========================

CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

-- =========================
-- PROJECT STATE (Summary + Metrics)
-- =========================

CREATE TABLE project_state (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id),
    summary TEXT,
    total_tasks_completed INTEGER DEFAULT 0,
    last_summary_at TIMESTAMP NULL
);

-- =========================
-- TOPICS (Workspace Engine)
-- =========================

CREATE TABLE topics (
    id TEXT PRIMARY KEY,
    priority INTEGER CHECK (priority BETWEEN 1 AND 5),
    weight INTEGER NOT NULL,
    maxcount INTEGER NOT NULL,
    max_tasks_per_cycle INTEGER DEFAULT 5,
    description TEXT NOT NULL,
    remaining_count INTEGER NOT NULL,
    last_served_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- ARCHIVED TOPICS (Analytics)
-- =========================

CREATE TABLE archived_topics (
    id TEXT,
    description TEXT,
    total_tasks INTEGER,
    total_input_tokens INTEGER,
    total_output_tokens INTEGER,
    total_tokens INTEGER,
    archived_at TIMESTAMP DEFAULT NOW(),
    summary TEXT
);

-- =========================
-- PROJECT TASKS
-- =========================

CREATE TABLE project_tasks (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id),
    topic_id TEXT NULL REFERENCES topics(id),
    parent_task_id INTEGER NULL REFERENCES project_tasks(id),

    description TEXT NOT NULL,

    impact_score INTEGER,
    urgency_score INTEGER,
    complexity_score INTEGER,
    priority_score INTEGER,

    source TEXT CHECK (source IN ('user','workspace','system')),

    status TEXT CHECK (
        status IN (
            'pending',
            'in_progress',
            'done',
            'decomposed',
            'done_revisions'
        )
    ),

    total_tokens INTEGER DEFAULT 0,

    created_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP NULL
);

-- =========================
-- TASK REVIEWS (Critic Logs)
-- =========================

CREATE TABLE task_reviews (
    id SERIAL PRIMARY KEY,
    task_id INTEGER REFERENCES project_tasks(id),
    verdict TEXT CHECK (verdict IN ('approve','revise')),
    critic_comment TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- INDEXES (Performance)
-- =========================

CREATE INDEX idx_tasks_status ON project_tasks(status);
CREATE INDEX idx_tasks_project ON project_tasks(project_id);
CREATE INDEX idx_tasks_topic ON project_tasks(topic_id);
CREATE INDEX idx_reviews_task ON task_reviews(task_id);

-- =========================
-- INITIAL DATA
-- =========================

INSERT INTO projects (name) VALUES ('Johnny Bright');

