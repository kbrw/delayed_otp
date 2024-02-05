defmodule DelayedSup do
  @moduledoc """
    The API is exactly the same as Elixir stdlib `Supervisor`,
    except that the supervisor options now supports `:delay_fun` as
    an option.

    The signature of `:delay_fun` is: `(child_id :: term, ms_lifetime :: integer, acc :: term) -> {ms_delay_death :: integer, newacc:: term}`
    The second argument `ms_lifetime` is the lifetime of the previously dead process.
    First start accumulator is `nil`.

    This delay will be the minimum lifetime of the child in millisecond : child death will be delayed
    if it occurs too soon.

    Below an example usage with an exponential backoff strategy: (200*2^count) ms
    delay where the backoff count is reset when previous run lifetime was > 10 minutes.

        iex> import Bitwise
        ...> DelayedSup.start_link([
        ...>   MyServer1,
        ...>   MyServer2
        ...> ], restart_strategy: :one_for_one, delay_fun: fn _id, lifetime, acc ->
        ...>    delay = if lifetime > :timer.minutes(10), do: 1, else: min((acc || 200) * 2, :timer.minutes(10))
        ...>    {delay, delay}
        ...>  end)
  """

  ## erlang supervisor callback delegates
  use GenServer
  def init({supname,mod,arg}) do
    {sup_spec,options} = mod.init(arg)
    Process.put(:delay_fun,options[:delay_fun] || fn _,_,_-> {0,0} end)
    :supervisor.init({erl_supname(supname), DelayedSup.Default, sup_spec})
  end

  defp erl_supname(nil), do: :self
  defp erl_supname(sup) when is_atom(sup), do: {:local,sup}
  defp erl_supname(sup), do: sup

  def handle_info({:EXIT,pid,{:delayed_death,lifetime,reason}},state) do
    {:reply,children,_} = :supervisor.handle_call(:which_children,nil,state)
    if id = Enum.find_value(children, fn {id, ^pid, _worker, _modules} -> id ; _ -> false end) do
      acc = Process.get({:delay_acc, id}, nil)
      {delay, acc} = Process.get(:delay_fun).(id, lifetime, acc)
      Process.put({:delay_acc, id}, acc)
      Process.put({:next_delay, id}, delay)
    end
    :supervisor.handle_info({:EXIT,pid,reason},state)
  end
  def handle_info(req,state), do: :supervisor.handle_info(req,state)

  defdelegate terminate(r,s), to: :supervisor

  defdelegate code_change(vsn,s,extra), to: :supervisor

  defdelegate handle_call(req,rep_to,s), to: :supervisor

  defdelegate handle_cast(req,s), to: :supervisor

  ## Elixir Supervisor API
  def start_link(children, options) when is_list(children) do
    start_link(DelayedSup.Default, DelayedSup.init(children, options), options)
  end

  def start_link(module, arg, options \\ []) when is_list(options) do
    GenServer.start_link(__MODULE__, {options[:name], module, arg}, options)
  end

  def which_children(supervisor) do
    for {id,pid,worker,modules} <- Supervisor.which_children(supervisor) do
      {id, GenServer.call(pid, :delayed_pid), worker, modules}
    end
  end

  def start_child(supervisor, child_spec) do
    Supervisor.start_child(supervisor, DelayedSup.map_childspec(child_spec))
  end

  defdelegate stop(sup), to: Supervisor

  defdelegate stop(sup, r), to: Supervisor

  defdelegate stop(sup, r, t), to: Supervisor

  defdelegate count_children(sup), to: Supervisor

  defdelegate terminate_child(sup, child), to: Supervisor

  defdelegate delete_child(sup, childid), to: Supervisor

  defdelegate restart_child(sup, childid), to: Supervisor

  defmacro __using__(_) do
    quote location: :keep do
      use Supervisor
    end
  end

  def init(children, opts) do
    {:ok, {opts_map,expanded_children}} = Supervisor.init(children, opts)
    {{:ok, {opts_map, Enum.map(expanded_children,&map_childspec/1)}}, opts}
  end

  def map_childspec(child_spec) do
    Map.put(%{child_spec| start: {__MODULE__,:start_delayed,[child_spec]}}, :shutdown, :infinity)
  end

  def start_delayed(%{start: {m,f,a}, id: id}=child_spec) do
    # reproduce default elixir configuration for shutdown strategy
    shutdown = case child_spec do
      %{shutdown: shutdown}-> shutdown
      %{type: :supervisor}-> :infinity
      _-> 5_000
    end
    DelayedServer.start_link(m, a, function: f, delay: Process.get({:next_delay,id},0), shutdown: shutdown)
  end
end
