-- ============================================================
-- JOHNNY BRIGHT - Database Schema v2
-- Complete, production-ready schema
-- ============================================================

-- =========================
-- PROJECTS
-- =========================
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- PROJECT STATE (Live Summary + Metrics)
-- =========================
CREATE TABLE project_state (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    summary TEXT,
    total_tasks_completed INTEGER DEFAULT 0,
    total_tasks_failed INTEGER DEFAULT 0,
    total_tokens_used BIGINT DEFAULT 0,
    avg_critic_pass_rate NUMERIC(5,2) DEFAULT 0,
    last_summary_at TIMESTAMP NULL,
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(project_id)
);

-- =========================
-- TOPICS (Workspace Engine)
-- =========================
CREATE TABLE topics (
    id TEXT PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    priority INTEGER CHECK (priority BETWEEN 1 AND 5),
    weight INTEGER NOT NULL DEFAULT 1,
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
    id TEXT PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    description TEXT,
    total_tasks INTEGER DEFAULT 0,
    total_input_tokens BIGINT DEFAULT 0,
    total_output_tokens BIGINT DEFAULT 0,
    total_tokens BIGINT DEFAULT 0,
    archived_at TIMESTAMP DEFAULT NOW(),
    summary TEXT
);

-- =========================
-- PROJECT TASKS
-- =========================
CREATE TABLE project_tasks (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    topic_id TEXT NULL REFERENCES topics(id) ON DELETE SET NULL,
    parent_task_id INTEGER NULL REFERENCES project_tasks(id) ON DELETE SET NULL,

    description TEXT NOT NULL,

    impact_score INTEGER CHECK (impact_score BETWEEN 0 AND 100),
    urgency_score INTEGER CHECK (urgency_score BETWEEN 0 AND 100),
    complexity_score INTEGER CHECK (complexity_score BETWEEN 0 AND 100),
    priority_score INTEGER GENERATED ALWAYS AS (
        (COALESCE(impact_score, 50) * 4 + COALESCE(urgency_score, 50) * 4 + (100 - COALESCE(complexity_score, 50)) * 2) / 10
    ) STORED,

    source TEXT NOT NULL CHECK (source IN ('user', 'workspace', 'system', 'decomposed')),

    status TEXT NOT NULL DEFAULT 'pending' CHECK (
        status IN (
            'pending',
            'in_progress',
            'done',
            'decomposed',
            'done_revisions',
            'failed'
        )
    ),

    revision_count INTEGER DEFAULT 0,
    total_tokens BIGINT DEFAULT 0,

    created_at TIMESTAMP DEFAULT NOW(),
    started_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL
);

-- =========================
-- TASK REVIEWS (Critic Logs)
-- =========================
CREATE TABLE task_reviews (
    id SERIAL PRIMARY KEY,
    task_id INTEGER REFERENCES project_tasks(id) ON DELETE CASCADE,
    verdict TEXT NOT NULL CHECK (verdict IN ('approve', 'revise')),
    critic_comment TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- EXECUTION LOG (LLM Outputs)
-- =========================
CREATE TABLE execution_log (
    id SERIAL PRIMARY KEY,
    task_id INTEGER REFERENCES project_tasks(id) ON DELETE CASCADE,
    revision_number INTEGER DEFAULT 0,
    prompt_sent TEXT,
    llm_output TEXT,
    input_tokens INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    temperature NUMERIC(3,2),
    model TEXT DEFAULT 'qwen2.5-32b',
    duration_ms INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- ERROR LOG
-- =========================
CREATE TABLE error_log (
    id SERIAL PRIMARY KEY,
    workflow_name TEXT NOT NULL,
    node_name TEXT,
    error_message TEXT,
    error_stack TEXT,
    execution_id TEXT,
    task_id INTEGER NULL REFERENCES project_tasks(id) ON DELETE SET NULL,
    severity TEXT DEFAULT 'error' CHECK (severity IN ('warning', 'error', 'critical')),
    resolved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- WORKFLOW STATE (Persistent state for WRR etc.)
-- =========================
CREATE TABLE workflow_state (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- INDEXES
-- =========================
CREATE INDEX idx_tasks_status ON project_tasks(status);
CREATE INDEX idx_tasks_project ON project_tasks(project_id);
CREATE INDEX idx_tasks_topic ON project_tasks(topic_id);
CREATE INDEX idx_tasks_priority ON project_tasks(priority_score DESC);
CREATE INDEX idx_tasks_pending ON project_tasks(status, priority_score DESC) WHERE status = 'pending';
CREATE INDEX idx_reviews_task ON task_reviews(task_id);
CREATE INDEX idx_exec_log_task ON execution_log(task_id);
CREATE INDEX idx_error_log_time ON error_log(created_at DESC);
CREATE INDEX idx_error_log_unresolved ON error_log(resolved) WHERE resolved = FALSE;
CREATE INDEX idx_topics_priority ON topics(priority, remaining_count);

-- =========================
-- INITIAL DATA
-- =========================
INSERT INTO projects (name) VALUES ('Johnny Bright');

INSERT INTO project_state (project_id, summary)
VALUES (
    (SELECT id FROM projects WHERE name = 'Johnny Bright'),
    'System initialized. Awaiting first tasks.'
);

-- Initialize WRR index
INSERT INTO workflow_state (key, value)
VALUES ('wrr_index', '{"index": 0}'::jsonb);

-- =========================
-- HELPER FUNCTIONS
-- =========================

-- Function to get next pending task (priority-ordered)
CREATE OR REPLACE FUNCTION get_next_pending_task(p_project_id INTEGER)
RETURNS TABLE(
    id INTEGER,
    description TEXT,
    topic_id TEXT,
    source TEXT,
    impact_score INTEGER,
    urgency_score INTEGER,
    complexity_score INTEGER,
    priority_score INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT pt.id, pt.description, pt.topic_id, pt.source,
           pt.impact_score, pt.urgency_score, pt.complexity_score, pt.priority_score
    FROM project_tasks pt
    WHERE pt.project_id = p_project_id
      AND pt.status = 'pending'
    ORDER BY
        CASE WHEN pt.source = 'user' THEN 0 ELSE 1 END,
        pt.priority_score DESC NULLS LAST,
        pt.created_at ASC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Function to update project state metrics
CREATE OR REPLACE FUNCTION update_project_metrics(p_project_id INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE project_state SET
        total_tasks_completed = (
            SELECT COUNT(*) FROM project_tasks
            WHERE project_id = p_project_id AND status IN ('done', 'done_revisions')
        ),
        total_tasks_failed = (
            SELECT COUNT(*) FROM project_tasks
            WHERE project_id = p_project_id AND status = 'failed'
        ),
        total_tokens_used = (
            SELECT COALESCE(SUM(total_tokens), 0) FROM project_tasks
            WHERE project_id = p_project_id
        ),
        avg_critic_pass_rate = (
            SELECT COALESCE(
                ROUND(100.0 * COUNT(*) FILTER (WHERE verdict = 'approve') / NULLIF(COUNT(*), 0), 2),
                0
            )
            FROM task_reviews tr
            JOIN project_tasks pt ON tr.task_id = pt.id
            WHERE pt.project_id = p_project_id
        ),
        updated_at = NOW(),
        last_summary_at = NOW()
    WHERE project_id = p_project_id;
END;
$$ LANGUAGE plpgsql;
