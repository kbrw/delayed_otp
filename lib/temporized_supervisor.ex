defmodule TemporizedSupervisor do
  @moduledoc """
    The API is exactly the same as Elixir stdlib `Supervisor`,
    except that the supervisor options now supports `:delay_fun` as
    an option.

    The signature of `:delay_fun` is: `(restart_count :: integer, child_id :: term) -> ms_delay_death :: integer`,
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
      {Supervisor.Spec.supervise(Enum.map(children,&map_childspec/1), options),options}
    end

    def map_childspec({id,mfa,restart,shutdown,worker,modules}) do
      {id,{__MODULE__, :start_temporized, [id,mfa,shutdown]},restart,:infinity,worker,modules}
    end

    def start_temporized(id,{m,f,a},shutdown) do
      restart_count = Process.get(id, 0)
      Process.put(id, restart_count + 1)
      delay = Process.get(:delay_fun).(restart_count,id)
      TemporizedServer.start_link(m, a, function: f, delay: delay, shutdown: shutdown)
    end

    defdelegate [worker(mod,args), worker(mod,args,opts),
                 supervisor(mod,args), supervisor(mod,args,opts)], to: Supervisor.Spec
  end

  defmodule ProxySup do
    @behaviour :supervisor
    def init({mod,arg}) do
      {sup_spec,options} = mod.init(arg)
      Process.put(:delay_fun,options[:delay_fun] || fn _,_->0 end)
      sup_spec
    end
  end
  
  def start_link(children, options) when is_list(children), do:
    start_link(Supervisor.Default, Spec.supervise(children, options), options)
  def start_link(module, arg, options \\ []) when is_list(options), do:
    Supervisor.start_link(ProxySup,{module,arg},options)

  def which_children(supervisor) do
    for {id,pid,worker,modules}<-Supervisor.which_children(supervisor) do
      {id,GenServer.call(pid,:temporized_pid),worker,modules}
    end
  end

  def start_child(supervisor, child_spec) do
    Supervisor.start_child(supervisor, MiddleSup.map_childspec(child_spec))
  end

  defdelegate [stop(sup),stop(sup,r),stop(sup,r,t), count_children(sup), terminate_child(sup,child), 
               delete_child(sup,childid), restart_child(sup,childid)], to: Supervisor

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour :supervisor
      import TemporizedSupervisor.Spec
    end
  end
end
