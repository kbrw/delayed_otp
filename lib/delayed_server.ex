defmodule DelayedServer do
  use GenServer
  require Logger
  @doc """
  starts process `apply(mod,options[:function] || :start_link,args)` but
  - proc death can only occur `options[:delay]` minimum after process creation
  - on sup termination: if proc exit takes longer than `options[:shutdown]`, then brutal kill it
    (options[:shutdown] is equivalent to the sup child_spec one: :brutal_kill | int_timeout | :infinity)
  """
  def start_link(mod,args,options \\ []), do: 
    GenServer.start_link(__MODULE__, {mod,args,options})

  def init({mod,args,options}) do
    Process.flag(:trap_exit, true)
    delay = options[:delay] || 100
    shutdown = options[:shutdown] || 100
    fun = options[:function] || :start_link
    name = options[:name] || inspect({mod,fun})
    call_timeout = options[:call_timeout] || 5000
    Logger.debug("starting #{name} with delay of #{delay}")
    started = :erlang.system_time(:milli_seconds)
    case apply(mod, fun, args) do
      {:ok, pid} ->
        {:ok, %{name: name, delay: delay, started: started, pid: pid, shutdown: shutdown, call_timeout: call_timeout}}
      :ignore -> :ignore
      err ->
        {:ok, delayed_death(err, %{name: name, delay: delay, started: started, pid: nil, shutdown: shutdown, call_timeout: call_timeout})}
    end
  end

  def delayed_death(reason, state) do
    lifetime = :erlang.system_time(:milli_seconds) - state.started
    Process.send_after(self, {:die, reason, lifetime}, max(state.delay - lifetime, 0))
    %{state| pid: nil}
  end

  def handle_call(:delayed_pid, _from, state), do: {:reply,state.pid,state}
  def handle_call(req, _from, state), do: {:reply,GenServer.call(state.pid,req, state.call_timeout),state}
  def handle_cast(req, state), do: (GenServer.cast(state.pid,req); {:noreply,state})

  def handle_info({:EXIT,_pid,reason}, state) do
    Logger.info("Delayed proc #{state.name} failed : #{inspect reason}")
    {:noreply, delayed_death(reason, state)}
  end
  def handle_info({:die, reason, lifetime}, state), do: {:stop, {:delayed_death,lifetime,reason}, state}
  def handle_info(msg, state), do: (send(state.pid, msg); {:noreply, state})

  def terminate(_, %{pid: nil}), do: :ok
  def terminate(_, %{pid: pid, shutdown: :brutal_kill}), do: Process.exit(pid, :kill)
  def terminate(reason, %{pid: pid, shutdown: shutdown, name: name}) do
    Process.exit(pid, reason)
    receive do
      {:EXIT, ^pid, _}-> :ok
    after shutdown->
      Logger.warn("Delayed server #{name} failed to terminate within #{shutdown}, killing it brutally")
      Process.exit(pid, :kill)
      receive do {:EXIT, ^pid, _}-> :ok end
    end
  end
end
