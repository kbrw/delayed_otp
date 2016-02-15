# TemporizedSupervisor

With exactly the same API as `Supervisor`, create a supervisor which allows you
to control a minimum delay for the supervised children to die.

You can for instance : 

- get an Exponential backoff restarting strategy for children
- normalized death time for port managed external processes 

Useful to manage external service in Elixir supervisors.

## Usage

All the same as `Supervisor`, but a new option is available: `:delay_fun` which is a
function returning the minimum lifetime of a child in millisecond (child death will be delayed
if it occurs too soon).

The signature of `:delay_fun` is: `(restart_count :: integer, child_id :: term) -> ms_delay_death :: integer`

Below an example usage with an exponential backoff strategy: (200*2^count) ms
delay where the backoff count is reset when previous run lifetime was > 5 secondes.

```Elixir
import TemporizedSupervisor.Spec
import Bitwise
@reset_backoff_lifetime 5_000
@init_backoff_delay 200
TemporizedSupervisor.start_link([
  worker(MyServer1,[]),
  worker(MyServer2,[])
], restart_strategy: :one_for_one, 
   delay_fun: fn _id,lifetime,count_or_nil->
               count = count_or_nil || 0
               if lifetime > @reset_backoff_lifetime, 
                 do: {0,0}, 
                 else: {@init_backoff_delay*(1 <<< count),count+1}
          end)
```

## How it works

The created "supervisor" creates actually the following supervision tree :

`supervise([child1,child2], strategy: :one_for_one)` =>

```
+--------------+       +----------+      +---------+
| Supervisor   +------>+TempServer+----->+ Child1  |
+--------------+       +----------+      +---------+
               |       +----------+      +---------+
               +------>+TempServer+----->+ Child2  |
                       +----------+      +---------+
```

`TempServer` (actually `TemporizedServer`) is an intermediate process
which can delay its death relatively to its linked server.

Restart Counter, and delay computation function are kept into the supervisor
process dictionnary.

The shutdown strategy (brutal kill or max shutdown duration) is handled by the temp server.

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

