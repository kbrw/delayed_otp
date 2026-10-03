defmodule DelayedSupChildSpecTest do
  use ExUnit.Case

  @moduletag capture_log: true

  defmodule Worker do
    use GenServer

    def start_link(arg), do: GenServer.start_link(__MODULE__, arg)
    def launch(owner, id), do: start_link({owner, id})

    def init({owner, id}) do
      send(owner, {:started, id, self()})
      {:ok, id}
    end

    def handle_call(:identity, _from, id), do: {:reply, id, id}
  end

  defmodule BareWorker do
    use GenServer

    def start_link([]), do: GenServer.start_link(__MODULE__, [])
    def init([]), do: {:ok, []}
  end

  test "start_link accepts modern child specs mixed with legacy tuples" do
    supervisor = start_supervisor(children(self()))

    assert_receive {:started, :map, map_pid}, 1_000
    assert_receive {:started, :tuple, tuple_pid}, 1_000
    assert_receive {:started, :legacy, legacy_pid}, 1_000

    actual = Map.new(DelayedSup.which_children(supervisor), fn {id, pid, _, _} -> {id, pid} end)

    assert actual[:map] == map_pid
    assert actual[Worker] == tuple_pid
    assert actual[:legacy] == legacy_pid
    assert Process.alive?(actual[BareWorker])
    assert map_size(actual) == 4
    assert GenServer.call(map_pid, :identity) == :map
    assert DelayedSup.count_children(supervisor)[:active] == 4
  end

  test "start_child accepts map, module, module argument, and legacy specs" do
    supervisor = start_supervisor([])

    for child_spec <- children(self()) do
      assert {:ok, wrapper} = DelayedSup.start_child(supervisor, child_spec)
      assert Process.alive?(GenServer.call(wrapper, :delayed_pid))
    end

    assert_receive {:started, :map, map_pid}, 1_000
    assert_receive {:started, :tuple, tuple_pid}, 1_000
    assert_receive {:started, :legacy, legacy_pid}, 1_000

    actual = Map.new(DelayedSup.which_children(supervisor), fn {id, pid, _, _} -> {id, pid} end)

    assert actual[:map] == map_pid
    assert actual[Worker] == tuple_pid
    assert actual[:legacy] == legacy_pid
    assert Process.alive?(actual[BareWorker])
    assert map_size(actual) == 4
  end

  test "map specs preserve a custom start MFA and child metadata" do
    mfa = {Worker, :launch, [self(), :custom]}

    child_spec = %{
      id: :custom,
      start: mfa,
      restart: :transient,
      shutdown: :brutal_kill,
      type: :supervisor,
      modules: :dynamic
    }

    assert DelayedSup.Spec.map_childspec(child_spec) == %{
             child_spec
             | start: {DelayedSup.Spec, :start_delayed, [:custom, mfa, :brutal_kill]},
               shutdown: :infinity
           }

    supervisor = start_supervisor([child_spec])
    assert_receive {:started, :custom, worker}, 1_000
    assert [{:custom, ^worker, :supervisor, :dynamic}] = DelayedSup.which_children(supervisor)
  end

  test "minimal maps receive standard worker and supervisor defaults" do
    mfa = {GenServer, :start_link, [Worker, {self(), :minimal}]}
    worker_spec = %{id: :minimal, start: mfa}

    assert DelayedSup.Spec.map_childspec(worker_spec) == %{
             id: :minimal,
             start: {DelayedSup.Spec, :start_delayed, [:minimal, mfa, 5_000]},
             shutdown: :infinity,
             modules: [GenServer]
           }

    supervisor_mfa = {GenServer, :start_link, [Worker, {self(), :supervisor}]}
    supervisor_spec = %{id: :supervisor, start: supervisor_mfa, type: :supervisor}
    mapped_supervisor = DelayedSup.Spec.map_childspec(supervisor_spec)

    assert mapped_supervisor.start ==
             {DelayedSup.Spec, :start_delayed, [:supervisor, supervisor_mfa, :infinity]}

    assert mapped_supervisor.shutdown == :infinity
    assert mapped_supervisor.type == :supervisor
    assert mapped_supervisor.modules == [GenServer]

    supervisor = start_supervisor([worker_spec, supervisor_spec])
    assert_receive {:started, :minimal, _worker}, 1_000
    assert_receive {:started, :supervisor, _supervisor_worker}, 1_000
    assert {:ok, actual_worker_spec} = :supervisor.get_childspec(supervisor, :minimal)
    assert actual_worker_spec.restart == :permanent
    assert actual_worker_spec.type == :worker
    assert {:ok, actual_supervisor_spec} = :supervisor.get_childspec(supervisor, :supervisor)
    assert actual_supervisor_spec.restart == :permanent
    assert actual_supervisor_spec.type == :supervisor
  end

  test "modern map children restart with accumulated backoff" do
    owner = self()
    delay = 100
    child_spec = %{id: :connector, start: {GenServer, :start_link, [Worker, {owner, :connector}]}}

    supervisor =
      start_supervisor([child_spec],
        delay_fun: fn id, lifetime, acc ->
          send(
            owner,
            {:delay_computed, id, lifetime, acc, :erlang.monotonic_time(:milli_seconds)}
          )

          count = (acc || 0) + 1
          {delay * count, count}
        end
      )

    assert_receive {:started, :connector, first_worker}, 1_000
    first_ref = Process.monitor(first_worker)
    Process.exit(first_worker, :kill)
    assert_receive {:DOWN, ^first_ref, :process, ^first_worker, :killed}, 1_000
    assert_receive {:delay_computed, :connector, lifetime, nil, first_failure_at}, 1_000
    assert is_integer(lifetime) and lifetime >= 0

    assert_receive {:started, :connector, second_worker}, 1_000
    assert second_worker != first_worker
    second_ref = Process.monitor(second_worker)
    Process.exit(second_worker, :kill)
    assert_receive {:DOWN, ^second_ref, :process, ^second_worker, :killed}, 1_000
    assert_receive {:delay_computed, :connector, next_lifetime, 1, second_failure_at}, 1_000
    assert is_integer(next_lifetime) and next_lifetime >= 0
    assert second_failure_at - first_failure_at >= delay - 10

    assert_receive {:started, :connector, third_worker}, 1_000
    assert third_worker != second_worker

    assert [{:connector, ^third_worker, :worker, [GenServer]}] =
             DelayedSup.which_children(supervisor)

    assert Process.alive?(supervisor)
  end

  defp children(owner) do
    [
      %{id: :map, start: {GenServer, :start_link, [Worker, {owner, :map}]}},
      BareWorker,
      {Worker, {owner, :tuple}},
      DelayedSup.Spec.worker(Worker, [{owner, :legacy}], id: :legacy)
    ]
  end

  defp start_supervisor(children, options \\ []) do
    {:ok, supervisor} =
      DelayedSup.start_link(
        children,
        Keyword.merge([strategy: :one_for_one, max_restarts: 10], options)
      )

    Process.unlink(supervisor)

    on_exit(fn ->
      if Process.alive?(supervisor), do: DelayedSup.stop(supervisor)
    end)

    supervisor
  end
end
