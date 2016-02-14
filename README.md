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

The signature of `:delay_fun` is: `(restart_count :: integer, child_id :: term) -> ms_delay_death :: integer`

Below an example usage with an exponential backoff strategy: (200*2^count) ms delay.

```Elixir
import TemporizedSupervisor.Spec
import Bitwise
TemporizedSupervisor.start_link([
  worker(MyServer1,[]),
  worker(MyServer2,[])
], restart_strategy: :one_for_one, delay_fun: fn count,_id-> 200*(1 <<< count) end)
```

## How it works

The created "supervisor" creates actually the following supervision tree :

`supervise([child1,child2], strategy: :one_for_one)` =>

```

                         +--------------+
                         |  DelayManager|
+--------------+-------> +--------------+
|   FrontSup   |         +--------------+       +----------+      +---------+
+--------------+-------> |  MiddleSup   +------>+TempServer+----->+ Child1  |
                         +--------------+       +----------+      +---------+
                                        |       +----------+      +---------+
                                        +------>+TempServer+----->+ Child2  |
                                                +----------+      +---------+
```

`DelayManager` maintains a restart count by `child_id` and the
`delay_fun`.
`TempServer` (actually `TemporizedServer`) is an intermediate process
which can delay its death relatively to its linked server.

When you call `TemporizedSupervisor` functions on `FrontSup`, it
actually proxify the query to the `MiddleSup`.

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

