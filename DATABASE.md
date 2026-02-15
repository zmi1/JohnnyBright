CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE project_tasks (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id),
    topic_id TEXT NULL,
    parent_task_id INTEGER NULL REFERENCES project_tasks(id),

    description TEXT NOT NULL,

    impact_score INTEGER,
    urgency_score INTEGER,
    complexity_score INTEGER,
    priority_score INTEGER,

    source TEXT CHECK (source IN ('user','workspace','system')),

    status TEXT CHECK (status IN ('pending','in_progress','done','decomposed')),

    created_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP NULL
);

CREATE TABLE topics (
    id TEXT PRIMARY KEY,
    priority INTEGER CHECK (priority BETWEEN 1 AND 5),
    weight INTEGER,
    maxcount INTEGER,
    max_tasks_per_cycle INTEGER,
    description TEXT,
    remaining_count INTEGER,
    last_served_at TIMESTAMP NULL
);

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

CREATE TABLE project_state (
    id SERIAL PRIMARY KEY,
    summary TEXT,
    total_tasks_completed INTEGER DEFAULT 0,
    last_summary_at TIMESTAMP NULL
);

