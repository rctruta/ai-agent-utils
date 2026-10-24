# The analysis layer — install it when the trigger fires, not before

This is not seeded into new projects. An empty stub in every repository is
dead weight, and dead weight gets deleted: `checkpoint.sh` was installed in
eight repositories, used in none, and removed at registry version 12.

## The trigger

**Install this once a project has produced a corpus of results that someone
has asked a question about twice.**

Two is the number because the first question is legitimately a one-off. The
second is the signal: somebody is now going to keep asking, and without a
named place for the answer every question gets a fresh throwaway parser that
nobody finds again.

The shape to watch for: hundreds of result files, dozens of runs, and **one**
reusable analysis module -- every other analysis written for a single question
and abandoned. A project is usually well past this trigger before anyone
notices.

## What to install

    install_api_layer.sh            copy the skeletons into ./api/

Three modules, in this order. The order is the point — each one depends on
the previous existing, and skipping ahead puts logic in the wrong place.

**`catalog.py` — what exists.** Reads the corpus and says what is in it.
Interprets nothing. Keeping reading and interpreting apart means a change to
how a result is scored cannot silently change which results are found.

**`operations.py` — the questions.** Name the four or five questions actually
asked of this corpus. Not the questions that might be asked: the ones someone
has already asked twice. Each returns a plain dict, so one implementation
serves a CLI, a notebook and an MCP tool without the logic migrating into
whichever called first.

**`metrics.py` — the numbers, derived.** Every figure the project would quote
outward, produced from the corpus rather than typed, each carrying a
`definition` field saying in words what it counts.

That definition field is not documentation. A count of trace *files* is not a
count of *graded runs* -- some files hold no model output at all -- and the
two differ by enough to matter. Quoted without its definition, the first
becomes the second with nobody lying at any step. A number with no stated
definition can be quoted as anything that sounds close.

## Then, and only then, expose it

A CLI first. An MCP server is a thin wrapper over operations that already
exist; built first, the operations end up written inside the server, which is
the one-off problem with a protocol on top.

Register the metrics as executable claims so the numbers cannot drift:

    - id: <project>_<metric>
      check: command
      command: <interpreter> -m api.cli metrics --name <metric>
      expect: "<value>"

A metric that becomes wrong is then a failing check rather than a document
nobody rereads.
