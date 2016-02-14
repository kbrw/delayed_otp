defmodule TemporizedSupervisor do
  @moduledoc """
    The API is exactly the same as Elixir stdlib `Supervisor`,
    except that the supervisor options now supports `:delay_fun` as
    an option.

    The signature of `:delay_fun` is: `delay_fun(restart_count :: integer, child_id :: term) :: integer`,
    it takes the restart count and the id of the child and returns a delay in millisecond.

    This delay will be the minimum lifetime of the child in millisecond : child death will be delayed
    if it occurs too soon.

    Example usage: exponential backoff restart

        iex> import TemporizedSupervisor.Spec
        ...> import Bitwise
        ...> TemporizedSupervisor.start_link([
        ...>   worker(MyServer1,[]),
        ...>   worker(MyServer2,[])
        ...> ], restart_strategy: :one_for_one, delay_fun: fn count,_id-> 200*(1 <<< count) end)
  """

  defmodule Spec do
    def supervise(children, options) do
      ids = for {id,_,_,_,_,_}<-children, do: id
      Supervisor.Spec.supervise([
        Supervisor.Spec.worker(DelayManager, [options[:delay_fun],ids]),
        Supervisor.Spec.supervisor(MiddleSup, [children,Dict.drop(options,[:delay_fun,:name])])
      ], strategy: :one_for_all, max_restarts: 0)
    end

    defdelegate [worker(mod,args,opts),supervisor(mod,args,opts)], to: Supervisor.Spec
  end

  defmodule MiddleSup do
    def map_childspec({id,mfa,restart,shutdown,worker,modules}) do
      {id,{__MODULE__, :start_temporized, [id,mfa]},restart,shutdown,worker,modules}
    end

    def start_link(children,options) do
      Supervisor.start_link(Enum.map(children,&map_childspec/1), options)
    end

    def start_temporized(id,{m,f,a}) do
      [delay_manager_sup|_] = Process.get(:"$ancestors")
      [{_,delay_manager,_,_}|_] = Supervisor.which_children(delay_manager_sup)
      delay = GenServer.call(delay_manager,{:delay,id})
      TemporizedServer.start_link(m, a, function: f, delay: delay)
    end
  end

  defmodule DelayManager do
    use GenServer
    def start_link(delay_fun,ids), do:
      GenServer.start_link(__MODULE__,{delay_fun,ids |> Enum.map(&{&1,0}) |> Enum.into(%{})})
    def handle_call({:delay,id},_,{delay_fun,counters}), do:
      {:reply,delay_fun.(counters[id],id),{delay_fun,Dict.update!(counters,id,& &1 + 1)}}
  end

  defp middle_sup(supervisor) do
    [_,{_,sup_pid,_,_}] = Supervisor.which_children(supervisor)
    sup_pid
  end
  
  def start_link(children, options) when is_list(children), do:
    start_link(Supervisor.Default, Spec.supervise(children, options), options)
  def start_link(module, arg, options \\ []) when is_list(options), do:
    Supervisor.start_link(module,arg,options)

  def count_children(supervisor), do:
    Supervisor.count_children(middle_sup(supervisor))

  def which_children(supervisor) do
    for {id,pid,worker,modules}<-Supervisor.which_children(middle_sup(supervisor)) do
      {id,GenServer.call(pid,:temporized_pid),worker,modules}
    end
  end

  def start_child(supervisor, child_spec) do
    Supervisor.start_child(middle_sup(supervisor), MiddleSup.map_childspec(child_spec))
  end

  def terminate_child(supervisor, child) do
    Supervisor.terminate_child(middle_sup(supervisor), child)
  end

  def delete_child(supervisor, child_id) do
    Supervisor.delete_child(middle_sup(supervisor), child_id)
  end

  def restart_child(supervisor, child_id) do
    Supervisor.restart_child(middle_sup(supervisor), child_id)
  end

  defdelegate [stop(sup),stop(sup,r),stop(sup,r,t)], to: Supervisor

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour :supervisor
      import TemporizedSupervisor.Spec
    end
  end
end
