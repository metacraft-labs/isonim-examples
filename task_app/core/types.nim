## task_app/core/types.nim — plain-value types for the task app.
##
## EX-M17: the `Task` shape lives here so both `services/fake_db.nim`
## and `task_app/core/vm.nim` can import it without forming a cycle
## (the VM imports `fake_db`; `fake_db` imports the task type from
## here; the VM re-exports `Task` for downstream consumers).

type
  Task* = object
    ## A single task. Value type — copied freely, no shared identity
    ## beyond `id`. The id is assigned by the FakeDb at `saveTask` time
    ## (when the incoming task's id is 0); it is monotonic per FakeDb
    ## instance and stable across the resource's lifetime.
    id*: int
    name*: string
    completed*: bool
