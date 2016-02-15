defmodule DelayedSupTest do
  use ExUnit.Case
  require Logger

  setup_all do
    Agent.start_link(fn->true end, name: :working?)
    Agent.start_link(fn->[] end, name: :restart_queue)

    defmodule Elixir.FakeServer do
      use GenServer
      def init([]) do
        if Agent.get(:working?, & &1), 
          do: {:ok,[]},
          else: {:stop, :die_too_soon}
      end
    end
    
    defmodule Elixir.TestSup1 do
      use DelayedSup
      import Bitwise
    
      @reset_backoff_lifetime 5_000
      @init_backoff_delay 200
      def init(_) do
        supervise([
          worker(GenServer,[FakeServer,[],[name: FakeServer]])
        ], strategy: :one_for_one, max_restarts: 9999, max_seconds: 3600, 
           delay_fun: fn _id,lifetime,count_or_nil->
               count = count_or_nil || 0
               Agent.update(:restart_queue, &[:erlang.system_time(:milli_seconds)|&1])
               if lifetime > @reset_backoff_lifetime, 
                 do: {0,0}, 
                 else: {@init_backoff_delay*(1 <<< count),count+1}
          end)
      end
    end
    :ok
  end

  @test_duration 5_000
  @test_precision 100
  test "exp backoff delayed restart" do
    Agent.update(:restart_queue,fn _->[] end)
    Agent.update(:working?,fn _->false end)
    start_ts = :erlang.system_time(:milli_seconds)
    {:ok,pid} = DelayedSup.start_link(TestSup1,[])
    receive do after @test_duration-> :ok end
    queue = Agent.get(:restart_queue, & &1) |> Enum.map(& &1 - start_ts)
    expected = Stream.iterate({0,0},fn {i,dur}-> {i+1,dur + 200 * :math.pow(2,i)} end) |> 
               Stream.map(& trunc(elem(&1,1))) |> Enum.take_while(& &1 < @test_duration) |> Enum.reverse

    assert Enum.map(expected,& div(&1,@test_precision)) == Enum.map(queue,& div(&1,@test_precision))
    Process.exit(pid,:shutdown)
  end

  @server_recovery_after 2000
  @server_death_after 6100
  @test_duration 10_000
  @test_precision 100
  test "exp backoff with recovery" do
    Agent.update(:restart_queue,fn _->[] end)
    Agent.update(:working?,fn _->false end)
    start_ts = :erlang.system_time(:milli_seconds)
    {:ok,pid} = DelayedSup.start_link(TestSup1,[])
    receive do after @server_recovery_after-> :ok end
    Agent.update(:working?,& !&1)
    receive do after @server_death_after-> :ok end
    Agent.update(:working?,& !&1)
    Process.exit(Process.whereis(FakeServer),:new_death)
    receive do after @test_duration-@server_death_after-@server_recovery_after-> :ok end
    queue = Agent.get(:restart_queue, & &1) |> Enum.map(& &1 - start_ts)

    assert [95, 87, 83, 81, 81, 30, 14, 6, 2, 0] == Enum.map(queue,& div(&1,@test_precision))
    Process.exit(pid,:shutdown)
  end
end
