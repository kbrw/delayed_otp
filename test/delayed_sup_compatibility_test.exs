defmodule DelayedSupCompatibilityTest do
  use ExUnit.Case

  @moduletag capture_log: true

  defmodule Worker do
    use GenServer

    def start_link(owner, id) do
      GenServer.start_link(__MODULE__, {owner, id})
    end

    def init({owner, id}) do
      send(owner, {:started, id, self()})
      {:ok, []}
    end
  end

  test "delayed child death preserves one_for_all restarts and backoff on newer OTP" do
    owner = self()
    delay = 200
    reason = {:shutdown, :connection_closed}

    children =
      for id <- [:connector, :heartbeat] do
        DelayedSup.Spec.worker(Worker, [owner, id], id: id)
      end

    {:ok, supervisor} =
      DelayedSup.start_link(children,
        strategy: :one_for_all,
        max_restarts: 10,
        max_seconds: 5,
        delay_fun: fn id, lifetime, acc ->
          send(
            owner,
            {:delay_computed, id, lifetime, acc, :erlang.monotonic_time(:milli_seconds)}
          )

          {delay, (acc || 0) + 1}
        end
      )

    Process.unlink(supervisor)

    on_exit(fn ->
      if Process.alive?(supervisor), do: DelayedSup.stop(supervisor)
    end)

    supervisor_ref = Process.monitor(supervisor)
    assert_receive {:started, :connector, connector}, 1_000
    assert_receive {:started, :heartbeat, heartbeat}, 1_000
    connector_ref = Process.monitor(connector)
    heartbeat_ref = Process.monitor(heartbeat)

    Process.exit(connector, reason)

    assert_receive {:DOWN, ^connector_ref, :process, ^connector, ^reason}, 1_000
    assert_receive {:delay_computed, :connector, lifetime, nil, first_failure_at}, 1_000
    assert is_integer(lifetime) and lifetime >= 0
    assert_receive {:DOWN, ^heartbeat_ref, :process, ^heartbeat, :shutdown}, 1_000
    assert_receive {:started, :connector, restarted_connector}, 1_000
    assert_receive {:started, :heartbeat, restarted_heartbeat}, 1_000
    assert restarted_connector != connector
    assert restarted_heartbeat != heartbeat

    restarted_connector_ref = Process.monitor(restarted_connector)
    restarted_heartbeat_ref = Process.monitor(restarted_heartbeat)
    Process.exit(restarted_connector, reason)

    assert_receive {:DOWN, ^restarted_connector_ref, :process, ^restarted_connector, ^reason},
                   1_000

    assert_receive {:delay_computed, :connector, next_lifetime, 1, second_failure_at}, 1_000
    assert is_integer(next_lifetime) and next_lifetime >= 0
    # Allow for millisecond rounding between the system and monotonic clocks.
    assert second_failure_at - first_failure_at >= delay - 10

    assert_receive {:DOWN, ^restarted_heartbeat_ref, :process, ^restarted_heartbeat, :shutdown},
                   1_000

    assert_receive {:started, :connector, final_connector}, 1_000
    assert_receive {:started, :heartbeat, final_heartbeat}, 1_000
    assert final_connector != restarted_connector
    assert final_heartbeat != restarted_heartbeat

    assert DelayedSup.which_children(supervisor)
           |> Enum.map(fn {id, pid, _type, _modules} -> {id, pid} end)
           |> Enum.sort() == [connector: final_connector, heartbeat: final_heartbeat]

    assert Process.alive?(supervisor)
    refute_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}, 0
    refute_receive {:delay_computed, :heartbeat, _, _, _}, 0
  end
end
