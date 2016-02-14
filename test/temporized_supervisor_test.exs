defmodule FakeServer do
  use GenServer
  def start_link, do: GenServer.start_link(__MODULE__,[])
  def init([]), do: {:stop, :die_too_soon}
end

defmodule TestSup1 do
  use TemporizedSupervisor
  import Bitwise

  def init(_) do
    supervise([
      worker(FakeServer,[])
    ], strategy: :one_for_one, max_restart: :infinity, delay_fun: fn count,_id-> 
      Agent.update(:restart_queue, &[:erlang.system_time(:milli_seconds)|&1])
      200*(1 <<< count) 
    end)
  end
end

defmodule TemporizedSupervisorTest do
  use ExUnit.Case

  test "exp backoff temporized restart" do
    IO.puts "start agent"
    Agent.start_link(fn->[] end, name: :restart_queue)
    start_ts = :erlang.system_time(:milli_seconds)
    IO.puts "start sup"
    TemporizedSupervisor.start_link(TestSup1,[])
    IO.puts "start wait"
    receive do after 5000-> :ok end
    IO.puts "end wait-> get restart_queue"
    queue = Agent.get(:restart_queue, & &1)
            |> Enum.map(& &1 - start_ts)
    IO.puts inspect(queue, pretty: true)
  end
end
