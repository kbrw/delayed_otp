defmodule DelayedSup do
  @moduledoc """
    The API is exactly the same as Elixir stdlib `Supervisor`,
    except that the supervisor options now supports `:delay_fun` as
    an option.

    The signature of `:delay_fun` is: `(restart_count :: integer, child_id :: term) -> ms_delay_death :: integer`,
    it takes the restart count and the id of the child and returns a delay in millisecond.

    This delay will be the minimum lifetime of the child in millisecond : child death will be delayed
    if it occurs too soon.

    Example usage: exponential backoff restart

        iex> import DelayedSup.Spec
        ...> import Bitwise
        ...> DelayedSup.start_link([
        ...>   worker(MyServer1,[]),
        ...>   worker(MyServer2,[])
        ...> ], restart_strategy: :one_for_one, delay_fun: fn count,_id-> 200*(1 <<< count) end)
  """

  ## erlang supervisor callback delegates
  use GenServer
  def init({supref,mod,arg}) do
    {sup_spec,options} = mod.init(arg)
    Process.put(:delay_fun,options[:delay_fun] || fn _,_->0 end)
    :supervisor.init({supref, Supervisor.Default, sup_spec})
  end
  def handle_info({:EXIT,pid,{:delayed_death,lifetime,reason}},state) do
    {:reply,children,_} = :supervisor.handle_call(:which_children,nil,state)
    if id=Enum.find_value(children, fn {id,^pid,worker,modules}->id ; _->false end) do
      acc = Process.get({:delay_acc,id},nil)
      {delay,acc} = Process.get(:delay_fun).(id,lifetime,acc)
      Process.put({:delay_acc,id},acc)
      Process.put({:next_delay,id}, delay)
    end
    :supervisor.handle_info({:EXIT,pid,reason},state)
  end
  def handle_info(req,state), do: :supervisor.handle_info(req,state)

  defdelegate [terminate(r,s),code_change(vsn,s,extra),handle_call(req,rep_to,s), handle_cast(req,s)], to: :supervisor

  ## Elixir Supervisor API
  def start_link(children, options) when is_list(children), do:
    start_link(Supervisor.Default, Spec.supervise(children, options), options)
  def start_link(module, arg, options \\ []) when is_list(options), do:
    GenServer.start_link(__MODULE__,{options[:name] || self,module,arg}, options)

  
  def which_children(supervisor) do
    for {id,pid,worker,modules}<-Supervisor.which_children(supervisor) do
      {id,GenServer.call(pid,:delayed_pid),worker,modules}
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

    defdelegate [worker(mod,args), worker(mod,args,opts),
                 supervisor(mod,args), supervisor(mod,args,opts)], to: Supervisor.Spec
  end
end
