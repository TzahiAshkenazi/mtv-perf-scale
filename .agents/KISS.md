## **KISS Principle for Problem Solving**

**Core Philosophy:**
- **Keep It Stupid Simple** - Always start with the simplest possible solution
- Complex problems often have elegant, straightforward solutions
- Avoid over-engineering when a direct approach works

**Problem-Solving Process:**
1. **Step Back First** - Before diving into complex solutions, ask:
   - "What's the core issue here?"
   - "What's the simplest way to solve this?"
   - "Am I overcomplicating this?"

2. **Start Simple** - Begin with the most direct approach:
   - Use basic string operations before complex regex
   - Try line-by-line processing before multi-pass algorithms
   - Test simple logic before adding edge cases

3. **Iterate Minimally** - Only add complexity when simple solutions fail:
   - Add one feature at a time
   - Test each addition
   - Remove unnecessary steps

**Red Flags (Stop and Simplify):**
- Solution has more than 5 steps
- Multiple nested regex operations
- Complex state management for simple text processing
- "This should handle all edge cases" thinking

**Success Pattern:**
- User suggests simple approach (e.g., "check line length")
- Simple approach works better than complex solution
- Less code = fewer bugs = easier maintenance

**Mantra:** *"The best code is the code you don't have to write."*
