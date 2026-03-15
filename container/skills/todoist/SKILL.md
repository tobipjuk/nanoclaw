---
name: todoist
description: Read and manage Todoist tasks — list tasks assigned to Tobi, create tasks, complete tasks, add comments. Use whenever the user asks about their to-do list, tasks, or wants to manage Todoist.
allowed-tools: Bash(curl*)
---

# Todoist API

API key is in `$TODOIST_API_KEY`. Base URL: `https://api.todoist.com/api/v1`.

**Tobi's user ID:** `2893711`
**Orion project inbox section ID:** `6g7cgvqxCVXpQH6X`

## Get tasks assigned to Tobi

```bash
curl -s "https://api.todoist.com/api/v1/tasks?assignee_id=2893711" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | jq '[.results[] | {id, content, description, due: .due.string, priority}]'
```

## Get all active tasks (any assignee)

```bash
curl -s "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $TODOIST_API_KEY" | jq '[.results[] | {id, content, assignee_id, due: .due.string, priority}]'
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
