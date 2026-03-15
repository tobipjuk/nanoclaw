---
name: todoist
description: Read and manage Todoist tasks — list tasks assigned to Tobi, create tasks, complete tasks, add comments. Use whenever the user asks about their to-do list, tasks, or wants to manage Todoist.
allowed-tools: Bash(curl*)
---

# Todoist API

API key is in `$TODOIST_API_KEY`. Base URL: `https://api.todoist.com/api/v1`.

**Tobi's user ID:** `2893711`
**Orion project inbox section ID:** `6g7cgvqxCVXpQH6X`

## Get Tobi's tasks

Most tasks do not have an assignee set (including all recurring tasks), so **always query all tasks** — do not filter by `assignee_id`. Tobi is the only user so all tasks belong to him.

The API paginates (default 50/page). Use `next_cursor` to fetch all pages when you need a complete list (e.g. checking due dates).

```bash
# First page
curl -s "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | jq '[.results[] | {id, content, due: .due.date, is_recurring: .due.is_recurring, priority}]'

# Next page (use next_cursor value from previous response)
curl -s "https://api.todoist.com/api/v1/tasks?cursor=CURSOR" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | jq '[.results[] | {id, content, due: .due.date, is_recurring: .due.is_recurring, priority}]'
```

## Filter by project

```bash
curl -s "https://api.todoist.com/api/v1/tasks?project_id=PROJECT_ID" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | jq '.results[] | {id, content, due: .due.string}'
```

## Get a single task

```bash
curl -s "https://api.todoist.com/api/v1/tasks/TASK_ID" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | jq '{id, content, description, due: .due.string, priority}'
```

## Create a task

**Before creating**, if the conversation already shows the task was just created (API returned an `id`), do **not** create it again — trust the prior result even if a subsequent GET returns null (Todoist has eventual consistency). Only create if there is no prior record of it being created in this session.

Do **not** set a due date unless the user explicitly asks for one.

```bash
curl -s -X POST "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $TODOIST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Task title",
    "description": "Optional details",
    "assignee_id": "2893711",
    "section_id": "6g7cgvqxCVXpQH6X"
  }' | jq '{id, content}'
```

To set a due date (only when the user requests it):

```bash
  -d '{"content": "Task title", "assignee_id": "2893711", "section_id": "6g7cgvqxCVXpQH6X", "due_string": "tomorrow"}'
```

## Complete (close) a task

```bash
curl -s -X POST "https://api.todoist.com/api/v1/tasks/TASK_ID/close" \
  -H "Authorization: Bearer $TODOIST_API_KEY"
```

## Update a task

```bash
curl -s -X POST "https://api.todoist.com/api/v1/tasks/TASK_ID" \
  -H "Authorization: Bearer $TODOIST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"due_string": "next monday", "priority": 3}' | jq '{id, content, due: .due.string}'
```

## Add a comment

```bash
curl -s -X POST "https://api.todoist.com/api/v1/comments" \
  -H "Authorization: Bearer $TODOIST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"task_id": "TASK_ID", "content": "Comment text"}' | jq '{id, content}'
```

## List projects

```bash
curl -s "https://api.todoist.com/api/v1/projects" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | jq '[.results[] | {id, name}]'
```

## Priority levels

| Value | Meaning |
|-------|---------|
| 1 | Normal |
| 2 | Medium |
| 3 | High |
| 4 | Urgent |
