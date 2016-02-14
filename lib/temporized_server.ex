defmodule TemporizedServer do
  use GenServer
  require Logger
  @doc """
  starts process `apply(mod,options[:function] || :start_link,args)` but
  - proc death can only occur `options[:delay]` minimum after process creation
  - on sup termination: if proc exit takes longer than `options[:shutdown_timeout]`, then brutal kill it
  """
  def start_link(mod,args,options \\ []), do: GenServer.start_link(__MODULE__, {mod,args,options})

  def init(mod,args,options) do
    Process.flag(:trap_exit, true)
    delay = options[:delay] || 100
    shutdown_timeout = options[:shutdown_timeout] || 100
    fun = options[:function] || :start_link
    name = options[:name] || inspect({mod,fun,args})
    call_timeout = options[:call_timeout] || 5000
    Logger.debug("starting #{name} with delay of #{delay}")
    started = :erlang.system_time(:milli_seconds)
    case apply(mod, fun, args) do
      {:ok, pid} ->
        {:ok, %{name: name, delay: delay, started: started, pid: pid, shutdown_timeout: shutdown_timeout, call_timeout: call_timeout}}
      err ->
        {:ok, temporized_death(err, %{name: name, delay: delay, started: started, pid: nil, shutdown_timeout: shutdown_timeout, call_timeout: call_timeout})}
    end
  end

  def temporized_death(reason, state) do
    lifetime = :erlang.system_time(:milli_seconds) - state.started
    Process.send_after(self, {:die, reason}, max(state.delay - lifetime, 0))
    %{state| pid: nil}
  end

  def handle_call(:temporized_pid, _from, state), do: {:reply,state.pid,state}
  def handle_call(req, _from, state), do: {:reply,GenServer.call(state.pid,req, state.call_timeout),state}
  def handle_cast(req, state), do: (GenServer.cast(state.pid,req); {:noreply,state})

  def handle_info({:EXIT,_pid,reason}, state) do
    Logger.info("Temporized proc #{state.name} failed : #{inspect reason}")
    {:noreply, temporized_death(reason, state)}
  end
  def handle_info({:die, reason}, state), do: {:stop, reason, state}
  def handle_info(msg, state), do: (send(state.pid, msg); {:noreply, state})

  def terminate(_, %{pid: nil}), do: :ok
  def terminate(reason, %{pid: pid, shutdown_timeout: timeout, name: name}) do
    Process.exit(pid, reason)
    receive do
      {:EXIT, ^pid, _}-> :ok
    after timeout->
      Logger.warn("Temporized server #{name} failed to terminate within #{timeout}, killing it brutally")
      Process.exit(pid, :kill)
      receive do {:EXIT, ^pid, _}-> :ok end
    end
  end
end
