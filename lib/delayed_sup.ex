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
    delay where the backoff count is reset when previous run lifetime was > 5 secondes.

        iex> import DelayedSup.Spec
        ...> import Bitwise
        ...> DelayedSup.start_link([
        ...>   worker(MyServer1,[]),
        ...>   worker(MyServer2,[])
        ...> ], restart_strategy: :one_for_one, delay_fun: fn count,_id-> 200*(1 <<< count) end)
  """

  ## erlang supervisor callback delegates
  use GenServer
  def init({supname,mod,arg}) do
    {sup_spec,options} = mod.init(arg)
    Process.put(:delay_fun,options[:delay_fun] || fn _,_->0 end)
    :supervisor.init({erl_supname(supname), Supervisor.Default, sup_spec})
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
    start_link(Supervisor.Default, DelayedSup.Spec.supervise(children, options), options)
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
    Supervisor.start_child(supervisor, DelayedSup.Spec.map_childspec(child_spec))
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
      @behaviour :supervisor
      import DelayedSup.Spec
    end
  end

  defmodule Spec do
    def supervise(children, options) do
      {Supervisor.Spec.supervise(Enum.map(children,&map_childspec/1), options),options}
    end

    def map_childspec({id,mfa,restart,shutdown,worker,modules}) do
      {id,{__MODULE__, :start_delayed, [id,mfa,shutdown]},restart,:infinity,worker,modules}
    end

    def start_delayed(id,{m,f,a},shutdown) do
      DelayedServer.start_link(m, a, function: f, delay: Process.get({:next_delay,id},0), shutdown: shutdown)
    end

    defdelegate worker(mod, args), to: Supervisor.Spec

    defdelegate worker(mod, args, opts), to: Supervisor.Spec

    defdelegate supervisor(mod, args), to: Supervisor.Spec

    defdelegate supervisor(mod, args, opts), to: Supervisor.Spec
  end
end
