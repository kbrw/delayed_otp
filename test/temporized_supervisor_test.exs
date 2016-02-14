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
    ], strategy: :one_for_one, max_restarts: 9999, max_seconds: 3600, delay_fun: fn count,_id-> 
      Agent.update(:restart_queue, &[:erlang.system_time(:milli_seconds)|&1])
      200*(1 <<< count)
    end)
  end
end

defmodule TemporizedSupervisorTest do
  use ExUnit.Case
  require Logger

  @test_duration 5_000
  @test_precision 100

  test "exp backoff temporized restart" do
    Agent.start_link(fn->[] end, name: :restart_queue)
    start_ts = :erlang.system_time(:milli_seconds)
    TemporizedSupervisor.start_link(TestSup1,[])
    receive do after @test_duration-> :ok end
    queue = Agent.get(:restart_queue, & &1) |> Enum.map(& &1 - start_ts)
    expected = Stream.iterate({0,0},fn {i,dur}-> {i+1,dur + 200 * :math.pow(2,i)} end) |> 
               Stream.map(& trunc(elem(&1,1))) |> Enum.take_while(& &1 < @test_duration) |> Enum.reverse

    assert Enum.map(expected,& div(&1,@test_precision)) == Enum.map(queue,& div(&1,@test_precision))
  end
end
