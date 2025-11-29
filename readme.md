## Contribution
### The PR Checklist
Check each of these before submitting or approving a pull request.
- The design and logic are to your satisfaction.
- The PR focuses on one feature and its required architecture changes, *or* a refactor of one aspect of the architecture.
- All new functions and data types are annotated.
- Any function or data type that has changed is still correctly annotated.
- Modules that don't coordinate this particular game can theoretically work in any game.
- Modules that coordinate this particular game don't implement feature functionality.
- Any two-way dependencies have a specific, documented justification.
- All commented code is exclusively for debugging purposes, and is not zombie code.
- The parts of the game that the code touches still behave as expected.
- There is no unexpected jump in CPU cost.