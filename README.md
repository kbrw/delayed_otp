# TemporizedSupervisor

With exactly the same API as `Supervisor`, create a supervisor which allows you
to control a minimum delay for the supervised children to die.

You can for instance : 

- get an Exponential backoff restarting strategy for children
- normalized death time for port managed external processes 

## Usage

All the same as `Supervisor`, but a new option is available: `:delay_fun` which is a
function returning the minimum lifetime of a child in millisecond (child death will be delayed
if it occurs too soon).

The signature of `:delay_fun` is: `delay_fun(restart_count :: integer, child_id :: term) :: integer`

```Elixir
import TemporizedSupervisor.Spec
import Bitwise
TemporizedSupervisor.start_link([
  worker(MyServer1,[]),
  worker(MyServer2,[])
], restart_strategy: :one_for_one, delay_fun: fn count,_id-> 200*(1 <<< count) end)
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `temporized_supervisor` to your list of dependencies in `mix.exs`:

        def deps do
          [{:temporized_supervisor, "~> 0.0.1"}]
        end

  2. Ensure `temporized_supervisor` is started before your application:

        def application do
          [applications: [:temporized_supervisor]]
        end

