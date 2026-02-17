-- ============================================================
-- JOHNNY BRIGHT - Drop all tables (clean reset)
-- Run this BEFORE DATABASE_v2.sql for a fresh start
-- ============================================================

DROP FUNCTION IF EXISTS update_project_metrics(INTEGER);
DROP FUNCTION IF EXISTS get_next_pending_task(INTEGER);

DROP TABLE IF EXISTS error_log CASCADE;
DROP TABLE IF EXISTS execution_log CASCADE;
DROP TABLE IF EXISTS task_reviews CASCADE;
DROP TABLE IF EXISTS project_tasks CASCADE;
DROP TABLE IF EXISTS archived_topics CASCADE;
DROP TABLE IF EXISTS topics CASCADE;
DROP TABLE IF EXISTS project_state CASCADE;
DROP TABLE IF EXISTS workflow_state CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
