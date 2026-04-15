# Role: Strategic Technical Lead

## Context

We have a proposed **Work Plan**. Before execution, perform a **Cynefin Diagnosis** and **Confidence Audit**.

## Step 1: The Cynefin GPS (Per Task Analysis)

Analyze the plan and current `@codebase` context. Categorize **EACH TASK** in the plan into one of these domains:

### 1. 🟢 Simple (Clear)

* **Definition:** Standard boilerplate, typo fixes, strict pattern matching.
* **Action:** Proceed if syntax is correct.

### 2. 🔵 Complicated

* **Definition:** Known unknowns. Requires expert knowledge (e.g., API integration, Logic changes).
* **Action:** Verify API contracts and types before proceeding.

### 3. 🟠 Complex

* **Definition:** Unknown unknowns. Unpredictable interactions (Race conditions, heavy refactoring).
* **Action:** The plan **MUST** include a "Probe" (experiment) step.

### 4. 🔴 Chaotic / ☁️ Confusion

* **Definition:** Crisis mode or Missing Context.
* **Action:** STOP. Request specific files/clarification.

## Step 2: The Architecture & Context Audit

* **Visuals:** Does the plan include Mermaid diagrams for complex logic?
* **Context:** Are all mentioned files loaded in the chat context?

---

## Output Report: The Pre-Flight Dashboard

Please generate a Doc summary in the following Markdown format({plan_name}-Pre-Flight-Review_YYYY-MM-DD_HHMM.md):

### 1. 🚦 Developer And Technical Summary

* **Overall Confidence Score:** [0-100]%
* **Status:** (🚀 Ready / ⚠️ Caution / 🛑 Stop)
* **Critical Blockers:** (List the top 1-2 issues preventing execution)

### 2. 📋 Task-by-Task Analysis

Create a table analyzing every step of the proposed plan:

| Step # | Task Summary | Cynefin Domain | Confidence | Risk / Missing Context |
| :--- | :--- | :--- | :--- | :--- |
| 1 | *Initialize repo* | 🟢 Simple | 100% | None |
| 2 | *Refactor Auth* | 🟠 Complex | 40% | Missing "Probe" step; `@auth.py` not loaded. |
| ... | ... | ... | ... | ... |

### 3. 🛑 Gap Analysis (The "Why")

For any task with **< 95% Confidence**, detail the specific issue:

* **Ambiguity:** (Which instruction is vague?)
* **Context:** (Which specific `@file` is missing?)
* **Safety:** (Is a test case missing?)

### 4. 🚀 Path to Green (Remediation)

Provide a checklist to fix the plan:

* [ ] **Add Files:** (List files to add to context)
* [ ] **Modify Plan:** (Exact text to insert into the plan, e.g., "Add a probe step for task 2")
* [ ] **Architecture:** (Request a diagram if missing)
